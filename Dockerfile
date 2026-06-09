FROM debian:bookworm-slim

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl git gosu \
    && rm -rf /var/lib/apt/lists/*

# Download Microsoft's official VS Code CLI for the container's architecture.
RUN set -eux; \
    case "$(uname -m)" in \
      x86_64)  a=cli-linux-x64 ;; \
      aarch64) a=cli-linux-arm64 ;; \
      *) echo "unsupported arch: $(uname -m)" >&2; exit 1 ;; \
    esac; \
    curl -fsSL "https://update.code.visualstudio.com/latest/${a}/stable" -o /tmp/code.tar.gz; \
    tar -xzf /tmp/code.tar.gz -C /usr/local/bin; \
    rm /tmp/code.tar.gz; \
    chmod +x /usr/local/bin/code

RUN useradd -m -u 1000 -s /bin/bash coder

# Entrypoint: fix ownership of the persistent volume (runs as root), then drop
# to the unprivileged 'coder' user before launching the editor itself.
RUN cat > /usr/local/bin/entrypoint.sh <<'EOS' && chmod +x /usr/local/bin/entrypoint.sh
#!/usr/bin/env bash
set -euo pipefail
chown -R coder:coder /home/coder
exec gosu coder env HOME=/home/coder code serve-web \
  --host 0.0.0.0 --port "${PORT:?PORT env var is required}" \
  --without-connection-token \
  --accept-server-license-terms \
  --server-data-dir /home/coder/.vscode-server
EOS

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
