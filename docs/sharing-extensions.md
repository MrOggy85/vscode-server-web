# Sharing extensions across containers

Install an extension once, get it in every instance, and still enable or disable
it per instance.

## How it works

The two halves of "having an extension" are stored in different places in
`serve-web`, which is what makes this possible:

| | Where it lives | Scope |
| --- | --- | --- |
| **Installed** (the unpacked package) | `<server-data-dir>/extensions` on the container filesystem, listed in `extensions.json` | server |
| **Enabled / disabled** | browser IndexedDB (User-scoped state, like User settings) | per origin |

`run.sh` mounts the named volume `vscode-extensions` at
`/home/coder/.vscode-server/extensions`, shared by every instance, so an
install from any container is immediately an install for all of them.

Enablement needs no work at all: each instance gets its own port, so each is its
own origin (`http://127.0.0.1:<port>`) with its own IndexedDB. Disabling an
extension in one instance leaves it enabled in the others.

## Using it

1. Start any instance and install extensions from the Extensions view as usual.
   Marketplace downloads are firewalled per publisher, see
   [installing-extensions.md](installing-extensions.md).
2. Every instance started afterwards has them installed already.
3. In an instance where you don't want one, use **Disable** (not Uninstall) in
   the Extensions view. **Uninstall removes it from the shared volume**, i.e.
   from every instance.

Override the volume name with `VSCODE_EXTENSIONS_VOLUME=... ./run.sh` if you
want one project on its own isolated set.

## Notes

- An instance that is **already running** does not pick up an extension
  installed from another instance until it is restarted (`./run.sh <path>`);
  the server scans the extensions directory at startup.
- `settings.json.example` turns `extensions.autoUpdate` and
  `extensions.autoCheckUpdates` off. Keep them off: with a shared directory,
  several instances auto-updating the same extension concurrently can race on
  `extensions.json`. Update deliberately, from one instance.
- `./vsc destroy` keeps `vscode-extensions`, the same way it keeps `vscode-cli`
  and `vscode-claude-credentials`. To wipe every install:
  `docker volume rm vscode-extensions` (with no instance running).
