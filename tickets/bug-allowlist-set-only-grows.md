# Firewall allowlist only ever grows

`refresh_allowlist` (`init-firewall.sh:22-39`) adds resolved IPs to the nft set
and never removes any. Over a long-lived container the set grows unbounded, and —
more importantly — an address that gets reassigned away from an allowed CDN host
stays permitted for the container's whole lifetime.

## Fix

Give the set an element timeout and let the existing 30s refresher renew live
entries:

```
set allowed-ips {
    type ipv4_addr
    flags timeout
    timeout 10m
}
```
