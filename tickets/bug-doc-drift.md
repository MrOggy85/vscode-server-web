# Documentation drift

Three unrelated inaccuracies:

- `README.md:25` lists the rebuild triggers as `Dockerfile`, `entrypoint.sh` and
  `install_additional_packages.sh`. The real set in `context_hash()`
  (`run.sh:17-23`) also includes `init-firewall.sh` and `allowed-domains.txt`
  (and should include the npm files — see
  `bug-context-hash-misses-npm-files.md`).
- `completions/_vsc:6` points at a "Shell completion" section in `README.md`.
  No such section exists; the install instructions are in
  `docs/managing-instances.md`.
- `package.json:3` describes the file as pinning packages for "the
  claude-in-docker image" — wrong project.
