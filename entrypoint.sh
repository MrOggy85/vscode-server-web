#!/usr/bin/env bash
set -euo pipefail

: "${PORT:?PORT env var is required}"

/usr/local/bin/init-firewall.sh "${PORT}/tcp"

# Run as the host uid:gid so /workspace writes are owned by the host user. On
# macOS the VM writes as that user, so `ls -l` there looks right either way, but
# inside the VM the file keeps this container's uid, which is what another
# container on the same project sees.
# run.sh always sends these; the fallback is for a hand-rolled `docker run`.
TARGET_UID="${HOST_UID:-1000}"
TARGET_GID="${HOST_GID:-1000}"

# Never run the server as root; that is what the gosu drop is for.
if [ "$TARGET_UID" = "0" ] || [ "$TARGET_GID" = "0" ]; then
  echo "[entrypoint] HOST_UID/HOST_GID of 0 refused, falling back to 1000:1000" >&2
  TARGET_UID=1000
  TARGET_GID=1000
fi

# Edit passwd directly, not usermod -u: that chowns all of $HOME, walking every
# installed extension and hitting the read-only .gitconfig mount (332e6f9).
# Primary gid only, no /etc/group edit: a macOS gid 20 (staff) collides with
# dialout. Every chown below is numeric, so nothing needs the group name.
if [ "$(id -u coder)" != "$TARGET_UID" ] || [ "$(id -g coder)" != "$TARGET_GID" ]; then
  echo "[entrypoint] running as ${TARGET_UID}:${TARGET_GID} (was $(id -u coder):$(id -g coder))" >&2
  sed -i -E "s|^coder:x:[0-9]+:[0-9]+:|coder:x:${TARGET_UID}:${TARGET_GID}:|" /etc/passwd
fi

# Apply keybindings via a generated extension.
#
# VS Code keybindings are strictly User-scoped: there is no Machine-scope
# keybindings file the way there is for settings, and in serve-web all User
# data lives in the browser (IndexedDB), not on the server filesystem. So a
# mounted keybindings.json is never read. The only server-side mechanism is an
# extension that declares the bindings via `contributes.keybindings`; those
# register in the workbench from the manifest regardless of storage backend.
#
# `<server-data-dir>/extensions` IS a shared named volume (see run.sh) holding
# every Marketplace extension installed from any instance, so this must merge
# into `extensions.json` rather than rewrite it; a rewrite would uninstall them
# all on the next start.
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

  # extensions.json is the server's user-extension registry, shared with every
  # Marketplace extension installed from any instance. Replace only our own
  # entry and keep the rest verbatim.
  local entry existing tmp
  entry=$(jq -nc --arg dir "$ext_dir" --arg rel "${id}-${ver}" --arg id "$id" --arg ver "$ver" '{
    identifier: { id: $id },
    version: $ver,
    location: { "$mid": 1, path: $dir, scheme: "file" },
    relativeLocation: $rel,
    metadata: { installedTimestamp: 0, source: "vsix" }
  }')

  # Any existing registry must parse as a JSON array. Treating an unreadable one
  # as empty would rewrite it with only our entry, uninstalling every
  # Marketplace extension. A fresh volume has no file at all, which -s covers.
  existing='[]'
  if [ -s "${ext_root}/extensions.json" ]; then
    if ! existing=$(jq -ce 'if type == "array" then . else error("not a JSON array") end' \
      "${ext_root}/extensions.json"); then
      echo "[entrypoint] ${ext_root}/extensions.json is unreadable, refusing to rewrite it" >&2
      exit 1
    fi
  fi

  # Temp file first, so a partial jq run cannot truncate the registry. Failure is
  # fatal: carrying on would either skip the keybindings silently, or leave
  # extensions.json absent and fail at the chown below, naming the wrong culprit.
  tmp=$(mktemp)
  if ! jq -n --argjson existing "$existing" --argjson entry "$entry" \
    '[$existing[] | select(.identifier.id != $entry.identifier.id)] + [$entry]' > "$tmp"
  then
    rm -f "$tmp"
    echo "[entrypoint] could not build ${ext_root}/extensions.json" >&2
    exit 1
  fi
  cat "$tmp" > "${ext_root}/extensions.json"
  rm -f "$tmp"

  # Only the paths this function created as root; the rest of the shared
  # extensions volume already belongs to the runtime user.
  chown -R "${TARGET_UID}:${TARGET_GID}" "$ext_dir" "${ext_root}/extensions.json"
}

generate_keybindings_extension

# Fix ownership only where it's actually needed: the named volumes (a fresh
# named volume mounts root-owned) and the server data dir. Deliberately NOT a
# recursive chown over all of /home/coder: that would hit the read-only
# .gitconfig bind mount and abort the entrypoint under `set -e`.
EXT_ROOT=/home/coder/.vscode-server/extensions

# Normally chowned non-recursively: recursing would walk every installed
# extension on every start. A uid change is the exception: it strands them all
# in the shared volume. The dir's own owner is the signal, so this runs once.
if [ "$(stat -c %u "$EXT_ROOT")" != "$TARGET_UID" ]; then
  echo "[entrypoint] extensions volume has a different owner, chowning once" >&2
  chown -R "${TARGET_UID}:${TARGET_GID}" "$EXT_ROOT"
fi

chown -R "${TARGET_UID}:${TARGET_GID}" /home/coder/.vscode /home/coder/.claude /home/coder/.vscode-server/data
chown "${TARGET_UID}:${TARGET_GID}" /home/coder/.vscode-server "$EXT_ROOT"

# Baked into the image as 1000; Claude Code rewrites ~/.claude.json at runtime.
# Named explicitly, not globbed: the home dir also holds the read-only
# .gitconfig mount (332e6f9).
chown "${TARGET_UID}:${TARGET_GID}" /home/coder /home/coder/.claude.json /home/coder/.bashrc

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
# mobile.events.data.microsoft.com, which the firewall rejects, producing an
# endless "OneCollector/1.0 - error POST connect ECONNREFUSED" stream in the
# container log. The CLI forwards this flag to the server child, where
# `supportsTelemetry()` short-circuits and no appender is created at all.
exec gosu coder env HOME=/home/coder code serve-web \
  --host 0.0.0.0 --port "${PORT}" \
  --without-connection-token \
  --accept-server-license-terms \
  --disable-telemetry \
  --server-data-dir /home/coder/.vscode-server
