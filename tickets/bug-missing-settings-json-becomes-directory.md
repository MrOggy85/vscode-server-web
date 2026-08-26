# Fresh clone creates a directory named `settings.json`

`run.sh:107` mounts `$SCRIPT_DIR/settings.json` unconditionally, but the file is
gitignored and `make init` only creates `install_additional_packages.sh` and
`allowed-domains.txt`. On a fresh clone Docker auto-creates a *directory* at that
path, and VS Code gets no machine settings.

Every other optional mount in `run.sh` (`.bash_aliases`, `keybindings.json`,
`.gitconfig`, `.gitignore_global`) is `[ -f ]`-guarded. This one is not.

## Fix

Add `settings.json` to the `make init` target, and guard the mount with `[ -f ]`
like the others.
