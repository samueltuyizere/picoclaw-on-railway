# PicoClaw Railway Template

This repo packages **PicoClaw** for Railway with the built-in Launcher Web UI.

## What you get

- **PicoClaw Launcher** - Official web-based UI for configuration and chat
- **PicoClaw Gateway** - Bot gateway for Discord, Telegram, Slack, and more
- **Persistent state** via Railway Volume (config, workspace, sessions survive redeploys)

## How it works

- The container builds PicoClaw from source (pinned to a specific commit for reproducibility)
- The launcher runs on internal port 18800
- Nginx proxies Railway's public port 8080 to the launcher
- Configuration is stored in `/data/.picoclaw/config.json`

## Quick start

1. Deploy this repo to Railway
2. Set Railway to expose port 18800
3. Open your Railway URL and log in with `PICOCLAW_LAUNCHER_TOKEN`

## Environment variables

| Variable                | Default           | Description                                      |
| ----------------------- | ----------------- | ------------------------------------------------ |
| `PORT`                  | `8080`            | Port nginx listens on (Railway public port)     |
| `PICOCLAW_VERSION`      | (pinned commit)   | Git commit SHA to build PicoClaw from           |
| `PICOCLAW_HOME`         | `/data/.picoclaw` | Config directory location                       |
| `PICOCLAW_GATEWAY_HOST` | `0.0.0.0`         | Gateway listen address                           |
| `PICOCLAW_LAUNCHER_TOKEN` | (auto-generated) | Web UI auth token (set your own for persistence) |

## Channel configuration

Configure channels via Railway environment variables:

```
PICOCLAW_CHANNEL_DISCORD_ENABLED=true
PICOCLAW_CHANNEL_DISCORD_TOKEN=your-bot-token
PICOCLAW_CHANNEL_TELEGRAM_ENABLED=true
PICOCLAW_CHANNEL_TELEGRAM_TOKEN=your-bot-token
```

## Model configuration

```
PICOCLAW_MODEL_OPENROUTER_MODEL=openrouter/anthropic/claude-sonnet-4
PICOCLAW_MODEL_OPENROUTER_API_KEY=sk-or-v1-xxx
PICOCLAW_DEFAULT_MODEL_NAME=openrouter
```

## Getting Discord bot token

1. Go to the [Discord Developer Portal](https://discord.com/developers/applications)
2. **New Application** → pick a name
3. Open the **Bot** tab → **Add Bot**
4. Enable **MESSAGE CONTENT INTENT** under Privileged Gateway Intents
5. Copy the **Bot Token** and set `PICOCLAW_CHANNEL_DISCORD_TOKEN`
6. Set `PICOCLAW_CHANNEL_DISCORD_ENABLED=true`
7. Invite the bot to your server (OAuth2 URL Generator → scopes: `bot`, `applications.commands`)

## Local testing

```bash
docker build -t picoclaw-railway-template .

docker run --rm -p 8080:8080 \
  -v $(pwd)/.tmpdata:/data \
  picoclaw-railway-template

# Open http://localhost:8080 for the web UI
```

## FAQ

**Q: How do I access the web UI?**

A: Go to your Railway URL on port 18800. Set `PICOCLAW_LAUNCHER_TOKEN` env var for a persistent token.

**Q: The gateway shows "No channels enabled". What's wrong?**

A: Make sure you've set both the channel token AND enabled flag:

- `PICOCLAW_CHANNEL_DISCORD_TOKEN=your-token`
- `PICOCLAW_CHANNEL_DISCORD_ENABLED=true`

**Q: How do I change the AI model?**

A: Either use the web UI or set environment variables:

- `PICOCLAW_DEFAULT_MODEL_NAME=openrouter`
- `PICOCLAW_MODEL_OPENROUTER_MODEL=openrouter/anthropic/claude-sonnet-4`
- `PICOCLAW_MODEL_OPENROUTER_API_KEY=sk-or-v1-xxx`