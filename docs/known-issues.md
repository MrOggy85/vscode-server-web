# Known issues

Accepted limitations and the reasoning for leaving them. Distinct from
[troubleshooting.md](troubleshooting.md), which covers problems that have a fix.

## DNS exfiltration through the configured resolver

**Applies to:** all setups.

Outbound DNS is restricted to the nameservers in the container's
`/etc/resolv.conf`, so a process cannot open a socket to a DNS server of its
choosing. It can still smuggle data out through the resolver it *is* allowed to
use: ask for `<data>.attacker.example`, and the resolver recursively walks down
to the attacker's own nameserver, passing the full name along.

**Why it is not fixed:** a packet filter matches addresses, not the names inside
the packet. Closing this needs a DNS proxy that refuses queries for names outside
`allowed-domains.txt`. A CONNECT proxy does not help — it resolves the name
before deciding to refuse the connection.

**Scope:** requires an attacker already executing code in the container, and the
channel is slow and conspicuous. The serious half — a direct two-way tunnel to
any nameserver on the internet — is closed.

## Mounted `settings.json` changes owner under `VSCODE_MATCH_HOST_UID=0`

**Applies to:** native Linux Docker, and only with `VSCODE_MATCH_HOST_UID=0` set.
Not the default. Does not occur on macOS.

The entrypoint chowns `~/.vscode-server/data` recursively so the server can write
its own state there. The mounted `settings.json` lives inside that directory, so
the chown reaches through the bind mount and changes the owner of the file in
your checkout of this repo.

By default this is invisible — the container runs as your uid, so the chown sets
the file to the uid that already owns it. With `VSCODE_MATCH_HOST_UID=0` the
container runs as 1000 instead, and the host file ends up owned by 1000. On macOS
the VM translates ownership, so it does not surface there either.

**Why it is not fixed** — each available fix costs more than the bug:

- Chowning `data` non-recursively is correct only because the image creates
  nothing else under it and `run.sh` recreates the container on every run.
  Neither is enforced, so a later change to either would silently leave files
  owned by the wrong uid and unwritable by the server.
- `find -xdev` does not help. It stops descent into mounted *directories*; a
  bind-mounted *file* is still listed and chowned.
- Mounting `settings.json` read-only breaks editing it through **Open Remote
  Settings JSON**, which the README documents as the authoritative source.

**If you hit it:** `chown "$(id -u):$(id -g)" settings.json` in the repo, and
drop `VSCODE_MATCH_HOST_UID=0` unless you specifically need it.
