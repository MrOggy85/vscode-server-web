#!/bin/bash
# Configures outbound firewall at container start (runs as root, before privilege drop).
# Uses nftables — works in containers with NET_ADMIN without requiring host kernel modules.
# Allowed domains are baked into the image at /etc/allowed-domains.txt — rebuild to change them.
set -euo pipefail

DOMAINS_FILE="/etc/allowed-domains.txt"

# The allowed hosts are CDN-fronted and rotate their IPs *within* a session
# (api.githubcopilot.com notably moves around GitHub's 140.82.112.0/20 block).
# A one-shot resolution at startup therefore goes stale: a later connection hits
# a freshly-rotated IP that was never added, and the reject rule below drops it.
# A background loop re-resolves the allowlist every REFRESH_SECS and tops up the
# nft set. Set to 0 to disable the refresher (startup resolution only).
REFRESH_SECS=30

log() { echo "[firewall] $*" >&2; }

# Resolve every hostname in $DOMAINS_FILE and add any new IPv4 addresses to the
# nft set. Pass "1" for verbose startup logging (one line per host); pass "0" for
# the background refresher, which logs only the IPs it newly adds.
refresh_allowlist() {
  local verbose="$1" domain ips ip
  while IFS= read -r domain || [[ -n "$domain" ]]; do
    [[ "$domain" =~ ^[[:space:]]*# || -z "${domain//[[:space:]]/}" ]] && continue
    ips=$(dig +short +timeout=5 "$domain" 2>/dev/null | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' || true)
    if [[ -z "$ips" ]]; then
      [[ "$verbose" == "1" ]] && log "warn: could not resolve $domain"
      continue
    fi
    while IFS= read -r ip; do
      if nft add element ip firewall allowed-ips "{ $ip }" 2>/dev/null && [[ "$verbose" != "1" ]]; then
        log "refresh: +$ip ($domain)"
      fi
    done <<< "$ips"
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

nft flush ruleset

# Base ruleset: output defaults to drop; reject rules at the bottom give fast
# failure (TCP RST or ICMP unreachable) instead of silent timeout.
nft -f - <<'NFT_EOF'
table ip firewall {
    set allowed-ips {
        type ipv4_addr
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
    nft add rule ip firewall input "$proto" dport "$port" accept
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
