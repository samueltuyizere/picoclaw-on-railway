#!/bin/bash
set -e

mkdir -p /data/.picoclaw/workspace
mkdir -p /data/.picoclaw/sessions
mkdir -p /data/.picoclaw/cron

# Initialize config if not present
if [ ! -f /data/.picoclaw/config.json ]; then
    picoclaw onboard
fi

export PICOCLAW_HOME=/data/.picoclaw
export PICOCLAW_GATEWAY_HOST=0.0.0.0

# Sync channel env vars to .security.yml for Go gateway
# The Go picoclaw gateway reads tokens from .security.yml, not from config.json
sync_channel_env_to_security() {
    local security_file="$PICOCLAW_HOME/.security.yml"
    local temp_file=$(mktemp)

    # Create .security.yml if it doesn't exist
    if [ ! -f "$security_file" ]; then
        echo "model_list: {}" >"$security_file"
        echo "channels: {}" >>"$security_file"
        echo "web: {}" >>"$security_file"
        echo "skills: {}" >>"$security_file"
    fi

    # Process PICOCLAW_CHANNEL_* env vars
    for env_var in $(env | grep "^PICOCLAW_CHANNEL_" | cut -d= -f1); do
        # Extract channel name and field from env var name
        # PICOCLAW_CHANNEL_DISCORD_TOKEN -> discord, token
        local rest="${env_var#PICOCLAW_CHANNEL_}"
        local channel_name=$(echo "$rest" | cut -d_ -f1 | tr '[:upper:]' '[:lower:]')
        local field_name=$(echo "$rest" | cut -d_ -f2- | tr '[:upper:]' '[:lower:]')
        local value="${!env_var}"

        if [ -n "$value" ]; then
            echo "Syncing env var $env_var -> channels.$channel_name.$field_name"

            # Use yq or sed to update the yaml file
            if command -v yq &>/dev/null; then
                yq -i ".channels.$channel_name.$field_name = \"$value\"" "$security_file"
            else
                # Fallback: use Python if available
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
        fi
    done
}

# Install yq for YAML manipulation if not present
if ! command -v yq &>/dev/null && ! command -v python3 &>/dev/null; then
    curl -sL https://github.com/mikefarah/yq/releases/download/v4.35.1/yq_linux_amd64 -o /tmp/yq
    chmod +x /tmp/yq
    export PATH="$PATH:/tmp"
fi

sync_channel_env_to_security

# Start Obsidian vault sync (background process)
if [ -n "$GITHUB_TOKEN" ] && [ -n "$OBSIDIAN_REPO_URL" ]; then
    echo "Starting Obsidian vault sync..."
    /app/obsidian-sync.sh &
    OBSIDIAN_SYNC_PID=$!
fi

# Kill any existing launcher process
pkill -f "picoclaw-launcher" 2>/dev/null || true
sleep 1

# Clear any cached launcher config that might have wrong public URL
rm -f "$PICOCLAW_HOME/launcher-config.json"

# Launcher runs on Railway's PORT (18800)
LAUNCHER_PORT="${PORT:-18800}"

# Make picoclaw available to launcher
export PICOCLAW_BINARY=/usr/local/bin/picoclaw

# Kill any existing processes
pkill -f "picoclaw-launcher" 2>/dev/null || true
pkill nginx 2>/dev/null || true
sleep 2

echo "=== Starting launcher on port $LAUNCHER_PORT ==="

# Start the launcher on all interfaces (public mode)
picoclaw-launcher -public -port $LAUNCHER_PORT 2>&1 | tee /tmp/launcher.log &
LAUNCHER_PID=$!
echo "Launcher started with PID: $LAUNCHER_PID (public mode)"

sleep 3

# Start the gateway (bot gateway)
echo "Starting gateway with PICOCLAW_CHANNEL_DISCORD_ENABLED=${PICOCLAW_CHANNEL_DISCORD_ENABLED}"

# Kill any existing gateway processes
pkill -9 -f "picoclaw" || true
sleep 3

# Run gateway with debug logging
picoclaw gateway -d 2>&1 | tee /tmp/gateway_full.log &
GATEWAY_PID=$!
echo "Started gateway (PID: $GATEWAY_PID)"

sleep 5

# Show any Discord-related messages from gateway
echo "=== Discord debug messages ==="
grep -i "discord" /tmp/gateway_full.log 2>/dev/null | tail -5 || echo "No Discord messages yet"

# Handle shutdown gracefully
trap "kill $LAUNCHER_PID $GATEWAY_PID ${OBSIDIAN_SYNC_PID-} 2>/dev/null; exit 0" SIGTERM SIGINT

# Wait for launcher (primary process), but also monitor gateway
while kill -0 $LAUNCHER_PID 2>/dev/null; do
    # Check if gateway is still running
    if ! kill -0 $GATEWAY_PID 2>/dev/null; then
        echo "Gateway died, restarting..."
        picoclaw gateway -d &
        GATEWAY_PID=$!
    fi
    sleep 10
done