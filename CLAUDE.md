# CLAUDE.md

This repo builds and runs a VS Code Server (serve-web) Docker container, one container per project, each opening a browser-based VS Code pointed at a local directory.

## Key files

- `run.sh`: main entry point; builds the image if needed and starts the container
- `Dockerfile`: image definition; installs VS Code CLI, Node.js 22, Claude Code, and the outbound firewall
- `entrypoint.sh`: at container startup, initialises the firewall, patches the PWA manifest, then execs `code serve-web`
- `init-firewall.sh`: sets up nftables outbound allowlist from `/etc/allowed-domains.txt`
- `allowed-domains.txt`: gitignored; copy from `allowed-domains.txt.example` and rebuild to change allowed outbound hosts
- `package.json` / `package-lock.json`: pins the Claude Code and TypeScript versions installed into the image
- `settings.json`: gitignored; copy from `settings.json.example` for VS Code machine settings
- `Makefile`: `make init` seeds the gitignored config files; `make lint` shellchecks every script
- `.github/workflows/lint.yml`: CI; runs `make lint`, so it cannot drift from a local run
- `.github/workflows/build.yml`: CI; builds and smoke-tests the image. Its path filter mirrors `context_hash()` in `run.sh`, so change one and change the other

## Further reading

- `README.md`: setup, usage, and configuration
- `docs/`: troubleshooting, known issues, VS Code quirks, Claude Code usage

## Inline Comments
Keep it brief, tight, no prose. Shorter is better.

## Docs
Optimise for the reader's context budget, human or agent.

- One home per fact. Link, don't restate.
- Don't document what `--help` or the code already says.
- Cut anything that doesn't change what the reader does.
- Keep the *why* when it isn't derivable from the code; that is what earns its context.

Unlike inline comments, full sentences are fine; the reader has no adjacent code to lean on.
