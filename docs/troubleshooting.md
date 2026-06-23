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

## Installing an extension fails with ECONNREFUSED

**Symptom:** Installing a Marketplace extension fails mid-install with `AggregateError [ECONNREFUSED]`.

**Cause:** The extension package (`.vsix`) downloads from a per-publisher CDN host (`<publisher>.gallerycdn.vsassets.io`) that the outbound firewall refuses because it is not in `allowed-domains.txt`.

**Fix:** Allowlist the publisher's download hosts and rebuild. See [docs/installing-extensions.md](installing-extensions.md).
