#!/usr/bin/env bash
set -euo pipefail

MANIFEST=$(find /home/coder -name "manifest.json" -path "*/resources/server/*" | head -1)
sed -i \
  -e "s|\"name\": \".*\"|\"name\": \"${PROJECT_NAME:-Code} — VSCode\"|" \
  -e "s|\"short_name\": \".*\"|\"short_name\": \"${PROJECT_NAME:-Code}\"|" \
  -e "s|\"start_url\": \".*\"|\"start_url\": \"/?folder=/workspace\"|" \
  "$MANIFEST"

chown -R coder:coder /home/coder

exec gosu coder env HOME=/home/coder code serve-web \
  --host 0.0.0.0 --port "${PORT:?PORT env var is required}" \
  --without-connection-token \
  --accept-server-license-terms \
  --server-data-dir /home/coder/.vscode-server
