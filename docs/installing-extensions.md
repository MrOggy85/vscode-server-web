# Installing VS Code extensions

## Symptom

Installing an extension from the Marketplace fails. The Output panel (or
`code --install-extension … --verbose`) shows a connection error mid-install:

```
[error] [Window] AggregateError [ECONNREFUSED]:
    at internalConnectMultiple (node:net:1193:18)
    at afterConnectMultiple (node:net:1783:7)
```

The error is `ECONNREFUSED` (an *active* refusal, not a timeout) because the
outbound firewall rejects un-allowed hosts with a TCP RST — see
[init-firewall.sh](../init-firewall.sh).

## Cause

An extension install is two network hops to **different** hosts, and the second
one is usually the missing one:

| Step | Host | Serves |
| --- | --- | --- |
| 1. Search / metadata | `marketplace.visualstudio.com` | Extension lookup, versions, manifest |
| 2. Download the `.vsix` | `<publisher>.gallery.vsassets.io` → `<publisher>.gallerycdn.vsassets.io` | The actual package bytes |

`marketplace.visualstudio.com` is already in the allowlist, so metadata fetches
succeed. The package bytes come from a per-publisher CDN subdomain that is **not**
allowlisted, so the download connection is refused → `ECONNREFUSED`.

Note the two distinct download hosts: the `gallery.vsassets.io` host issues a
`302` redirect (the URL ends in `?redirect=true`) and the redirect **target** is
the separate `gallerycdn.vsassets.io` host that serves the file. Allowing only
the first still fails at the redirect. Allow **both**.

### Why you can't just add one wildcard

`allowed-domains.txt` does not support wildcards — each entry is resolved with
`dig`. The CDN uses a per-publisher subdomain
(`ms-python.gallerycdn.vsassets.io`, `denoland.gallerycdn.vsassets.io`, …), so
you must add the specific publisher hosts for each extension you install.

## Fix

1. Find the exact host being refused. Run in the container terminal:

   ```bash
   code --install-extension <publisher>.<name> --verbose
   ```

   and look for the `gallery.vsassets.io` / `gallerycdn.vsassets.io` URL.

2. Add **both** download hosts for that publisher to `allowed-domains.txt`. For
   example, the Deno extension (`denoland.vscode-deno`):

   ```
   # VS Code extension package downloads (per-publisher CDN, no wildcard support)
   denoland.gallery.vsassets.io
   denoland.gallerycdn.vsassets.io
   ```

3. Rebuild the image and restart the container:

   ```bash
   ./run.sh /path/to/project
   ```

If you install many extensions, the per-publisher limitation is worth raising
with whoever owns the firewall — a proxy exception for `*.vsassets.io` would
remove the need to allowlist each publisher by hand.
