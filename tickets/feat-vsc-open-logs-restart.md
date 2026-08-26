# `vsc open` / `logs` / `restart`, and a URL column in `ls`

`vsc` covers teardown (`stop`, `rm-volumes`, `destroy`) but nothing for the
day-to-day of using a running instance.

- `vsc open <selector>` — open the instance URL in a browser. Today the URL is
  only printed by `run.sh` at start; getting back to it means re-running
  `run.sh` (which destroys and recreates the container) or reading the port out
  of `vsc ls` and assembling the URL by hand.
- `vsc url <selector>` — print it, for piping.
- `vsc logs <selector>` — `docker logs`, with `-f`.
- `vsc restart <selector>` — restart in place. Currently the only way to pick up
  a new extension or an edited `keybindings.json` is a full `run.sh`.
- A URL column in `vsc ls`, or make the port column a full clickable URL.

`port_of()` and `folder_of()` already exist, so most of this is assembly.

Remember to extend `completions/_vsc` with the new subcommands.
