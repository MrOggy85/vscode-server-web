#!/bin/bash
# Configures outbound firewall at container start (runs as root, before privilege drop).
# Uses nftables — works in containers with NET_ADMIN without requiring host kernel modules.
# Allowed domains are baked into the image at /etc/allowed-domains.txt — rebuild to change them.
#
# One dual-stack `inet` table, so a single ruleset governs IPv4 and IPv6. This
# matters: an `ip`-family table installs no IPv6 hook at all, so v6 output is
# unfiltered — the drop policy simply does not apply to it. The allowlist is
# resolved from A records only, so IPv6 has no accept rule and falls through to
# the reject at the bottom of the output chain. That is deliberate: v6 fails
# closed. Because the reject is immediate rather than a timeout, a dual-stack
# client falls straight back to IPv4 (Happy Eyeballs) and still reaches allowed
# hosts. A v6-only network would have no egress at all; add an ipv6_addr set and
# an AAAA lookup in refresh_allowlist if that is ever needed.
set -euo pipefail

DOMAINS_FILE="/etc/allowed-domains.txt"

# The allowed hosts are CDN-fronted and rotate their IPs *within* a session
# (api.githubcopilot.com notably moves around GitHub's 140.82.112.0/20 block).
# A one-shot resolution at startup therefore goes stale: a later connection hits
# a freshly-rotated IP that was never added, and the reject rule below drops it.
# A background loop re-resolves the allowlist every REFRESH_SECS and renews the
# nft set. Set to 0 to disable the refresher (startup resolution only); that also
# drops the element timeout below, since nothing would renew it.
REFRESH_SECS=30

log() { echo "[firewall] $*" >&2; }

# Resolve every hostname in $DOMAINS_FILE and add or renew its IPv4 addresses in
# the nft set. Pass "1" for verbose startup logging (one line per host); pass "0"
# for the background refresher, which logs only the IPs it newly adds.
refresh_allowlist() {
  local verbose="$1" domain ips ip txn
  while IFS= read -r domain || [[ -n "$domain" ]]; do
    [[ "$domain" =~ ^[[:space:]]*# || -z "${domain//[[:space:]]/}" ]] && continue
    ips=$(dig +short +timeout=5 "$domain" 2>/dev/null | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' || true)
    if [[ -z "$ips" ]]; then
      [[ "$verbose" == "1" ]] && log "warn: could not resolve $domain"
      continue
    fi
    # Re-adding an existing element is not guaranteed to reset its timer, so a
    # present address is deleted and re-added instead. Both statements ride one
    # `nft -f` transaction, so it is never momentarily absent from the set.
    txn=""
    while IFS= read -r ip; do
      if nft get element inet firewall allowed-ips "{ $ip }" >/dev/null 2>&1; then
        txn+="delete element inet firewall allowed-ips { $ip }"$'\n'
      elif [[ "$verbose" != "1" ]]; then
        log "refresh: +$ip ($domain)"
      fi
      txn+="add element inet firewall allowed-ips { $ip }"$'\n'
    done <<< "$ips"
    printf '%s' "$txn" | nft -f - 2>/dev/null || log "warn: could not update set for $domain"
    [[ "$verbose" == "1" ]] && log "$domain → $(echo "$ips" | tr '\n' ' ')"
  done < "$DOMAINS_FILE"
  return 0
}

# Detached re-invocation (setsid "$0" --refresh-loop <secs>): skip all nft
# setup and just keep the set current for the container's lifetime.
if [[ "${1:-}" == "--refresh-loop" ]]; then
  REFRESH_SECS="${2:-$REFRESH_SECS}"
  while sleep "$REFRESH_SECS"; do
    refresh_allowlist 0
  done
  exit 0
fi

# Comma-separated "<port>/<proto>" list of inbound ports to accept.
OPEN_PORTS="${1:-}"

if [[ ! -f "$DOMAINS_FILE" ]]; then
  log "no domains file at $DOMAINS_FILE — skipping"
  exit 0
fi

# Base ruleset: output defaults to drop; reject rules at the bottom give fast
# failure (TCP RST or ICMP unreachable) instead of silent timeout.
#
# Replaces only our own table, rather than `nft flush ruleset`. A full flush
# wipes every table in the container's network namespace, including the ones
# Docker installs there — the DNAT for the embedded DNS resolver (127.0.0.11:53)
# and the published-port DNAT. The bare `table inet firewall` line creates the
# table if it does not exist, so the `delete` on the next line never errors on a
# cold start. `nft -f` applies the whole file as one transaction.
#
# `ip daddr @allowed-ips` matches IPv4 only, which is what the allowlist holds;
# IPv6 packets fall through to the reject. See the header comment.

# Elements expire unless the refresher renews them, so an address that rotates
# away from an allowed host stops being permitted instead of lasting the
# container's lifetime. 10m is 20 refresh cycles of slack, so a transient DNS
# failure does not cut egress. No refresher means no renewal, hence no timeout.
SET_TIMEOUT=""
if (( REFRESH_SECS > 0 )); then
  SET_TIMEOUT="
        flags timeout
        timeout 10m"
fi

# Heredoc is unquoted for ${SET_TIMEOUT} — keep the ruleset free of $ and `.
nft -f - <<NFT_EOF
table inet firewall
delete table inet firewall

table inet firewall {
    set allowed-ips {
        type ipv4_addr${SET_TIMEOUT}
    }

    chain input {
        type filter hook input priority 0; policy drop;
        iifname "lo" accept
        ct state established,related accept
    }

    chain output {
        type filter hook output priority 0; policy drop;
        oifname "lo" accept
        ct state established,related accept
        udp dport 53 accept
        tcp dport 53 accept
        ip daddr @allowed-ips accept
        meta l4proto tcp reject with tcp reset
        reject
    }

    chain forward {
        type filter hook forward priority 0; policy drop;
    }
}
NFT_EOF

# Initial synchronous resolution so connectivity is up before code-server starts.
refresh_allowlist 1

# Inbound ports published to the host (docker run --publish) arrive on this
# container's input chain as NEW connections, which the drop policy would
# otherwise reject. Open each requested port explicitly.
if [[ -n "$OPEN_PORTS" ]]; then
  IFS=',' read -r -a _ports <<< "$OPEN_PORTS"
  for pp in ${_ports[@]+"${_ports[@]}"}; do
    port="${pp%%/*}"; proto="${pp##*/}"
    if [[ ! "$port" =~ ^[0-9]+$ ]] || (( 10#$port < 1 || 10#$port > 65535 )); then
      log "warn: ignoring invalid port spec '$pp'"; continue
    fi
    case "$proto" in tcp|udp) ;; *) log "warn: ignoring invalid proto in '$pp'"; continue ;; esac
    nft add rule inet firewall input "$proto" dport "$port" accept
    log "open inbound: ${port}/${proto}"
  done
fi

REFRESH_LOG="/tmp/firewall-refresh.log"
if (( REFRESH_SECS > 0 )); then
  setsid "$0" --refresh-loop "$REFRESH_SECS" </dev/null >>"$REFRESH_LOG" 2>&1 &
  disown 2>/dev/null || true
  log "refresher started (every ${REFRESH_SECS}s) → $REFRESH_LOG"
fi

log "ready"
