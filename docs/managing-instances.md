# Managing instances (`vsc`)

`vsc` is a CLI for listing and tearing down the VS Code containers that `run.sh`
creates. An **instance** is a single container named `vscode-<folder>-<hash>`.

## What an instance is made of

Each container started by `run.sh` mounts:

- the **project folder** as a bind mount at `/workspace`: this is your real
  source code on disk. `vsc` never deletes it.
- **`vscode-cli`**: a named volume holding the downloaded VS Code server.
  Shared by every instance.
- **`vscode-claude-credentials`**: a named volume holding Claude Code auth.
  Shared by every instance (see [claude.md](claude.md)).
- **`vscode-extensions`**: a named volume holding the installed extensions.
  Shared by every instance (see [sharing-extensions.md](sharing-extensions.md)).

All three named volumes are **shared**, so removing them affects every project.
`vsc` is built around this: it never touches the workspace bind mount, and it
protects the shared volumes.

## Commands

`./vsc --help` lists the commands, the selector syntax and the flags.

## Colour

Output is colour-coded: cyan for the thing being named (container, volume,
path), green for a completed action, yellow for a skip, bold red for an error,
dim for structure and hints.

In `vsc ls` the STATUS column reports **health** rather than state while a
container is running, so `healthy`, `starting` or `unhealthy` instead of
`running`. That distinction is the point: `running` only means the process
exists, which says nothing about whether the server answers. A plain `running`
means the image predates the `HEALTHCHECK`. Green for `running`/`healthy`,
yellow for `starting` and other transitional states, bold red for
`unhealthy`/`dead`, dim otherwise.

The check fetches `/` from inside the container, so it catches a dead, deaf or
erroring server. It will not catch one stuck fetching its bundle, because the
CLI serves a page throughout that (see
[vscode-quirks.md](vscode-quirks.md)).

Colour is decided per stream, so `vsc ls | less` drops it from the table while
warnings on the still-attached stderr keep it. `NO_COLOR=1` (or `--no-color`)
turns it off, `CLICOLOR_FORCE=1` turns it on regardless, and `TERM=dumb`
disables it.

## How removal stays safe

- **Workspace folder**: a bind mount, never removed.
- **`vscode-cli`, `vscode-claude-credentials` and `vscode-extensions`**:
  `destroy` always **keeps** these, even with `--force`, so the next run reuses
  the VS Code server, your Claude credentials and your installed extensions
  instead of re-downloading / re-authenticating / reinstalling.
- **Volumes used by other instances**: skipped by default. Pass `--force` to
  attempt them anyway, but note that this only bypasses `vsc`'s own guard: Docker
  still refuses to delete a volume another container references, so a `--force`
  removal of a genuinely shared volume reports `could not remove`. Stop the other
  instances first.

In practice, because the shared volumes are kept, `destroy` removes the
container plus any *per-project* named volumes, of which there are none unless
you override `VSCODE_CLI_VOLUME` / `CLAUDE_VOLUME` /
`VSCODE_EXTENSIONS_VOLUME` per project.

## Examples

```bash
./vsc ls
# CONTAINER                    STATUS    PORT    FOLDER                  VOLUMES
# vscode-myapp-1a2b3c4d5e      running   24817   /Users/me/code/myapp    vscode-cli,vscode-claude-credentials,vscode-extensions

./vsc destroy myapp -y         # selector is a substring; -y skips the prompt
```

## Shell completion

**zsh only**: `completions/_vsc` uses zsh's `compdef`/`_arguments` and has no
bash equivalent. Deliberate, not an oversight; `vsc` itself works under any shell.

After `./vsc ` press Tab for subcommands; after `./vsc stop ` press Tab to list
live instances by container and folder name.

Install (zsh, Homebrew) by symlinking it onto your existing `fpath`:

```zsh
ln -s "$PWD/completions/_vsc" "$(brew --prefix)/share/zsh/site-functions/_vsc"
rm -f ~/.zcompdump*
exec zsh
```
