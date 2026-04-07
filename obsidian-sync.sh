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

# Setup git credentials
git config --global credential.helper "store"
echo "https://x-access-token:${GITHUB_TOKEN}@github.com" >~/.git-credentials

# Check if already a git repo
if [ -d ".git" ]; then
	echo "Already a git repo, pulling changes..."
	git pull origin master 2>/dev/null || git pull origin master 2>/dev/null
else
	# Check if directory is empty
	if [ "$(ls -A)" ]; then
		# Not empty - initialize git and commit existing files
		echo "Initializing git repo with existing files..."
		git init
		git remote add origin "$REPO_URL"
		git fetch origin

		# Try to checkout existing branch
		if git checkout origin/master 2>/dev/null || git checkout origin/master 2>/dev/null; then
			echo "Checked out existing branch"
		else
			# Fresh repo - commit everything
			echo "Fresh repo, committing existing files..."
			git add -A
			git commit -m "Initial commit from PicoClaw"
			git push -u origin master 2>/dev/null || git push -u origin master 2>/dev/null
		fi
	else
		# Empty - clone
		echo "Cloning Obsidian repo..."
		git clone "$REPO_URL" .
	fi
fi

# Sync loop - pull remote changes every 60s
echo "Starting sync loop..."
while true; do
	git fetch origin 2>/dev/null
	if ! git diff --quiet origin/master HEAD 2>/dev/null && ! git diff --quiet origin/master HEAD 2>/dev/null; then
		echo "Pulling remote changes..."
		git pull origin master 2>/dev/null || git pull origin master 2>/dev/null
	fi
	sleep 60
done
