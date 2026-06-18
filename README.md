# vscode-server-web

Runs VS Code Server (serve-web) in a Docker container, one container per project, with a stable per-project data volume.

## Requirements

- Docker (or Colima)

## Setup

Run once after cloning:

```bash
make init
```

This creates `install_additional_packages.sh` from the example file (gitignored — your edits stay local). See [Additional packages](#additional-packages) if you want to pre-install tools into the image.

## Usage

```bash
./run.sh [path/to/project]
```

Omit the path to open the current directory. The script derives a stable container name and port from the project path so concurrent projects don't collide. The image is built automatically on first run and rebuilt whenever `Dockerfile`, `entrypoint.sh`, or `install_additional_packages.sh` change.

## User settings

VS Code user settings are loaded from `settings.json` in this repo and mounted into the container at startup.

1. Copy the example file:
   ```bash
   cp settings.json.example settings.json
   ```
2. Edit `settings.json` to your preference.
3. `settings.json` is gitignored — your personal settings stay local.

Changes to `settings.json` take effect on the next `./run.sh` (the container is recreated each run).

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

## Caveats

**User Settings vs Remote Settings:** unlike a local VS Code install, "Open User Settings JSON" stores settings in the browser (per origin) and does not persist across devices or containers. The mounted `settings.json` is surfaced as "Open Remote Settings JSON" and is the persistent, authoritative source. Settings precedence: Machine (= Remote) > User > Workspace.

## Claude Code

Claude Code is pre-installed and available from the VS Code terminal. See [docs/claude.md](docs/claude.md) for authentication and usage details.

## Troubleshooting

See [docs/troubleshooting.md](docs/troubleshooting.md).
