# bash completion for `vsc`

`completions/_vsc` is zsh-only. `run.sh` and `entrypoint.sh` are both
`#!/usr/bin/env bash` and the container's shell is bash (`Dockerfile:52`), so a
bash user gets no completion at all.

## Fix

Add `completions/vsc.bash` mirroring the zsh one: subcommands and flags, plus
instance completion by container name and project folder name (the `docker ps`
+ `docker inspect` pair in `_vsc_instances`).

Document it alongside the zsh instructions in `docs/managing-instances.md`.
