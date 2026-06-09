set -euo pipefail

IMAGE="vscode-serve-web:local"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${1:-.}" && pwd)"

# Stable per-project names: vscode-<dirname>-<short hash of full path>.
# Same approach as claude-in-docker/run.sh — hash disambiguates same-named dirs.
path_hash() {
  if command -v sha256sum >/dev/null 2>&1; then printf '%s' "$1" | sha256sum | cut -c1-10
  else printf '%s' "$1" | shasum -a 256 | cut -c1-10; fi
}
SAFE_NAME="$(printf '%s' "$(basename "${PROJECT_DIR}")" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9' '-')"
SAFE_NAME="$(printf '%s' "${SAFE_NAME}" | sed -e 's/-\{2,\}/-/g' -e 's/^-//' -e 's/-$//')"
HASH="$(path_hash "${PROJECT_DIR}")"

CONTAINER="${VSCODE_CONTAINER:-vscode-${SAFE_NAME:-repo}-${HASH}}"
DATA_VOLUME="${VSCODE_VOLUME:-vscode-${SAFE_NAME:-repo}-${HASH}}"

# Derive a stable default port in 8000-8999 from the path hash; override with PORT=...
DEFAULT_PORT=$(( 8000 + ( 0x$(printf '%s' "${HASH}" | cut -c1-3) % 1000 ) ))
PORT="${PORT:-$DEFAULT_PORT}"

echo ">> container:    ${CONTAINER}"
echo ">> data volume:  ${DATA_VOLUME}"
echo ">> port:         ${PORT}"

docker rm -f "$CONTAINER" >/dev/null 2>&1 || true

docker run -d \
  --name "$CONTAINER" \
  --restart unless-stopped \
  -p "127.0.0.1:${PORT}:${PORT}" \
  -e PORT="$PORT" \
  -v "$DATA_VOLUME:/home/coder" \
  -v "$PROJECT_DIR:/workspace" \
  -v "$SCRIPT_DIR/settings.json:/home/coder/.vscode-server/data/Machine/settings.json" \
  --cap-drop ALL \
  --cap-add CHOWN --cap-add DAC_OVERRIDE --cap-add SETUID --cap-add SETGID \
  --security-opt no-new-privileges:true \
  "$IMAGE" >/dev/null

URL="http://127.0.0.1:${PORT}/?folder=/workspace"
echo ">> Container started. First load downloads the server, so give it a few seconds."
echo ">> Open: $URL"

# Open the browser automatically (macOS uses `open`, Linux uses `xdg-open`).
if command -v open >/dev/null 2>&1; then
  open "$URL" 2>/dev/null || true
elif command -v xdg-open >/dev/null 2>&1; then
  xdg-open "$URL" 2>/dev/null || true
fi
