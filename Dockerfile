FROM golang:1.25-alpine AS builder

RUN apk add --no-cache git make nodejs npm bash pnpm patch

WORKDIR /src

ARG PICOCLAW_VERSION=main

RUN git clone --depth 1 --branch ${PICOCLAW_VERSION} https://github.com/sipeed/picoclaw.git .

RUN go mod download
RUN make build
RUN make build-launcher

FROM debian:bookworm-slim

RUN apt-get update && \
    apt-get install -y --no-install-recommends ca-certificates curl nginx iproute2 procps git openssh-client nano && \
    rm -rf /var/lib/apt/lists/*

COPY --from=builder /src/build/picoclaw /usr/local/bin/picoclaw
COPY --from=builder /src/build/picoclaw-launcher /usr/local/bin/picoclaw-launcher

COPY nginx.conf /etc/nginx/nginx.conf.template
COPY obsidian-sync.sh /app/obsidian-sync.sh
RUN chmod +x /app/obsidian-sync.sh

RUN mkdir -p /data/.picoclaw && echo "v2"

COPY start.sh /app/start.sh
RUN chmod +x /app/start.sh

ENV HOME=/data
ENV PICOCLAW_HOME=/data/.picoclaw
ENV PICOCLAW_AGENTS_DEFAULTS_WORKSPACE=/data/.picoclaw/workspace
ENV PICOCLAW_GATEWAY_HOST=0.0.0.0
ENV PICOCLAW_BINARY=/usr/local/bin/picoclaw

EXPOSE 18800 18790

# Run start script via bash explicitly
CMD ["/bin/bash", "/app/start.sh"]
