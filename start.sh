#!/bin/bash
set -e

echo "CONTAINER_START $(date)" >&2

mkdir -p /data/.picoclaw/workspace
mkdir -p /data/.picoclaw/sessions
mkdir -p /data/.picoclaw/cron

if [[ ! -f /data/.picoclaw/config.json ]]; then
    picoclaw onboard
fi

export PICOCLAW_HOME=/data/.picoclaw
export PICOCLAW_GATEWAY_HOST=0.0.0.0
export PICOCLAW_BINARY=/usr/local/bin/picoclaw

# Sync channel env vars to .security.yml
sync_channel_env_to_security() {
    local security_file="$PICOCLAW_HOME/.security.yml"
    if [[ ! -f "$security_file" ]]; then
        echo "model_list: {}" >"$security_file"
        echo "channels: {}" >>"$security_file"
        echo "web: {}" >>"$security_file"
        echo "skills: {}" >>"$security_file"
    fi

    for env_var in $(env | grep "^PICOCLAW_CHANNEL_" | cut -d= -f1); do
        local rest="${env_var#PICOCLAW_CHANNEL_}"
        local channel_name=$(echo "$rest" | cut -d_ -f1 | tr '[:upper:]' '[:lower:]')
        local field_name=$(echo "$rest" | cut -d_ -f2- | tr '[:upper:]' '[:lower:]')
        local value="${!env_var}"

        if [[ -n "$value" ]]; then
            echo "Syncing $env_var -> channels.$channel_name.$field_name"
            if command -v python3 &>/dev/null; then
                python3 -c "
import yaml
with open('$security_file', 'r') as f:
    data = yaml.safe_load(f) or {}
data.setdefault('channels', {}).setdefault('$channel_name', {})
data['channels']['$channel_name']['$field_name'] = '$value'
with open('$security_file', 'w') as f:
    yaml.dump(data, f, default_flow_style=False)
"
            fi
        fi
    done
}

# Install yq if needed
if ! command -v yq &>/dev/null && ! command -v python3 &>/dev/null; then
    curl -sL https://github.com/mikefarah/yq/releases/download/v4.35.1/yq_linux_amd64 -o /tmp/yq
    chmod +x /tmp/yq
    export PATH="$PATH:/tmp"
fi

sync_channel_env_to_security

# Kill existing processes aggressively
pkill -9 -f picoclaw 2>/dev/null || true
pkill -9 nginx 2>/dev/null || true
sleep 2

# Launcher PORT (internal - different from Railway PORT)
LAUNCHER_PORT=18801

# Clear cached launcher config
rm -f "${PICOCLAW_HOME}/launcher-config.json"

# Clear stale PID files before starting
rm -f "${PICOCLAW_HOME}/gateway.pid" "${PICOCLAW_HOME}/launcher.pid" 2>/dev/null || true

# Start launcher (listens on 127.0.0.1:18800)
echo "=== Starting launcher on port $LAUNCHER_PORT ==="
picoclaw-launcher -port $LAUNCHER_PORT 2>&1 | tee /tmp/launcher.log &
LAUNCHER_PID=$!
echo "Launcher started with PID: $LAUNCHER_PID"

sleep 3

# Start nginx to proxy both launcher and gateway
echo "=== Starting nginx ==="
# Template nginx config - proxy to launcher on 18801
sed -e "s/listen 8080;/listen ${PORT:-18800};/" \
    -e "s/server 127.0.0.1:18800/server 127.0.0.1:$LAUNCHER_PORT/" \
    /etc/nginx/nginx.conf.template > /etc/nginx/nginx.conf
nginx -g 'daemon off;' &
NGINX_PID=$!
echo "Nginx started with PID: $NGINX_PID"

sleep 2

# Start gateway (bot gateway)
echo "=== Starting gateway ==="
picoclaw gateway -d 2>&1 | tee /tmp/gateway.log &
GATEWAY_PID=$!
echo "Gateway started with PID: $GATEWAY_PID"

sleep 5

echo "=== Discord debug messages ==="
grep -i "discord" /tmp/gateway.log 2>/dev/null | tail -5 || echo "No Discord messages yet"

# Handle shutdown
trap "kill $LAUNCHER_PID $NGINX_PID $GATEWAY_PID 2>/dev/null; exit 0" SIGTERM SIGINT

# Wait for nginx
while kill -0 $NGINX_PID 2>/dev/null; do
    if ! kill -0 $LAUNCHER_PID 2>/dev/null; then
        echo "Launcher died, restarting..."
        picoclaw-launcher -port $LAUNCHER_PORT 2>&1 | tee /tmp/launcher.log &
        LAUNCHER_PID=$!
    fi
    if ! kill -0 $GATEWAY_PID 2>/dev/null; then
        echo "Gateway died, restarting..."
        rm -f "${PICOCLAW_HOME}/gateway.pid" 2>/dev/null || true
        picoclaw gateway -d 2>&1 | tee -a /tmp/gateway.log &
        GATEWAY_PID=$!
    fi
    sleep 10
done