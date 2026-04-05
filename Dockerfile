FROM golang:1.25-alpine AS builder

# Rebuild v5 - complete launcher with web frontend
RUN apk add --no-cache git make nodejs npm bash pnpm patch

WORKDIR /src

ARG PICOCLAW_VERSION=15a70ac45c5a37ddeeede8150431e5b6e1de6516

RUN git clone --depth 1 --branch ${PICOCLAW_VERSION} https://github.com/sipeed/picoclaw.git .

RUN go mod download
RUN make build
RUN make build-launcher

FROM debian:bookworm-slim

RUN apt-get update && \
    apt-get install -y --no-install-recommends ca-certificates curl iproute2 procps git openssh-client && \
    rm -rf /var/lib/apt/lists/*

# Copy all PicoClaw binaries
COPY --from=builder /src/build/picoclaw /usr/local/bin/picoclaw
COPY --from=builder /src/build/picoclaw-launcher /usr/local/bin/picoclaw-launcher

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
