# vscode-server-web

Runs VS Code Server (serve-web) in a Docker container, one container per project, with a stable per-project data volume.

## Requirements

- Docker (or Colima)

## Build

```bash
docker build -t vscode-serve-web:local .
```

## Usage

```bash
./run.sh [path/to/project]
```

Omit the path to open the current directory. The script derives a stable container name, data volume, and port from the project path, so concurrent projects don't collide.

## User settings

VS Code user settings are loaded from `settings.json` in this repo and mounted into the container at startup.

1. Copy the example file:
   ```bash
   cp settings.json.example settings.json
   ```
2. Edit `settings.json` to your preference.
3. `settings.json` is gitignored — your personal settings stay local.

Changes to `settings.json` take effect on the next `./run.sh` (the container is recreated each run).
