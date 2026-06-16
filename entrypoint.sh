#!/usr/bin/env bash
set -euo pipefail

: "${PORT:?PORT env var is required}"

/usr/local/bin/init-firewall.sh "${PORT}/tcp"

chown -R coder:coder /home/coder

# Patch manifest.json once after the server is up. The CLI self-update and
# server download both complete before HTTP becomes available, so a single
# pass is sufficient. cat into the existing inode avoids sed -i fchown errors.
patch_manifests() {
  find /home/coder/.vscode/cli/serve-web \
      -name "manifest.json" -path "*/resources/server/*" 2>/dev/null \
  | while IFS= read -r m; do
    tmp=$(mktemp)
    sed \
      -e "s|\"name\": \".*\"|\"name\": \"${PROJECT_NAME:-Code} — VSCode\"|" \
      -e "s|\"short_name\": \".*\"|\"short_name\": \"${PROJECT_NAME:-Code}\"|" \
      -e "s|\"start_url\": \".*\"|\"start_url\": \"/?folder=/workspace\"|" \
      "$m" > "$tmp" && cat "$tmp" > "$m" || true
    rm -f "$tmp"
  done
}

(
  until curl -sf --max-time 2 -o /dev/null "http://127.0.0.1:${PORT}/"; do
    sleep 2
  done
  patch_manifests
) &

exec gosu coder env HOME=/home/coder code serve-web \
  --host 0.0.0.0 --port "${PORT}" \
  --without-connection-token \
  --accept-server-license-terms \
  --server-data-dir /home/coder/.vscode-server
