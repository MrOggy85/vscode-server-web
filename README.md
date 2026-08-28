# vscode-server-web

[![Lint](https://github.com/MrOggy85/vscode-server-web/actions/workflows/lint.yml/badge.svg)](https://github.com/MrOggy85/vscode-server-web/actions/workflows/lint.yml) [![Build](https://github.com/MrOggy85/vscode-server-web/actions/workflows/build.yml/badge.svg)](https://github.com/MrOggy85/vscode-server-web/actions/workflows/build.yml)

Runs VS Code Server (serve-web) in a Docker container, one container per project, with a stable per-project data volume.

## Requirements

- Docker (or Colima)

## Setup

Run once after cloning:

```bash
make init
```

This creates `install_additional_packages.sh`, `allowed-domains.txt` and `settings.json` from their example files. All three are gitignored — your edits stay local. Existing files are left alone, so it is safe to re-run.

See [Additional packages](#additional-packages) if you want to pre-install tools into the image.

## Usage

```bash
./run.sh [path/to/project]
```

Omit the path to open the current directory. The script derives a stable container name and port from the project path so concurrent projects don't collide.

The image is built automatically on first run, and rebuilt whenever any file it is built from changes: `Dockerfile`, `entrypoint.sh`, `init-firewall.sh`, `install_additional_packages.sh`, `allowed-domains.txt`, `package.json`, `package-lock.json`, `.npmrc`. Files that are *mounted* rather than baked in — `settings.json`, `keybindings.json`, `.gitconfig`, `.gitignore_global`, `.bash_aliases` — take effect on the next run without a rebuild.

## User settings

VS Code user settings are loaded from `settings.json` in this repo and mounted into the container at startup.

`make init` creates it from `settings.json.example`; edit it to your preference. It is gitignored, so your personal settings stay local.

Changes take effect on the next `./run.sh` (the container is recreated each run).

If the file is missing, `run.sh` says so and starts without machine settings rather than mounting a nonexistent path — Docker would otherwise materialise a `settings.json/` *directory* in the repo root.

## Keybindings

Keybindings can't be mounted like `settings.json`. VS Code keybindings are strictly *User-scoped* (there is no Machine-scope keybindings file), and in `serve-web` all User data lives in the browser, not on the server filesystem — so a mounted `keybindings.json` is simply never read. See [docs/vscode-quirks.md](docs/vscode-quirks.md) for the full explanation.

Instead, the keybindings are applied across all containers via a small server-side extension that the entrypoint generates from your `keybindings.json` at startup.

1. Copy the example file:
   ```bash
   cp keybindings.json.example keybindings.json
   ```
2. Edit `keybindings.json` — it is a plain JSON array of `{ "key", "command" }` entries, same as VS Code's `keybindings.json` (no `//` comments — it is parsed as strict JSON).
3. `keybindings.json` is gitignored — your personal bindings stay local.

Changes take effect on the next `./run.sh`. The file is mounted (not baked into the image), so editing it does not trigger a rebuild.

## Git identity

Set the git `user.name` / `user.email` used by git inside the container via a `.gitconfig` in the repo root. It is mounted read-only over `~/.gitconfig` in the container.

1. Copy the example file:
   ```bash
   cp .gitconfig.example .gitconfig
   ```
2. Edit `.gitconfig` with your name and email.
3. `.gitconfig` is gitignored — your identity stays local.

Changes take effect on the next `./run.sh`. The file is mounted (not baked into the image), so editing it does not trigger a rebuild.

## Global gitignore

Optional user-level gitignore applied to every repo in the container. `cp .gitignore_global.example .gitignore_global`, then edit. Mounted read-only at `~/.config/git/ignore` (read automatically via the XDG convention). Gitignored; mounted only when it exists.

## Additional packages

`install_additional_packages.sh` is a gitignored script that runs during image build. Use it to install any tools your projects need. Example:

```bash
#!/bin/bash
set -euo pipefail

# Deno
curl -fsSL https://deno.land/install.sh | DENO_INSTALL=/usr/local sh -s v2.3.1

# nvm
NVM_DIR="/home/coder/.nvm" HOME="/home/coder" \
  curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash
```

The image is rebuilt automatically by `run.sh` whenever this file changes.

## File ownership

The container runs as your host uid:gid, so anything it writes into the project — a `pnpm install`, a build output — is owned by you rather than by the container's internal user.

This matters most when another container works on the same project. If it runs as your uid — `--user "$(id -u):$(id -g)"` — and this one had written as a different uid, it could not modify a `node_modules` installed here.

On macOS the mismatch is easy to miss, because it is invisible from the Mac side: the VM performs writes as your host user, so `ls -l` on macOS looks correct whatever uid wrote the file. Inside the Linux VM the file still carries the writing container's uid, which is where the conflict shows up.

Set `VSCODE_MATCH_HOST_UID=0` to go back to the fixed internal `1000:1000`.

## Caveats

**User Settings vs Remote Settings:** unlike a local VS Code install, "Open User Settings JSON" stores settings in the browser (per origin) and does not persist across devices or containers. The mounted `settings.json` is surfaced as "Open Remote Settings JSON" and is the persistent, authoritative source. Settings precedence: Machine (= Remote) > User > Workspace.

## Managing instances

`./vsc` lists, stops, and tears down running instances and their volumes. See [docs/managing-instances.md](docs/managing-instances.md).

## Claude Code

Claude Code is pre-installed and available from the VS Code terminal. See [docs/claude.md](docs/claude.md) for authentication and usage details.

## Extensions

Installed extensions live in the shared `vscode-extensions` volume, so you install an extension once and every instance has it. Enable/disable is per instance — extension enablement is stored in the browser, and each instance has its own port, hence its own origin. Use **Disable** rather than Uninstall to turn one off for a single project; uninstalling removes it everywhere. See [docs/sharing-extensions.md](docs/sharing-extensions.md).

Marketplace extensions download their package bytes from a per-publisher CDN host that the outbound firewall blocks by default — installs fail with `ECONNREFUSED` until you allowlist that host. See [docs/installing-extensions.md](docs/installing-extensions.md).

## Troubleshooting

See [docs/troubleshooting.md](docs/troubleshooting.md).

## Development

```bash
make lint
```

Shellchecks every script in the repo, and checks that `run.sh` and `vsc` are still executable. CI runs the same target on push and PR, so a green `make lint` locally means a green CI. It needs no `make init` — only committed files are linted.

CI also builds the image and smoke-tests it, but only when a file the image is built from changes — the same set that triggers a local rebuild.
