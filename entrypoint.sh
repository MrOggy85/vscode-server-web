#!/usr/bin/env bash
set -euo pipefail

: "${PORT:?PORT env var is required}"

/usr/local/bin/init-firewall.sh "${PORT}/tcp"

# Apply keybindings via a generated extension.
#
# VS Code keybindings are strictly User-scoped — there is no Machine-scope
# keybindings file the way there is for settings, and in serve-web all User
# data lives in the browser (IndexedDB), not on the server filesystem. So a
# mounted keybindings.json is never read. The only server-side mechanism is an
# extension that declares the bindings via `contributes.keybindings`; those
# register in the workbench from the manifest regardless of storage backend.
#
# `.vscode-server` is not a volume, so this dir resets from the image on every
# run and we own it cleanly — no merge with user-installed extensions needed.
generate_keybindings_extension() {
  local src=/home/coder/keybindings.json
  [ -s "$src" ] || return 0

  local ext_root=/home/coder/.vscode-server/extensions
  local id=local.container-keybindings ver=1.0.0
  local ext_dir="${ext_root}/${id}-${ver}"

  mkdir -p "$ext_dir"

  # A purely declarative extension (no entry point) is loaded everywhere,
  # including the web extension host, without activation.
  jq -n --slurpfile kb "$src" '{
    name: "container-keybindings",
    displayName: "Container Keybindings",
    publisher: "local",
    version: "1.0.0",
    engines: { vscode: "^1.0.0" },
    contributes: { keybindings: $kb[0] }
  }' > "${ext_dir}/package.json"

  # extensions.json is the server's user-extension registry. We own the dir, so
  # a fresh single-entry file is safe.
  jq -n --arg dir "$ext_dir" --arg rel "${id}-${ver}" --arg id "$id" --arg ver "$ver" '[
    {
      identifier: { id: $id },
      version: $ver,
      location: { "$mid": 1, path: $dir, scheme: "file" },
      relativeLocation: $rel,
      metadata: { installedTimestamp: 0, source: "vsix" }
    }
  ]' > "${ext_root}/extensions.json"
}

generate_keybindings_extension

# Fix ownership only where it's actually needed: the two named volumes (a fresh
# named volume mounts root-owned) and the server dir, where the keybindings
# extension above was generated as root. Deliberately NOT a recursive chown over
# all of /home/coder — that would hit the read-only .gitconfig bind mount and
# abort the entrypoint under `set -e`.
chown -R coder:coder /home/coder/.vscode /home/coder/.claude /home/coder/.vscode-server

# cat into the existing inode avoids sed -i fchown errors.
patch_manifests() {
  find /home/coder/.vscode/cli/serve-web \
      -name "manifest.json" -path "*/resources/server/*" 2>/dev/null \
  | while IFS= read -r m; do
    tmp=$(mktemp)
    # Both steps are allowed to fail without aborting the entrypoint: a manifest
    # we cannot rewrite is cosmetic, not fatal. Kept as if/then rather than
    # `sed && cat || true` so the fallback is tied to sed alone.
    if sed \
      -e "s|\"name\": \".*\"|\"name\": \"${PROJECT_NAME:-Code} — VSCode\"|" \
      -e "s|\"short_name\": \".*\"|\"short_name\": \"${PROJECT_NAME:-Code}\"|" \
      -e "s|\"start_url\": \".*\"|\"start_url\": \"/?folder=/workspace\"|" \
      "$m" > "$tmp"
    then
      cat "$tmp" > "$m" || true
    fi
    rm -f "$tmp"
  done
}

# Pre-patch: if the CLI volume already has a manifest from a previous project,
# update it before VS Code starts so it never serves the stale name.
patch_manifests

# Post-patch: handles the first-run case where VS Code downloads the server
# package after startup (file doesn't exist until HTTP is ready).
(
  until curl -sf --max-time 2 -o /dev/null "http://127.0.0.1:${PORT}/"; do
    sleep 2
  done
  patch_manifests
) &

# --disable-telemetry, not the `telemetry.telemetryLevel` setting: the mounted
# Machine settings.json only controls the *send gate* (`getTelemetryLevel`), so
# the server still builds its 1DS appender and keeps POSTing to
# mobile.events.data.microsoft.com — which the firewall rejects, producing an
# endless "OneCollector/1.0 - error POST connect ECONNREFUSED" stream in the
# container log. The CLI forwards this flag to the server child, where
# `supportsTelemetry()` short-circuits and no appender is created at all.
exec gosu coder env HOME=/home/coder code serve-web \
  --host 0.0.0.0 --port "${PORT}" \
  --without-connection-token \
  --accept-server-license-terms \
  --disable-telemetry \
  --server-data-dir /home/coder/.vscode-server
