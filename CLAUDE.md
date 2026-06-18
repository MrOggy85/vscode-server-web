# CLAUDE.md

This repo builds and runs a VS Code Server (serve-web) Docker container — one container per project, each opening a browser-based VS Code pointed at a local directory.

## Key files

- `run.sh` — main entry point; builds the image if needed and starts the container
- `Dockerfile` — image definition; installs VS Code CLI, Node.js 22, Claude Code, and the outbound firewall
- `entrypoint.sh` — container startup: initialises the firewall, patches the PWA manifest, then execs `code serve-web`
- `init-firewall.sh` — sets up nftables outbound allowlist from `/etc/allowed-domains.txt`
- `allowed-domains.txt` — gitignored; copy from `allowed-domains.txt.example` and rebuild to change allowed outbound hosts
- `package.json` / `package-lock.json` — pins the Claude Code and TypeScript versions installed into the image
- `settings.json` — gitignored; copy from `settings.json.example` for VS Code machine settings

## Further reading

- `README.md` — setup, usage, and configuration
- `docs/` — troubleshooting, VS Code quirks, Claude Code usage
