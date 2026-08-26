# `chown -R` changes ownership of the host's `settings.json`

`entrypoint.sh:87` recurses over `/home/coder/.vscode-server/data`, which
contains the bind-mounted `Machine/settings.json` from the repo root. The chown
follows into the bind mount and flips the *host* file to uid 1000.

`run.sh:84-86` reasons explicitly about why the read-only `.gitconfig` mount is
safe from this chown. `settings.json` is not: it sits under the data dir that
gets recursed.

Invisible when the host user is uid 1000, an ownership surprise otherwise.

## Fix

Chown the data dir's contents excluding the mounted settings file, or mount
`settings.json` read-only and drop it from the recursion.
