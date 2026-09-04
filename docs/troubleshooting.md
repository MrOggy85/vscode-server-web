# Troubleshooting

## PWA shows wrong name or opens wrong folder

**Symptom:** After rebuilding the image or opening a project for the first time, the installed PWA still shows the old name or does not open `/?folder=/workspace`.

**Cause:** The browser has cached the previous manifest from the same origin (`http://127.0.0.1:<port>`). The cache takes precedence over the freshly served manifest.

**Fix:** Clear the site data for that origin in your browser, then reinstall the PWA.

In Brave/Chrome:
1. Navigate to the instance URL (`http://127.0.0.1:<port>`)
2. Open DevTools → Application → Storage → click **Clear site data**
3. Reload the page
4. Reinstall the PWA from the address bar

## Container log floods with OneCollector ECONNREFUSED

**Symptom:** `docker logs` repeats, every few seconds:

```
info [<commit> stderr]: #29: https://mobile.events.data.microsoft.com/OneCollector/1.0?... - error POST connect ECONNREFUSED 51.116.246.106:443
```

**Cause:** The VS Code server's telemetry appender (1DS/OneCollector) posts to `mobile.events.data.microsoft.com`, which is not in `allowed-domains.txt`. The firewall's `reject with tcp reset` rule fails the connection immediately, so the appender retries quickly instead of stalling on a timeout.

Setting `"telemetry.telemetryLevel": "off"` in the mounted Machine `settings.json` does **not** stop it. That setting drives `getTelemetryLevel()`, the per-event send gate; the appender itself is still constructed and still opens sockets.

**Fix:** Already handled. `entrypoint.sh` passes `--disable-telemetry` to `code serve-web`, which the CLI forwards to the server child process. There, `supportsTelemetry()` returns false and the appender is replaced by a null one, so no connection is ever attempted.

## Container log is noisy even without telemetry

**Symptom:** Frequent `[ManagementConnection] The client has disconnected gracefully` / `New connection established` pairs, and occasional `No ptyHost heartbeat after 6 seconds`.

**Cause:** Normal `serve-web` behaviour. The connection churn is the browser tab or PWA being backgrounded and resumed; the heartbeat warning is the pty host missing a poll under load. Neither is configurable through `settings.json`.

**Fix (optional):** The CLI logs *all* server stdout **and** stderr at `info` level, so raising the CLI's log level drops every wrapped server line at once. In `entrypoint.sh`:

```
code serve-web --log warn ...
```

Trade-off: this also hides the `Downloading server <commit>` progress lines that the first-run diagnosis in [vscode-quirks.md](vscode-quirks.md) relies on. The server keeps its own logs under `~/.vscode-server/data/logs/` regardless.

## Installing an extension fails with ECONNREFUSED

**Symptom:** Installing a Marketplace extension fails mid-install with `AggregateError [ECONNREFUSED]`.

**Cause:** The extension package (`.vsix`) downloads from a per-publisher CDN host (`<publisher>.gallerycdn.vsassets.io`) that the outbound firewall refuses because it is not in `allowed-domains.txt`.

**Fix:** Allowlist the publisher's download hosts and rebuild. See [docs/installing-extensions.md](installing-extensions.md).

## `run.sh` refuses to start: port already published

**Symptom:**

```
run.sh: port 24817 is already published by 'vscode-other-project-9f2c1a'
run.sh: start this project on another port with --port N
```

**Cause:** the port is derived from a hash of the project path, so two projects can land on the same one. Uncommon (well under 1% across a few dozen projects) but permanent: that pair collides on every run, not intermittently.

Your existing container is left alone. The check runs before `run.sh` removes anything, so nothing was destroyed.

**Fix:** start one of them elsewhere:

```bash
./run.sh --port 24818 ~/code/thisproject
```

Move the project *without* an installed PWA if only one has one. A PWA's identity is its origin, so moving a project that has one means reinstalling it from the new URL.

`--port` is not remembered. Wrap it if you need it permanently:

```bash
alias run-thisproject='~/path/to/run.sh --port 24818 ~/code/thisproject'
```

The port is deliberately never auto-incremented. Picking another one silently would leave an installed PWA opening whichever project now owns the old port, which is worse than refusing to start.

**Related:** a container stuck at `restarting` in `vsc ls` that never comes up can be the same collision reached another way. Two containers can both be *configured* for one port if one was stopped when the other was created; a host reboot then starts both and the loser cannot bind. `vsc logs <selector>` shows the bind error. Recreate one with `--port N`.
