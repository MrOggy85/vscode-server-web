# VS Code Quirks

## Server download stuck on "Downloading new version…"

**Symptom:** The browser shows a white "Downloading new version…" page indefinitely. The container log repeats:

```
info Downloading server <commit-hash>
info Downloading server <commit-hash>
...
```

every 2–3 seconds with no progress.

**Cause:** `code serve-web` downloads the VS Code web server bundle at runtime. The initial request goes to `update.code.visualstudio.com`, which issues a 302 redirect to `vscode.download.prss.microsoft.com` for the actual file. The outbound firewall resolves and allows IPs by domain name, so if the redirect target domain is missing from `allowed-domains.txt`, the CDN connection is immediately rejected with a TCP RST, hence the fast retry loop.

Three things trigger the download, and only the first two involve you:

1. **First start against a fresh CLI volume**: nothing is cached yet.
2. **An image rebuild that moves the VS Code CLI.** `Dockerfile` fetches the CLI from the `latest` slot, resolved at build time, so *any* rebuild can pick up a newer CLI, including one triggered by an unrelated change such as a Claude Code version bump.
3. **A new upstream stable release.** `serve-web` follows the stable channel rather than the CLI's own build, so it fetches the new server bundle on its own. This needs no rebuild and no action from you, and since VS Code ships roughly monthly it is the usual explanation for a download appearing "out of nowhere".

Note that the CLI baked into the image and the server bundle are separate downloads. Pinning the `Dockerfile` to a fixed CLI version addresses case 2 only; case 3 happens regardless.

**Fix:** `vscode.download.prss.microsoft.com` must be in `allowed-domains.txt` before building the image. Rebuild and restart:

```
./run.sh /path/to/project
```

## PWA shows the previous project's name

**Symptom:** After switching to a different project with `./run.sh`, the installed PWA still shows the old project name.

**Cause:** Two independent caches can hold the stale name:

1. **CLI volume**: the shared `vscode-cli` volume carries the `manifest.json` written by the previous project. If `code serve-web` reads it before the entrypoint patches it, the old name is served from the start.
2. **Browser**: the browser caches the manifest for the origin (`http://127.0.0.1:<port>`), so even a correctly served manifest may not be picked up until the cache is cleared.

The entrypoint patches the manifest synchronously before `exec`-ing VS Code to handle case 1. Case 2 requires a manual browser fix.

**Fix (browser cache):** Clear site data for the origin in your browser, then reinstall the PWA.

In Brave/Chrome:
1. Navigate to the instance URL (`http://127.0.0.1:<port>`)
2. Open DevTools → Application → Storage → click **Clear site data**
3. Reload the page
4. Reinstall the PWA from the address bar

## Git source control view is broken (no diff, no file status)

**Symptom:** The Source Control panel shows no changes or throws an error, even though the workspace has uncommitted changes.

**Cause:** Git 2.35.2+ rejects operations in directories owned by a different user (`fatal: detected dubious ownership`). Because the workspace is a bind mount from the host, the directory owner (host UID) differs from the container user (`coder`, UID 1000), and git refuses to operate on it.

**Fix:** Already handled in the image. The Dockerfile sets `safe.directory = *` in the system git config. If you see this with a custom image, add:

```dockerfile
RUN git config --system --add safe.directory '*'
```

## Settings changes have no effect

**Symptom:** Edits to the mounted `settings.json` are ignored; the editor behaves as if no settings are applied.

**Cause:** In `serve-web` mode, *User Settings* are stored in the **browser's IndexedDB** (per origin), not on the server filesystem. A `settings.json` mounted to the user-settings path on the container has no effect because VS Code never reads it there.

**Fix:** Mount settings to the *Machine settings* path instead. Machine settings live on the server filesystem and override user settings:

```
~/.vscode-server/data/Machine/settings.json
```

This is what `run.sh` does via the `-v` flag. If settings still seem ignored, check that the file is mounted to `data/Machine/`, not `data/User/`.

## Keybindings can't be mounted like settings

**Symptom:** Mounting a `keybindings.json` into the container (the obvious analogue to the `settings.json` mount) has no effect; none of the bindings apply.

**Cause:** The Machine-settings escape hatch above does **not** exist for keybindings. VS Code keybindings are strictly *User-scoped*; there is no `data/Machine/keybindings.json`. In `serve-web`, User data lives in the browser's IndexedDB, so a `keybindings.json` placed anywhere on the server filesystem (`data/User/`, the home dir, etc.) is never read.

**Fix:** Ship the bindings as a server-side **extension** instead. An extension that declares `contributes.keybindings` in its `package.json` registers those bindings in the workbench from the manifest, independent of the browser-stored User profile. The `entrypoint.sh` generates exactly such an extension from the mounted `keybindings.json`:

- Writes `~/.vscode-server/extensions/local.container-keybindings-1.0.0/package.json` with the bindings under `contributes.keybindings`.
- Registers it in `~/.vscode-server/extensions/extensions.json` (the server's user-extension registry).

`serve-web` exposes no `--extensions-dir`; the user-extension directory is fixed at `<server-data-dir>/extensions`. That directory is the shared `vscode-extensions` volume (see [sharing-extensions.md](sharing-extensions.md)), so the entrypoint **merges** its entry into `extensions.json`, replacing only `local.container-keybindings` and leaving every Marketplace extension untouched. A blind rewrite there would uninstall them all on the next start.

Notes:
- `keybindings.json` is parsed as **strict JSON** (via `jq`); no `//` comments.
- Because the extensions directory is shared, the generated extension persists there. Removing `keybindings.json` stops it being regenerated but does not uninstall it. Delete `local.container-keybindings-1.0.0` from the `vscode-extensions` volume (or uninstall it from the Extensions view) to drop the bindings.
- Contributed keybindings sit at default-keybinding priority. A binding the user sets in the browser-stored profile for the same key still wins; this is for shared defaults across containers, not for overriding per-user choices.

## Search skips gitignored sub-repositories

**Symptom:** A workspace holds checkouts of other repos, gitignored so their changes stay out of the parent's diff:

```gitignore
/vnext-web
/vnext-game-backend
```

That works for git, but search returns nothing from inside them. The Explorer still lists them, so it looks like a search bug.

**Cause:** VS Code search is ripgrep, and `search.useIgnoreFiles` (on by default) makes it honour `.gitignore`. Moving the entries to `.git/info/exclude` does not help: ripgrep reads that too.

**Fix:** Add a `.ignore` file next to `.gitignore`, negating each sub-repo:

```gitignore
!/vnext-web
!/vnext-game-backend
```

Ripgrep ranks `.ignore` above `.gitignore`, so the negation wins. Git never reads `.ignore`, so the parent diff stays clean.

Each sub-repo's own `.gitignore` still applies, so its `node_modules` stays out of results. That is the advantage over `"search.useIgnoreFiles": false`, which also restores the sub-repos but by switching off every ignore rule everywhere.

Claude Code honours `.gitignore` for its own searches too, so the same file widens what it can see.
