set -euo pipefail

IMAGE="vscode-serve-web:local"
CONTAINER="vscode-serve-web"
PORT="${PORT:-8000}"
PROJECT_DIR="$(pwd)"
DATA_VOLUME="vscode-serve-web-data"   # persists the downloaded server, extensions, settings

docker rm -f "$CONTAINER" >/dev/null 2>&1 || true

docker run -d \
  --name "$CONTAINER" \
  --restart unless-stopped \
  -p "127.0.0.1:${PORT}:${PORT}" \
  -e PORT="$PORT" \
  -v "$DATA_VOLUME:/home/coder" \
  -v "$PROJECT_DIR:/workspace" \
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
