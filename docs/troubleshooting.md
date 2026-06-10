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
