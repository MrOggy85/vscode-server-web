# Managing instances (`vsc`)

`vsc` is a CLI for listing and tearing down the VS Code containers that `run.sh`
creates. An **instance** is a single container named `vscode-<folder>-<hash>`.

## What an instance is made of

Each container started by `run.sh` mounts:

- the **project folder** as a bind mount at `/workspace` — this is your real
  source code on disk. `vsc` never deletes it.
- **`vscode-cli`** — a named volume holding the downloaded VS Code server.
  Shared by every instance.
- **`vscode-claude-credentials`** — a named volume holding Claude Code auth.
  Shared by every instance (see [claude.md](claude.md)).

Both named volumes are **shared**, so removing them affects every project. `vsc`
is built around this: it never touches the workspace bind mount, and it protects
the two shared volumes.

## Commands

```bash
./vsc ls                      # list instances: status, port, folder, volumes
./vsc stop       <selector>   # stop and remove a running instance (container only)
./vsc rm-volumes <selector>   # remove the named volumes attached to an instance
./vsc destroy    <selector>   # stop the instance, then remove its volumes
```

`<selector>` matches an exact container name, or a substring of the container
name **or** the project folder name — so `./vsc stop myproject` works. If a
selector matches more than one instance, `vsc` lists them and aborts.

### Flags

- `-y`, `--yes` — skip confirmation prompts.
- `-f`, `--force` — also remove volumes shared with *other* instances
  (`rm-volumes` only; see the protected-volume note below).
- `--no-color` — disable colour.

### Colour

Output is colour-coded: cyan for the thing being named (container, volume,
path), green for a completed action, yellow for a skip, bold red for an error,
dim for structure and hints. In `vsc ls` the status column is green for
`running`, yellow for `created`/`paused`/`restarting`, red for `dead`, dim
otherwise.

Colour is decided per stream, so `vsc ls | less` drops it from the table while
warnings on the still-attached stderr keep it. `NO_COLOR=1` (or `--no-color`)
turns it off, `CLICOLOR_FORCE=1` turns it on regardless, and `TERM=dumb`
disables it.

## How removal stays safe

- **Workspace folder** — a bind mount, never removed.
- **`vscode-cli` and `vscode-claude-credentials`** — `destroy` always **keeps**
  these, even with `--force`, so the next run reuses the VS Code server and your
  Claude credentials instead of re-downloading / re-authenticating.
- **Volumes used by other instances** — skipped by default. Pass `--force` to
  remove them anyway (Docker still refuses to delete a volume held by a running
  container).

In practice, because the two shared volumes are kept, `destroy` removes the
container plus any *per-project* named volumes — of which there are none unless
you override `VSCODE_CLI_VOLUME` / `CLAUDE_VOLUME` per project.

## Examples

```bash
./vsc ls
# CONTAINER                    STATUS    PORT    FOLDER                  VOLUMES
# vscode-myapp-1a2b3c4d5e      running   24817   /Users/me/code/myapp    vscode-cli,vscode-claude-credentials

./vsc stop myapp               # stop + remove just the container
./vsc destroy myapp -y         # remove the container, keep shared volumes, no prompt
```

## Shell completion

`vsc` ships a zsh completion at `completions/_vsc`. After `./vsc ` press Tab for
subcommands; after `./vsc stop ` press Tab to list live instances by container
name and folder name.

Install (zsh, Homebrew) by symlinking it onto your existing `fpath`:

```zsh
ln -s "$PWD/completions/_vsc" "$(brew --prefix)/share/zsh/site-functions/_vsc"
rm -f ~/.zcompdump*
exec zsh
```
