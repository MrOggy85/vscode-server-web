# Mount `allowed-domains.txt` instead of baking it into the image

`Dockerfile:95` `COPY`s `allowed-domains.txt` to `/etc/allowed-domains.txt`, so
it is part of the build context hash (`run.sh:22`) and any edit forces a full
image rebuild.

This is the project's sharpest papercut, because the file needs editing often:
Marketplace extensions download their `.vsix` from a *per-publisher* host
(`<publisher>.gallerycdn.vsassets.io`), so every new publisher means edit →
rebuild → restart. See `docs/installing-extensions.md`.

## Fix

Bind-mount the file to `/etc/allowed-domains.txt` in `run.sh` and drop it from
both the `COPY` and `context_hash()`. Editing it then costs a container restart —
or nothing at all, since the background refresher re-reads the file every 30s
(`init-firewall.sh:43-49`) and would pick up new hosts on the next tick.

Keep a copy in the image as the fallback for when the mount is absent.
