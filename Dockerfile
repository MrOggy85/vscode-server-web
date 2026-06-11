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

RUN mkdir -p /home/coder/.vscode-server/data/Machine \
    && chown -R coder:coder /home/coder

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
