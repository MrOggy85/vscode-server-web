#!/usr/bin/env bash
set -euo pipefail

IMAGE="vscode-serve-web:local"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat <<'EOF'
Usage: run.sh [options] [path/to/project]

Starts a VS Code Server (serve-web) container for a project, building the image
first if the build context changed. Defaults to the current directory.

Options:
  -h, --help       show this help
      --port N     host port to publish on (default: derived from the project path)
      --no-open    do not open a browser afterwards
      --rebuild    rebuild the image even if the build context is unchanged

Environment:
  PORT                     same as --port, which wins if both are given
  VSCODE_MATCH_HOST_UID    0 to run as the image's fixed 1000:1000 instead of your uid:gid
  VSCODE_CONTAINER         override the derived container name
  VSCODE_CLI_VOLUME        volume holding the downloaded VS Code server (default: vscode-cli)
  VSCODE_EXTENSIONS_VOLUME volume holding installed extensions (default: vscode-extensions)
  CLAUDE_VOLUME            volume holding Claude Code credentials (default: vscode-claude-credentials)
EOF
}

NO_OPEN=0
FORCE_REBUILD=0
PORT_FLAG=""
POS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage; exit 0;;
    --no-open) NO_OPEN=1; shift;;
    --rebuild) FORCE_REBUILD=1; shift;;
    --port)
      [[ $# -ge 2 ]] || { echo "run.sh: --port needs a value" >&2; exit 1; }
      PORT_FLAG="$2"; shift 2;;
    --port=*)  PORT_FLAG="${1#*=}"; shift;;
    --)        shift; while [[ $# -gt 0 ]]; do POS+=("$1"); shift; done;;
    -*)        echo "run.sh: unknown option: $1" >&2; usage >&2; exit 1;;
    *)         POS+=("$1"); shift;;
  esac
done

