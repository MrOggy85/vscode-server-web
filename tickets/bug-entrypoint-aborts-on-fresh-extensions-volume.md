# Entrypoint can abort on a fresh extensions volume

`entrypoint.sh:72` chowns `${ext_root}/extensions.json`. That file is only
created by the `cat "$tmp" > ...` at line 66, which is inside an `if` guarding
the jq merge at line 63.

If the jq merge fails on a fresh volume where `extensions.json` does not yet
exist, the chown targets a nonexistent path, returns nonzero, and `set -e` kills
the entrypoint — the container never starts.

## Fix

Guard the chown (`[ -e ... ] && chown ...`, or `|| true`), consistent with the
"a manifest we cannot rewrite is cosmetic, not fatal" handling in
`patch_manifests`.
