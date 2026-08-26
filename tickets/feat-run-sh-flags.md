# `run.sh` command-line flags

`run.sh` takes exactly one positional argument and is otherwise configured only
through environment variables (`PORT`, `VSCODE_CONTAINER`, `VSCODE_CLI_VOLUME`,
`CLAUDE_VOLUME`, `VSCODE_EXTENSIONS_VOLUME`), none of which are discoverable from
the script itself.

Wanted:

- `--help` — there is none; the env vars are only documented in the source.
- `--port N` — equivalent to `PORT=N`.
- `--no-open` — skip the `open`/`xdg-open` at the end (`run.sh:120-124`).
- `--rebuild` — force a rebuild without having to touch a hashed file.

Related: `run.sh:66` unconditionally `docker rm -f`s the container, so re-running
it to reopen a project destroys and recreates a perfectly good instance. Consider
reusing a running container when nothing in the mount set has changed — or leave
that to `vsc open` (`feat-vsc-open-logs-restart.md`).
