# Claude Code

Claude Code is pre-installed in the container and available from the VS Code integrated terminal.

## Starting a session

Open the terminal inside VS Code and run:

```bash
claude
```

On first use you need to authenticate:

```bash
claude /login
```

This opens a browser tab for OAuth. Once complete the credentials are stored in `~/.claude/` inside the container.

## Persistent credentials

`~/.claude/` is backed by the named Docker volume `vscode-claude-credentials`, which is shared across all project containers started by `run.sh`. You only need to run `/login` once; every subsequent container reuses the same credentials automatically.

To verify which account is active:

```bash
claude /status
```

## Updating Claude Code

The version is pinned in `package-lock.json`. To upgrade, update `package.json`, regenerate the lock file against the public registry, and rebuild the image:

```bash
npm install --package-lock-only --registry https://registry.npmjs.org
./run.sh
```
