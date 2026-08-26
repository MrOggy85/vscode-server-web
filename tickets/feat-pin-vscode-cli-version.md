# Pin the VS Code CLI version

`Dockerfile:47` fetches `https://update.code.visualstudio.com/latest/${a}/stable`.

Two consequences: rebuilds are not reproducible, and `context_hash()` cannot
detect the drift — the Dockerfile text is unchanged, so `run.sh` sees no reason
to rebuild even when upstream has moved.

## Fix

Pin an explicit version in place of `latest` (a build arg keeps it easy to bump).
Bumping it then changes the Dockerfile, which changes the context hash, which
triggers the rebuild automatically.
