#!/bin/bash
set -e

# Ensure /data is writable with full permissions
mkdir -p /data
chmod -R 777 /data

# Ensure directories exist
mkdir -p /data/.picoclaw/workspace
mkdir -p /data/.picoclaw/sessions
mkdir -p /data/.picoclaw/cron

export HOME=/data
export PICOCLAW_HOME=/data/.picoclaw
export PICOCLAW_BINARY=/usr/local/bin/picoclaw

# Start Obsidian sync in background if configured
if [ -n "$OBSIDIAN_REPO_URL" ] && [ -n "$GITHUB_TOKEN" ]; then
    echo "Starting Obsidian sync..."
    /app/obsidian-sync.sh &
fi

# Run the launcher directly - it handles gateway management
exec picoclaw-launcher -public -port ${PORT:-18800}
