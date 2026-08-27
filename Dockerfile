FROM debian:trixie-slim

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    ripgrep \
    git \
    gosu \
    jq \
    make \
    nano \
    zip \
    unzip \
    dnsutils \
    man-db \
    nftables \
    shellcheck \
    less \
    tree \
    fd-find \
    procps \
    wget \
      && rm -rf /var/lib/apt/lists/*

# Install Node.js 22 from NodeSource (GPG-verified signed apt repository).
# Keeps the Node version under our control rather than inherited from the base image.
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
    gnupg \
 && install -m 0755 -d /etc/apt/keyrings \
 && curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
    | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg \
 && printf 'deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_22.x nodistro main\n' \
    > /etc/apt/sources.list.d/nodesource.list \
 && apt-get update \
 && apt-get install -y nodejs \
 && rm -rf /var/lib/apt/lists/*

# Download Microsoft's official VS Code CLI for the container's architecture.
# `latest` resolves at build time and fixes the CLI only. The server bundle is a
# separate runtime download into the vscode-cli volume, and follows upstream
# stable on its own — pinning this line would not freeze it.
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

# Install Claude Code
COPY package.json package-lock.json .npmrc /usr/local/
RUN npm ci --prefix /usr/local \
  && node /usr/local/node_modules/@anthropic-ai/claude-code/install.cjs \
  && rm /usr/local/package.json /usr/local/package-lock.json /usr/local/.npmrc \
  && echo 'export PATH="/usr/local/node_modules/.bin:$PATH"' >> /home/coder/.bashrc

ENV DISABLE_AUTOUPDATER=1

# Minimal ~/.claude.json baked into the image (NOT mounted from the host). Because
# the container is ephemeral (--rm), this resets to a clean state every run:
#   - onboarding marked complete (no setup wizard)
#   - the repo's fixed mount path pre-trusted (no "trust this folder?" prompt)
RUN cat > /home/coder/.claude.json <<'JSON'
{
  "hasCompletedOnboarding": true,
  "projects": {
    "/workspace": {
      "hasTrustDialogAccepted": true,
      "hasCompletedProjectOnboarding": true
    }
  }
}
JSON

# Trust any mounted workspace — git 2.35.2+ rejects directories owned by a
# different user, which breaks VS Code's source control view for bind mounts.
RUN git config --system --add safe.directory '*'

# `extensions` is created here (rather than left to Docker) so the shared
# extensions volume inherits coder ownership when it is initialised empty —
# Docker copies the image path's uid/gid onto a fresh named volume.
RUN mkdir -p /home/coder/.vscode-server/data/Machine \
             /home/coder/.vscode-server/extensions \
    && chown -R coder:coder /home/coder

COPY install_additional_packages.sh /usr/local/bin/install_additional_packages.sh
RUN bash /usr/local/bin/install_additional_packages.sh

# Outbound firewall: allowed domains are baked in at build time; rules are
# applied on each container start by the entrypoint (which runs as root).
COPY allowed-domains.txt /etc/allowed-domains.txt
COPY init-firewall.sh /usr/local/bin/init-firewall.sh
RUN chmod +x /usr/local/bin/init-firewall.sh

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
