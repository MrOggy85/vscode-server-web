# Bumping Claude Code does not rebuild the image

`context_hash()` (`run.sh:17-23`) hashes `Dockerfile`, `entrypoint.sh`,
`install_additional_packages.sh`, `init-firewall.sh` and `allowed-domains.txt` —
but not `package.json`, `package-lock.json` or `.npmrc`, all of which are
`COPY`d into the image at `Dockerfile:55`.

`docs/CLAUDE.md` tells the user to regenerate the lock file and run `./run.sh` to
upgrade Claude Code. That is currently a no-op: the hash is unchanged, so no
rebuild happens and the old pinned version stays.

## Fix

Add the three npm files to the `files` array in `context_hash()`.