if [[ ${#POS[@]} -gt 1 ]]; then
  echo "run.sh: expected at most one project path, got ${#POS[@]}" >&2
  exit 1
fi
if [[ -n "$PORT_FLAG" ]]; then
  if [[ ! "$PORT_FLAG" =~ ^[0-9]+$ ]] || (( 10#$PORT_FLAG < 1 || 10#$PORT_FLAG > 65535 )); then
    echo "run.sh: --port must be 1-65535, got '$PORT_FLAG'" >&2
    exit 1
  fi
fi

PROJECT_ARG="."
[[ ${#POS[@]} -eq 1 ]] && PROJECT_ARG="${POS[0]}"
[ -d "$PROJECT_ARG" ] || { echo "run.sh: not a directory: $PROJECT_ARG" >&2; exit 1; }
PROJECT_DIR="$(cd "$PROJECT_ARG" && pwd)"

# Stable per-project names: vscode-<dirname>-<short hash of full path>.
# The hash disambiguates same-named dirs in different locations.
sha256() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$@"
  else shasum -a 256 "$@"; fi
}

# Every file the image is built from. Anything COPY'd by the Dockerfile belongs
# here, or editing it will not rebuild: the npm trio pins the Claude Code and
# TypeScript versions, and docs/CLAUDE.md documents `./run.sh` as the way to
# apply a version bump.
#
# .github/workflows/build.yml gates its CI build on the same set. Add a file
# here and it needs adding there too, or CI will not build the change.
context_hash() {
  local files=(
    "${SCRIPT_DIR}/Dockerfile"
    "${SCRIPT_DIR}/entrypoint.sh"
    "${SCRIPT_DIR}/install_additional_packages.sh"
    "${SCRIPT_DIR}/init-firewall.sh"
    "${SCRIPT_DIR}/allowed-domains.txt"
    "${SCRIPT_DIR}/package.json"
    "${SCRIPT_DIR}/package-lock.json"
    "${SCRIPT_DIR}/.npmrc"
  )
  local existing=()
  for f in "${files[@]}"; do [ -f "$f" ] && existing+=("$f"); done
  sha256 "${existing[@]}" | sha256 | cut -c1-16
}

CURRENT_HASH="$(context_hash)"
IMAGE_HASH="$(docker image inspect "${IMAGE}" --format '{{index .Config.Labels "build.context-hash"}}' 2>/dev/null || true)"

if [[ "$FORCE_REBUILD" == 1 || "$IMAGE_HASH" != "$CURRENT_HASH" ]]; then
  if [[ "$FORCE_REBUILD" == 1 ]]; then echo ">> --rebuild: building ${IMAGE}..."
  elif [[ -n "$IMAGE_HASH" ]];    then echo ">> build context changed, rebuilding ${IMAGE}..."
  else                                 echo ">> image not found, building ${IMAGE}..."
  fi
  docker build --tag "${IMAGE}" --label "build.context-hash=${CURRENT_HASH}" "${SCRIPT_DIR}"
fi

path_hash() {
  printf '%s' "$1" | sha256 | cut -c1-10
}
SAFE_NAME="$(printf '%s' "$(basename "${PROJECT_DIR}")" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9' '-')"
SAFE_NAME="$(printf '%s' "${SAFE_NAME}" | sed -e 's/-\{2,\}/-/g' -e 's/^-//' -e 's/-$//')"
HASH="$(path_hash "${PROJECT_DIR}")"

CONTAINER="${VSCODE_CONTAINER:-vscode-${SAFE_NAME:-repo}-${HASH}}"
CLI_VOLUME="${VSCODE_CLI_VOLUME:-vscode-cli}"
CLAUDE_VOLUME="${CLAUDE_VOLUME:-vscode-claude-credentials}"
# Installed extensions, shared across every instance: install once, available in
# all containers. Enable/disable stays per-container because extension
# enablement is User-scoped state, which in serve-web lives in the browser's
# IndexedDB, and each instance has its own port, hence its own origin.
EXTENSIONS_VOLUME="${VSCODE_EXTENSIONS_VOLUME:-vscode-extensions}"
PROJECT_NAME="$(basename "${PROJECT_DIR}")"

# Derive a stable default port in 10000-59999 from the path hash. Precedence:
# --port, then PORT, then the derived default.
DEFAULT_PORT=$(( 10000 + ( 0x$(printf '%s' "${HASH}" | cut -c1-4) % 50000 ) ))
PORT="${PORT_FLAG:-${PORT:-$DEFAULT_PORT}}"

# Run as your uid:gid so files the container writes into the project are yours.
# Otherwise it writes as 1000, and another container running as your uid cannot
# modify what it created (a pnpm-installed node_modules, say).
# VSCODE_MATCH_HOST_UID=0 restores the fixed 1000:1000.
if [[ "${VSCODE_MATCH_HOST_UID:-1}" == "1" ]]; then
  HOST_UID="$(id -u)"
  HOST_GID="$(id -g)"
else
  HOST_UID=1000
  HOST_GID=1000
fi

echo ">> container:  ${CONTAINER}"
echo ">> user:       ${HOST_UID}:${HOST_GID}"
echo ">> cli volume: ${CLI_VOLUME}"
echo ">> ext volume: ${EXTENSIONS_VOLUME}"
echo ">> port:       ${PORT}"
echo ">> project:    ${PROJECT_NAME}"

echo ">> killing any running container..."
docker rm -f "$CONTAINER" >/dev/null 2>&1 || true

optional_mounts=()

# VS Code Machine settings, surfaced in the UI as "Remote Settings". Guarded like
# every other mount here rather than passed unconditionally: Docker materialises a
# *directory* for a bind source that does not exist, so an unconditional mount
# silently creates a `settings.json/` directory in the repo root on a fresh clone
# and VS Code ends up with no machine settings at all. `make init` creates the
# file, so the warning below only fires if it was skipped or deleted.
if [ -f "${SCRIPT_DIR}/settings.json" ]; then
  optional_mounts+=(-v "${SCRIPT_DIR}/settings.json:/home/coder/.vscode-server/data/Machine/settings.json")
else
  echo ">> note: no settings.json, starting without machine settings"
  echo ">>       create one with 'make init' (or cp settings.json.example settings.json)"
fi

# Shell aliases for the integrated terminal. Optional, only mounted when the
# file exists.
[ -f "${SCRIPT_DIR}/.bash_aliases" ] \
  && optional_mounts+=(-v "${SCRIPT_DIR}/.bash_aliases:/home/coder/.bash_aliases")

# Keybindings can't be mounted like settings.json: VS Code keybindings are
# strictly User-scoped (no Machine path), and in serve-web User data lives in
# the browser, not the filesystem. Instead we hand the raw file to the
# entrypoint, which turns it into a keybinding-contributing extension on the
# server side. Optional, only mounted when the file exists.
[ -f "${SCRIPT_DIR}/keybindings.json" ] \
  && optional_mounts+=(-v "${SCRIPT_DIR}/keybindings.json:/home/coder/keybindings.json")

# git identity (user.name / user.email) for git inside the container. Mounted
# read-only: the entrypoint's chown is scoped to the volume/server paths and
# never touches this file, so :ro is safe and nothing writes to it. Optional,
# only mounted when the file exists.
[ -f "${SCRIPT_DIR}/.gitconfig" ] \
  && optional_mounts+=(-v "${SCRIPT_DIR}/.gitconfig:/home/coder/.gitconfig:ro")

# Global (user-level) gitignore. Mounted read-only at ~/.config/git/ignore, which
# git reads automatically when core.excludesFile is unset (the XDG convention), so
# no .gitconfig entry is required. Optional, only mounted when the file exists.
[ -f "${SCRIPT_DIR}/.gitignore_global" ] \
  && optional_mounts+=(-v "${SCRIPT_DIR}/.gitignore_global:/home/coder/.config/git/ignore:ro")

echo ">> run new container..."
docker run -d \
  --name "$CONTAINER" \
  --restart unless-stopped \
  -p "127.0.0.1:${PORT}:${PORT}" \
  -e PORT="$PORT" \
  -e PROJECT_NAME="$PROJECT_NAME" \
  -e HOST_UID="$HOST_UID" \
  -e HOST_GID="$HOST_GID" \
  -v "${CLI_VOLUME}:/home/coder/.vscode" \
  -v "${CLAUDE_VOLUME}:/home/coder/.claude" \
  -v "${EXTENSIONS_VOLUME}:/home/coder/.vscode-server/extensions" \
  -v "$PROJECT_DIR:/workspace" \
  "${optional_mounts[@]+"${optional_mounts[@]}"}" \
  --cap-drop ALL \
  --cap-add CHOWN --cap-add DAC_OVERRIDE --cap-add SETUID --cap-add SETGID \
  --cap-add NET_ADMIN \
  --security-opt no-new-privileges:true \
  "$IMAGE" >/dev/null

URL="http://127.0.0.1:${PORT}/?folder=/workspace"
echo ">> Container started."
echo ">> Open: $URL"

# Open the browser automatically (macOS uses `open`, Linux uses `xdg-open`).
if [[ "$NO_OPEN" == 0 ]]; then
  if command -v open >/dev/null 2>&1; then
    open "$URL" 2>/dev/null || true
  elif command -v xdg-open >/dev/null 2>&1; then
    xdg-open "$URL" 2>/dev/null || true
  fi
fi
