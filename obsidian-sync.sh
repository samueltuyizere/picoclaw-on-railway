#!/bin/bash
# Obsidian vault sync script - syncs to GitHub

OBSIDIAN_DIR="/data/.picoclaw/workspace/obsidian"
REPO_URL="${OBSIDIAN_REPO_URL}"
GITHUB_TOKEN="${GITHUB_TOKEN}"

if [ -z "$REPO_URL" ] || [ -z "$GITHUB_TOKEN" ]; then
    echo "OBSIDIAN_REPO_URL or GITHUB_TOKEN not set, skipping sync"
    exit 0
fi

mkdir -p "$OBSIDIAN_DIR"
cd "$OBSIDIAN_DIR" || exit 1

# Setup git credentials
git config --global credential.helper "store"
echo "https://x-access-token:${GITHUB_TOKEN}@github.com" > ~/.git-credentials

# Check if already a git repo
if [ -d ".git" ]; then
    echo "Already a git repo, pulling changes..."
    git pull origin main 2>/dev/null || git pull origin master 2>/dev/null
else
    echo "Cloning Obsidian repo..."
    git clone "$REPO_URL" .
fi

# Sync loop
echo "Starting sync loop..."
while true; do
    git fetch origin 2>/dev/null
    if ! git diff --quiet origin/main HEAD 2>/dev/null && ! git diff --quiet origin/master HEAD 2>/dev/null; then
        echo "Pulling remote changes..."
        git pull origin main 2>/dev/null || git pull origin master 2>/dev/null
    fi
    sleep 60
done
