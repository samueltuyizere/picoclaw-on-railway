FROM debian:bookworm-slim

RUN apt-get update && \
    apt-get install -y --no-install-recommends ca-certificates curl nginx iproute2 procps git openssh-client && \
    rm -rf /var/lib/apt/lists/*

# Download picoclaw v0.2.5 binaries from GitHub releases
RUN curl -sL "https://github.com/sipeed/picoclaw/releases/download/v0.2.5/picoclaw_Linux_x86_64.tar.gz" -o /tmp/picoclaw.tar.gz && \
    tar -xzf /tmp/picoclaw.tar.gz -C /tmp && \
    mv /tmp/picoclaw /usr/local/bin/ && \
    mv /tmp/picoclaw-launcher /usr/local/bin/ && \
    chmod +x /usr/local/bin/picoclaw /usr/local/bin/picoclaw-launcher && \
    rm -f /tmp/picoclaw.tar.gz

# Copy nginx config template
COPY nginx.conf /etc/nginx/nginx.conf.template

# Copy Obsidian sync script
COPY obsidian-sync.sh /app/obsidian-sync.sh
RUN chmod +x /app/obsidian-sync.sh

RUN mkdir -p /data/.picoclaw && echo "v2"

COPY start.sh /app/start.sh
RUN chmod +x /app/start.sh

ENV HOME=/data
ENV PICOCLAW_HOME=/data/.picoclaw
ENV PICOCLAW_AGENTS_DEFAULTS_WORKSPACE=/data/.picoclaw/workspace
ENV PICOCLAW_GATEWAY_HOST=0.0.0.0

# Expose launcher web UI port and gateway port
EXPOSE 18800 18790

CMD ["/app/start.sh"]