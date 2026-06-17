# VS Code Quirks

## Server download stuck on first run (or after image rebuild)

**Symptom:** The browser shows a white "Downloading new version…" page indefinitely. The container log repeats:

```
info Downloading server <commit-hash>
info Downloading server <commit-hash>
...
```

every 2–3 seconds with no progress.

**Cause:** `code serve-web` downloads the VS Code web server bundle at runtime. The initial request goes to `update.code.visualstudio.com`, which issues a 302 redirect to `vscode.download.prss.microsoft.com` for the actual file. The outbound firewall resolves and allows IPs by domain name, so if the redirect target domain is missing from `allowed-domains.txt`, the CDN connection is immediately rejected with a TCP RST — hence the fast retry loop.

This happens on first start against a fresh CLI volume, or whenever the image is rebuilt with a newer VS Code CLI version that requires a different server bundle.

**Fix:** `vscode.download.prss.microsoft.com` must be in `allowed-domains.txt` before building the image. Rebuild and restart:

```
./run.sh /path/to/project
```
