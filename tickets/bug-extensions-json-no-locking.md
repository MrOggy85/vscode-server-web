# No locking on the shared `extensions.json`

`generate_keybindings_extension` (`entrypoint.sh:47-68`) does a read-modify-write
of `extensions.json` in the shared `vscode-extensions` volume, finishing with a
non-atomic `cat "$tmp" > "${ext_root}/extensions.json"`.

Nothing serialises this. Two concurrent `./run.sh` starts, or one instance
starting while another has an install in flight, can lose an update, which means
silently uninstalling extensions.

`docs/sharing-extensions.md` already warns about extension auto-update racing
this same file; the entrypoint has the same exposure and no mitigation.

## Fix

Take an `flock` around the read-modify-write, and replace the `cat >` with a
`mv` from a temp file on the same filesystem so the swap is atomic. Note the
`cat >` was deliberate (it avoids `sed -i` fchown errors); a `mv` plus explicit
chown achieves both.
