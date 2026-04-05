#!/bin/bash
set -e

OBSIDIAN_DIR="/data/.picoclaw/workspace/obsidian"
REPO_URL="${OBSIDIAN_REPO_URL-}"
SYNC_INTERVAL="${OBSIDIAN_SYNC_INTERVAL:-300}"
GITHUB_TOKEN="${GITHUB_TOKEN-}"

# Configure git
git config --global user.email "picoclaw@railway.app"
git config --global user.name "PicoClaw Bot"
git config --global init.defaultBranch main

# Clone repo if token is provided
if [ -n "$GITHUB_TOKEN" ] && [ -n "$REPO_URL" ]; then
	# Convert HTTPS URL to include token: https://TOKEN@github.com/user/repo
	REPO_URL_WITH_TOKEN=$(echo "$REPO_URL" | sed "s|https://|https://${GITHUB_TOKEN}@|")
	export REPO_URL_WITH_TOKEN

	if [ ! -d "$OBSIDIAN_DIR/.git" ]; then
		echo "Cloning Obsidian vault..."
		git clone "$REPO_URL_WITH_TOKEN" "$OBSIDIAN_DIR" 2>&1 || {
			echo "Clone failed, trying to initialize and fetch..."
			mkdir -p "$OBSIDIAN_DIR"
			cd "$OBSIDIAN_DIR"
			git init
			git remote add origin "$REPO_URL_WITH_TOKEN"
			git fetch origin
			DEFAULT_BRANCH=$(git branch -r | head -1 | sed 's/.*origin\///')
			git checkout -b "$DEFAULT_BRANCH" "origin/$DEFAULT_BRANCH" 2>/dev/null || git checkout -b main origin/main
		}
	else
		echo "Obsidian vault already exists, updating remote..."
		cd "$OBSIDIAN_DIR"
		git remote set-url origin "$REPO_URL_WITH_TOKEN"
	fi
else
	echo "Warning: GITHUB_TOKEN or OBSIDIAN_REPO_URL not set, skipping Obsidian sync"
	exit 0
fi

# Sync loop
sync_vault() {
	cd "$OBSIDIAN_DIR"

	# Update remote with token for push operations
	git remote set-url origin "$REPO_URL_WITH_TOKEN" 2>/dev/null || true

	# Detect default branch
	DEFAULT_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@' || echo "main")

	# Pull latest changes
	echo "[$(date)] Pulling latest changes from $DEFAULT_BRANCH..."
	git fetch origin
	git merge "origin/$DEFAULT_BRANCH" --ff-only 2>/dev/null || {
		echo "Merge conflict or diverged branches, resetting to origin/$DEFAULT_BRANCH"
		git reset --hard "origin/$DEFAULT_BRANCH"
	}

	# Check for local changes
	if [ -n "$(git status --porcelain)" ]; then
		echo "[$(date)] Committing local changes..."
		git add -A
		git commit -m "Auto-sync from PicoClaw ($(date -Iminutes))" || true
		git push origin "$DEFAULT_BRANCH" || {
			echo "Push failed, pulling and retrying..."
			git pull --rebase origin "$DEFAULT_BRANCH"
			git push origin "$DEFAULT_BRANCH"
		}
		echo "[$(date)] Pushed changes to GitHub"
	else
		echo "[$(date)] No local changes to sync"
	fi
}

# Initial sync
sync_vault

# Continuous sync loop
echo "Starting Obsidian sync loop (interval: ${SYNC_INTERVAL}s)"
while true; do
	sleep "$SYNC_INTERVAL"
	sync_vault
done
