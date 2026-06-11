set -euo pipefail

IMAGE="vscode-serve-web:local"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PROJECT_DIR="$(cd "${1:-.}" && pwd)"

# Stable per-project names: vscode-<dirname>-<short hash of full path>.
# Same approach as claude-in-docker/run.sh — hash disambiguates same-named dirs.
sha256() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$@"
  else shasum -a 256 "$@"; fi
}

context_hash() {
  local files=(
    "${SCRIPT_DIR}/Dockerfile"
    "${SCRIPT_DIR}/entrypoint.sh"
    "${SCRIPT_DIR}/install_additional_packages.sh"
  )
  local existing=()
  for f in "${files[@]}"; do [ -f "$f" ] && existing+=("$f"); done
  sha256 "${existing[@]}" | sha256 | cut -c1-16
}

CURRENT_HASH="$(context_hash)"
IMAGE_HASH="$(docker image inspect "${IMAGE}" --format '{{index .Config.Labels "build.context-hash"}}' 2>/dev/null || true)"

if [[ "$IMAGE_HASH" != "$CURRENT_HASH" ]]; then
  [[ -n "$IMAGE_HASH" ]] && echo ">> build context changed — rebuilding ${IMAGE}..." \
                          || echo ">> image not found — building ${IMAGE}..."
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
PROJECT_NAME="$(basename "${PROJECT_DIR}")"

# Derive a stable default port in 8000-8999 from the path hash; override with PORT=...
DEFAULT_PORT=$(( 8000 + ( 0x$(printf '%s' "${HASH}" | cut -c1-3) % 1000 ) ))
PORT="${PORT:-$DEFAULT_PORT}"

echo ">> container:  ${CONTAINER}"
echo ">> cli volume: ${CLI_VOLUME}"
echo ">> port:       ${PORT}"
echo ">> project:    ${PROJECT_NAME}"

echo ">> killing any running container..."
docker rm -f "$CONTAINER" >/dev/null 2>&1 || true

echo ">> run new container..."
docker run -d \
  --name "$CONTAINER" \
  --restart unless-stopped \
  -p "127.0.0.1:${PORT}:${PORT}" \
  -e PORT="$PORT" \
  -e PROJECT_NAME="$PROJECT_NAME" \
  -v "${CLI_VOLUME}:/home/coder/.vscode" \
  -v "$PROJECT_DIR:/workspace" \
  -v "$SCRIPT_DIR/settings.json:/home/coder/.vscode-server/data/Machine/settings.json" \
  --cap-drop ALL \
  --cap-add CHOWN --cap-add DAC_OVERRIDE --cap-add SETUID --cap-add SETGID \
  --security-opt no-new-privileges:true \
  "$IMAGE" >/dev/null

URL="http://127.0.0.1:${PORT}/?folder=/workspace"
echo ">> Container started."
echo ">> Open: $URL"

# Open the browser automatically (macOS uses `open`, Linux uses `xdg-open`).
if command -v open >/dev/null 2>&1; then
  open "$URL" 2>/dev/null || true
elif command -v xdg-open >/dev/null 2>&1; then
  xdg-open "$URL" 2>/dev/null || true
fi
