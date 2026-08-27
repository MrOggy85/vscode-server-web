# CI job that builds the image

`.github/workflows/lint.yml` runs shellcheck, but nothing builds the
`Dockerfile`. Image breakage is only discovered on someone's next `./run.sh`,
which is also the moment they wanted to start working.

Split out of the original CI ticket; the shellcheck half is done.

## Fix

A `build` job that runs `make init` and then `docker build`.

Note this is the one job that *does* need `make init` first, unlike the
shellcheck job: `allowed-domains.txt` and `install_additional_packages.sh` are
gitignored but `COPY`d by the Dockerfile, so a bare checkout cannot build.

## Cost

Several minutes per run — the build pulls Node.js from NodeSource, downloads the
VS Code CLI, and runs `npm ci`. Worth scoping to pushes that touch the build
context (`Dockerfile`, `entrypoint.sh`, `init-firewall.sh`, the npm files,
`install_additional_packages.sh.example`) rather than running on every PR.
