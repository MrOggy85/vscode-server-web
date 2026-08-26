# DNS egress is unrestricted

`init-firewall.sh:79-80` accepts `udp dport 53` and `tcp dport 53` to *any*
destination address.

Docker's embedded resolver lives on 127.0.0.11, which is already covered by the
`oifname "lo" accept` rule above it. So these two rules mainly enable DNS to
arbitrary external servers — a working data channel out of a design whose whole
point is an egress allowlist.

## Fix

Restrict `daddr` to the nameservers actually listed in `/etc/resolv.conf`,
resolved at firewall setup time.
