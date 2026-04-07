#!/bin/bash
set -e

echo "CONTAINER_START $(date)" >&2

mkdir -p /data/.picoclaw/workspace
mkdir -p /data/.picoclaw/sessions
mkdir -p /data/.picoclaw/cron

# Check if config exists and show what's in it
echo "=== Checking PicoClaw config ==="
if [[ -f /data/.picoclaw/config.json ]]; then
    echo "Config file exists, checking validity..."
    if python3 -c "import json; json.load(open('/data/.picoclaw/config.json'))" 2>/dev/null; then
        echo "Config is valid JSON"
        # Print full config (redact sensitive values)
        python3 -c "
import json
with open('/data/.picoclaw/config.json') as f:
    data = json.load(f)
    # Redact sensitive fields
    for key in ['launcher_token', 'providers', 'channels']:
        if key in data:
            data[key] = '<redacted>'
    print(json.dumps(data, indent=2))
"
    else
        echo "WARNING: Config is NOT valid JSON!"
        echo "Content:"
        cat /data/.picoclaw/config.json
    fi
else
    echo "No config.json found - will run onboard"
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
pkill -9 -f "picoclaw" 2>/dev/null || true
pkill -9 -f "gateway" 2>/dev/null || true
pkill -9 -f "nginx" 2>/dev/null || true
sleep 2

# Clear all PID files to ensure clean start
rm -f "${PICOCLAW_HOME}/"*.pid 2>/dev/null || true
rm -f "/data/.picoclaw/"*.pid 2>/dev/null || true

# Start obsidian sync AFTER pkill, as separate process that won't be affected
echo "=== Checking Obsidian config ==="
echo "OBSIDIAN_REPO_URL: ${OBSIDIAN_REPO_URL:-not set}"
echo "GITHUB_TOKEN: ${GITHUB_TOKEN:+set}"

OBSIDIAN_PID=""
if [[ -n "$OBSIDIAN_REPO_URL" ]] && [[ -n "$GITHUB_TOKEN" ]]; then
    echo "=== Starting Obsidian sync ==="
    chmod +x /app/obsidian-sync.sh
    
    # Start in background with redirect to get output
    bash -c '/app/obsidian-sync.sh' > /tmp/obsidian.log 2>&1 &
    OBSIDIAN_PID=$!
    echo "Obsidian sync started with PID: $OBSIDIAN_PID"
    
    # Wait a moment then check if it's still running
    sleep 3
    if kill -0 $OBSIDIAN_PID 2>/dev/null; then
        echo "Obsidian sync is running"
    else
        echo "Obsidian sync failed to start, checking log:"
        cat /tmp/obsidian.log
    fi
else
    echo "Warning: OBSIDIAN_REPO_URL or GITHUB_TOKEN not set, skipping Obsidian sync"
fi

# Launcher PORT (internal - use 18801 hardcoded, Railway PORT controls nginx external port)
LAUNCHER_PORT=18801

# Validate ports don't conflict
if [[ "$PORT" == "$LAUNCHER_PORT" ]]; then
    echo "ERROR: PORT ($PORT) cannot equal LAUNCHER_PORT ($LAUNCHER_PORT)"
    exit 1
fi

# Clear cached launcher config
rm -f "${PICOCLAW_HOME}/launcher-config.json"

# Start launcher (listens on 127.0.0.1:18801)
# Capture output to /tmp for debugging
echo "=== Starting launcher on port $LAUNCHER_PORT ==="
picoclaw-launcher -port $LAUNCHER_PORT 2>&1 | tee /tmp/launcher.log &
LAUNCHER_PID=$!
echo "Launcher started with PID: $LAUNCHER_PID"

# Wait longer for launcher to be ready
sleep 5

# Check if launcher is actually running
if ! kill -0 $LAUNCHER_PID 2>/dev/null; then
    echo "ERROR: Launcher failed to start. Log output:"
    cat /tmp/launcher.log
    exit 1
fi

# Verify launcher is listening
if ! ss -tlnp | grep ":$LAUNCHER_PORT" > /dev/null; then
    echo "ERROR: Launcher not listening on port $LAUNCHER_PORT"
    cat /tmp/launcher.log
    exit 1
fi
echo "Launcher is listening on port $LAUNCHER_PORT"

# Start nginx to proxy both launcher and gateway
echo "=== Starting nginx ==="
# Template nginx config - proxy to launcher on 18801, listen on Railway PORT (18800)
sed -e "s/listen 8080;/listen ${PORT:-18800};/" \
    -e "s/server 127.0.0.1:18800;/server 127.0.0.1:$LAUNCHER_PORT;/" \
    /etc/nginx/nginx.conf.template > /etc/nginx/nginx.conf

echo "=== Nginx config ==="
echo "Listening on: ${PORT:-18800}"
echo "Proxying to: 127.0.0.1:$LAUNCHER_PORT"
cat /etc/nginx/nginx.conf | head -20

nginx -g 'daemon off;' &
NGINX_PID=$!
echo "Nginx started with PID: $NGINX_PID"

sleep 2

# Start gateway (bot gateway) - run WITHOUT -d flag to keep it in foreground
echo "=== Starting gateway (no daemon) ==="
picoclaw gateway -d 2>&1 &
GATEWAY_PID=$!
echo "Gateway started with PID: $GATEWAY_PID"
trap "kill $LAUNCHER_PID $NGINX_PID $GATEWAY_PID $OBSIDIAN_PID 2>/dev/null; exit 0" SIGTERM SIGINT

# Wait for nginx
while kill -0 $NGINX_PID 2>/dev/null; do
    if ! kill -0 $LAUNCHER_PID 2>/dev/null; then
        echo "Launcher died, restarting..."
        picoclaw-launcher -port $LAUNCHER_PORT 2>&1 | tee /tmp/launcher.log &
        LAUNCHER_PID=$!
    fi
    if ! kill -0 $GATEWAY_PID 2>/dev/null; then
        echo "Gateway died, restarting..."
        # Get exit code
        wait $GATEWAY_PID 2>/dev/null
        EXIT_CODE=$?
        echo "Gateway exited with code: $EXIT_CODE"
        
        # Aggressively kill ALL picoclaw processes and verify they're dead before restarting
        # This prevents stale PID conflicts that cause restart loops
        for i in {1..5}; do
            pkill -9 -f "picoclaw" 2>/dev/null || true
            pkill -9 -f "gateway" 2>/dev/null || true
            sleep 1
            if ! pgrep -f "picoclaw" >/dev/null && ! pgrep -f "gateway" >/dev/null; then
                echo "All picoclaw processes terminated successfully"
                break
            fi
            echo "Waiting for processes to terminate... attempt $i/5"
            if [[ $i -eq 5 ]]; then
                echo "WARNING: Some processes may still be running, proceeding anyway"
            fi
        done
        
        # Wait for ports to be released
        sleep 2
        
        # Clean all PID files
        rm -f "${PICOCLAW_HOME}/.picoclaw.pid" "/data/.picoclaw/"*.pid 2>/dev/null || true
        rm -f "/tmp/"*gateway* 2>/dev/null || true
        
        # Debug: Show recent launcher logs
        echo "=== Recent launcher logs ==="
        tail -20 /tmp/launcher.log 2>/dev/null || echo "No launcher log"
        
        picoclaw gateway -d 2>&1 | tee /tmp/gateway.log &
        GATEWAY_PID=$!
    fi
    sleep 10
done
