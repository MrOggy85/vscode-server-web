# IPv6 egress bypasses the firewall entirely

`init-firewall.sh:59` runs `nft flush ruleset`, then installs only
`table ip firewall` — IPv4. There is no `ip6` table, so no netfilter hook exists
for IPv6 and v6 output has no policy at all.

Compounding it, `refresh_allowlist` filters `dig +short` output with
`grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'` (`init-firewall.sh:26`), which
discards AAAA records — IPv6 was never in the allowlist's scope in the first
place.

Latent while Docker gives containers no IPv6, but it silently voids the whole
outbound allowlist the moment the daemon has `--ipv6` enabled or the container
joins an IPv6-capable network.

## Fix

Add a `table ip6 firewall` with `policy drop` on input/output/forward. Dropping
all v6 is sufficient if v6 egress is not wanted; otherwise mirror the v4 set and
collect AAAA records too.
