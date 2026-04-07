#!/bin/bash
# Obsidian vault sync script - syncs workspace to GitHub

WORKSPACE="/data/.picoclaw/workspace"
REPO_URL="${OBSIDIAN_REPO_URL}"
GITHUB_TOKEN="${GITHUB_TOKEN}"

if [ -z "$REPO_URL" ] || [ -z "$GITHUB_TOKEN" ]; then
    echo "OBSIDIAN_REPO_URL or GITHUB_TOKEN not set, skipping sync"
    exit 0
fi

cd "$WORKSPACE" || exit 1

# Configure git if not already done
git config --local credential.helper "store"
echo "https://x-access-token:${GITHUB_TOKEN}@github.com" > ~/.git-credentials

# Clone or pull
if [ -d ".git" ]; then
    echo "Pulling Obsidian changes..."
    git pull origin main 2>/dev/null || git pull origin master 2>/dev/null
else
    echo "Cloning Obsidian repo..."
    git clone "$REPO_URL" .
fi

# Sync loop
while true; do
    git fetch origin
    if ! git diff --quiet origin/main HEAD 2>/dev/null && ! git diff --quiet origin/master HEAD 2>/dev/null; then
        echo "Pulling remote changes..."
        git pull origin main 2>/dev/null || git pull origin master 2>/dev/null
    fi
    sleep 60
done
