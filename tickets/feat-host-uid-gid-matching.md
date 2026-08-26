# Match the container user to the host uid/gid

`Dockerfile:52` hardcodes `coder` to uid 1000. The project directory is
bind-mounted read-write at `/workspace` (`run.sh:106`), so on a host where the
user is not uid 1000 every file created or modified inside the container lands
with the wrong owner on the host.

## Fix

Pass the host's uid/gid in (`-e HOST_UID="$(id -u)" -e HOST_GID="$(id -g)"`) and
have the entrypoint `usermod`/`groupmod` `coder` to match before the `gosu` drop.
The entrypoint already runs as root at that point.

Note the existing chowns at `entrypoint.sh:87-88` would need to run after the
remap, not before.
