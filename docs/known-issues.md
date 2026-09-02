# Known issues

Accepted limitations and the reasoning for leaving them. Distinct from
[troubleshooting.md](troubleshooting.md), which covers problems that have a fix.

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
