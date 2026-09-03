# Add a Docker `HEALTHCHECK`

The image has no `HEALTHCHECK`, so `docker inspect .State.Status`, which is what
`vsc ls` reports (`vsc:97`), says `running` for a container whose `serve-web`
process is wedged or never finished downloading the server.

`--restart unless-stopped` (`run.sh:99`) also can't help with a hung-but-alive
process.

## Fix

```
HEALTHCHECK --interval=30s --timeout=5s --start-period=120s \
  CMD curl -sf "http://127.0.0.1:${PORT}/" || exit 1
```

A generous `--start-period` matters: on first run VS Code downloads the server
package after startup (see the post-patch comment at `entrypoint.sh:115-116`).

Then surface the health state in the `vsc ls` status column.
