# Known issues

Accepted limitations and the reasoning for leaving them. Distinct from
[troubleshooting.md](troubleshooting.md), which covers problems that have a fix.

## An agent with MCP write access can exfiltrate data

**Applies to:** all setups. Inherent to giving an agent tool access, not a defect
in the firewall.

The outbound allowlist has to include the endpoints the agent needs, and some of
those accept writes. `api.githubcopilot.com` (GitHub MCP) can create a public
gist or issue comment. `mcp.atlassian.com` can create a page.
`sheets.googleapis.com` can write a sheet. Anything written to a public
destination is readable by whoever planted the instruction.

The realistic vector is prompt injection: the agent reads untrusted content (an
issue body, a dependency README, a web page) carrying instructions to send
secrets somewhere. That fires during a session where the agent legitimately holds
those credentials, so time-boxing the allowlist does not help. The window is open
exactly when it is exploitable.

**Why it is not fixed:** the firewall cannot tell a wanted write from an unwanted
one, and removing the endpoint removes the feature. Exfiltration needs three
things present at once: private data, untrusted content, and a channel out. Only
the last two are negotiable, and the channel is the reason the agent is useful.

**What actually limits it:**

- Keep MCP write tools behind permission prompts. Allowlisting a read-only tool
  such as `get_file_contents` is safe; allowlisting `issue_write` is not.
- Scope the GitHub token. Fine-grained tokens cannot use the gist API at all,
  which removes the easiest public destination.
- Consider a read-only MCP server by default, adding a write-capable one only for
  sessions that need it. Unlike a time-boxed firewall rule, this survives
  injection, because the capability is absent rather than merely unused.

**Where the firewall still earns its place:** a compromised dependency reaching
for an arbitrary command-and-control host is rejected, because that host is not
on the allowlist.

## DNS exfiltration through the configured resolver

**Applies to:** all setups. Strictly less serious than the entry above.

Outbound DNS is restricted to the nameservers in the container's
`/etc/resolv.conf`, so a process cannot open a socket to a DNS server of its
choosing. It can still smuggle data out through the resolver it *is* allowed to
use: ask for `<data>.attacker.example`, and the resolver recursively walks down
to the attacker's own nameserver, passing the full name along.

**Why it is not fixed:** a packet filter matches addresses, not the names inside
the packet. Closing this needs a filtering resolver that refuses names outside
`allowed-domains.txt`. A CONNECT proxy does not help, because it resolves the
name before deciding to refuse the connection.

**Scope:** requires an attacker already executing code in the container, and the
channel is slow and conspicuous. Anyone in that position prefers the MCP write
channels above, which are faster and bidirectional; DNS tunnelling is the
fallback when nothing else is reachable. The serious half, a direct two-way
tunnel to any nameserver on the internet, is closed.

## A concurrent extension install can be lost from the registry

**Applies to:** only when `keybindings.json` is mounted, since nothing else makes
the entrypoint touch the registry.

`extensions.json` in the shared `vscode-extensions` volume lists the installed
extensions. At startup the entrypoint reads it, adds the generated keybindings
extension, and writes the whole file back. Anything that changes the file in the
few hundredths of a second between that read and write is overwritten, because
the write is based on the copy read a moment earlier.

In practice that means installing an extension in one instance at the same moment
another instance starts. The newly installed extension disappears from the
Extensions view.

**Why it is not fixed:** a lock would only serialise this repo's own entrypoints
against each other, which needs two `./run.sh` invocations inside the same
fraction of a second and is not reachable by hand. It cannot help against the
case that actually occurs, because the VS Code server writes the file too and
does not participate in any locking scheme added here. The mitigations that would
help, skipping the write when the content is unchanged and swapping the file in
atomically, are real but add moving parts to a startup path for something this
rare. See also the auto-update warning in
[sharing-extensions.md](sharing-extensions.md).

**If you hit it:** reinstall the extension. Only its registry entry is lost; the
extension's files are still in the volume.

## Mounted `settings.json` changes owner under `VSCODE_MATCH_HOST_UID=0`

**Applies to:** native Linux Docker, and only with `VSCODE_MATCH_HOST_UID=0` set.
Not the default. Does not occur on macOS.

The entrypoint chowns `~/.vscode-server/data` recursively so the server can write
its own state there. The mounted `settings.json` lives inside that directory, so
the chown reaches through the bind mount and changes the owner of the file in
your checkout of this repo.

By default this is invisible, because the container runs as your uid and the
chown sets the file to the uid that already owns it. With
`VSCODE_MATCH_HOST_UID=0` the container runs as 1000 instead, and the host file
ends up owned by 1000. On macOS the VM translates ownership, so it does not
surface there either.

**Why it is not fixed** (each available fix costs more than the bug):

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
