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

# Trust any mounted workspace — git 2.35.2+ rejects directories owned by a
# different user, which breaks VS Code's source control view for bind mounts.
RUN git config --system --add safe.directory '*'

# Pre-create the settings directory so named volumes get it on first init,
# ensuring Docker bind-mounts settings.json as a file rather than a directory.
RUN mkdir -p /home/coder/.vscode-server/data/Machine \
    && chown -R coder:coder /home/coder

# Pre-download the VS Code web server package at build time so the first
# container start is instant and manifest.json exists before launch.
RUN gosu coder env HOME=/home/coder code serve-web \
      --without-connection-token \
      --accept-server-license-terms \
      --server-data-dir /home/coder/.vscode-server \
      --host 127.0.0.1 --port 19283 & \
    until curl -s --max-time 2 -o /dev/null http://127.0.0.1:19283; do sleep 2; done; \
    until find /home/coder -name "manifest.json" -path "*/resources/server/*" 2>/dev/null | grep -q .; do sleep 2; done; \
    kill %1 2>/dev/null || true

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
