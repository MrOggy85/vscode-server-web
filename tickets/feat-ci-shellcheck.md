# CI running shellcheck

There is no `.github/` directory. Meanwhile shellcheck is installed into the
image (`Dockerfile:18`) and commit `a49b429` was a manual shellcheck cleanup of
`run.sh` and `entrypoint.sh` — the linting is happening, just by hand.

## Fix

A GitHub Actions workflow running shellcheck over `run.sh`, `vsc`,
`entrypoint.sh` and `init-firewall.sh` on push and PR.

Worth adding a build job too, so `Dockerfile` breakage is caught without a local
run. It would need an `allowed-domains.txt` and an
`install_additional_packages.sh` — both gitignored — so the workflow should copy
the `.example` files first, the same as `make init`.
