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
    apt-get install -y --no-install-recommends \
        ca-certificates curl git bash sudo vim nano less procps \
        openssh-client rsync coreutils && \
    rm -rf /var/lib/apt/lists/*
# Ensure /data is writable
RUN mkdir -p /data && chmod 777 /data

COPY --from=builder /src/build/picoclaw /usr/local/bin/picoclaw
COPY --from=builder /src/build/picoclaw-launcher /usr/local/bin/picoclaw-launcher

COPY obsidian-sync.sh /app/obsidian-sync.sh
RUN chmod +x /app/obsidian-sync.sh

COPY start.sh /app/start.sh
RUN chmod +x /app/start.sh

ENV HOME=/data
ENV PICOCLAW_HOME=/data/.picoclaw
ENV PICOCLAW_BINARY=/usr/local/bin/picoclaw

EXPOSE 18800

CMD ["/app/start.sh"]
