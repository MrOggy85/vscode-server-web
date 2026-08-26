# Port collisions are unhandled

`run.sh:56` derives the default port from `0x<4 hex chars of path hash> % 50000`.
Two different projects can collide. When they do, `docker run -p` fails with
Docker's raw `port is already allocated` and `run.sh` exits under `set -e`.

Worse: `run.sh:66` has already `docker rm -f`'d the container by that point, so a
collision leaves the user with no instance and an opaque error.

## Fix

Probe the derived port before starting and increment until a free one is found;
report the port actually used.
