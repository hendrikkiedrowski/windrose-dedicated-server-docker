# Windrose Dedicated Server — Docker

Self-hosted dedicated server for [Windrose](https://store.steampowered.com/app/2700940/Windrose/) running on Linux via Docker, SteamCMD and Wine.

> **No port forwarding required** — players join via **Invite Code** from `ServerDescription.json`.

---

## Features

- Automatic server download and update via SteamCMD
- Optional update-on-start toggle for faster restarts
- Wine + Xvfb headless runtime (no desktop required)
- Persistent saves and config via bind-mounted volumes
- Optional env-driven patching for server name, password, invite code, and max players
- PUID and PGID support for better host permission compatibility
- `restart: unless-stopped` — survives host reboots automatically
- Healthcheck watching the server process
- Log rotation (20 MB × 5 files)
- Anonymous SteamCMD login by default

---

## Requirements

| Component | Minimum |
|-----------|---------|
| OS        | Ubuntu 22.04+ / Debian 12+ (Linux host) |
| Docker    | 24.x+ |
| Docker Compose | v2.x (`docker compose`) |
| RAM       | 8 GB (16 GB recommended for 4 players) |
| Disk      | 8 GB free for game files |

---

## Quick start

```bash
# 1. Clone the repository
git clone https://github.com/UberDudePL/windrose-dedicated-server-docker.git
cd windrose-dedicated-server-docker

# 2. Copy the example environment file
cp .env.example .env

# 3. Edit basic values if needed
nano .env

# 4. Start the server (downloads game files on first run ~3 GB)
docker compose up -d

# 5. Follow logs
docker compose logs -f windrose
```

Recommended image tags:

```text
Stable: ghcr.io/uberdudepl/windrose-dedicated-server-docker:v1.0.1
Latest: ghcr.io/uberdudepl/windrose-dedicated-server-docker:latest
```

---

## Configuration

### Common server settings

You can set the most common values directly in `.env`:

```dotenv
SERVER_NAME=My Windrose Server
SERVER_PASSWORD=
MAX_PLAYERS=4
INVITE_CODE=
```

If you prefer manual editing, stop the server first and edit `data/R5/ServerDescription.json` directly.

### Environment variables (`.env`)

Copy `.env.example` to `.env` and change only the values you need.

```dotenv
PUID=1000                    # Host user id for mounted files
PGID=1000                    # Host group id for mounted files
STEAM_LOGIN=anonymous        # SteamCMD login
STEAM_PASS=                  # Leave empty for anonymous login
WINDROSE_APP_ID=4129620      # Steam AppID for Windrose Dedicated Server
UPDATE_ON_START=true         # Set false to skip update on container restart
GENERATE_SETTINGS=true       # Set false to skip env-based JSON patching
INVITE_CODE=                 # Optional invite code
SERVER_NAME=                 # Optional server name
SERVER_PASSWORD=             # Optional password
MAX_PLAYERS=4                # Recommended for stability
P2P_PROXY_ADDRESS=127.0.0.1  # Keep default unless you know you need a change
PORT=7777
QUERYPORT=7778
MULTIHOME=0.0.0.0
```

### `docker-compose.yml` overrides

| Variable | Default | Description |
|----------|---------|-------------|
| `PUID` | `1000` | User id used for mounted files |
| `PGID` | `1000` | Group id used for mounted files |
| `UPDATE_ON_START` | `true` | Update and validate server files on startup |
| `GENERATE_SETTINGS` | `true` | Auto-patch `ServerDescription.json` from env values |
| `INVITE_CODE` | empty | Invite code shown to players |
| `SERVER_NAME` | empty | Display name of the server |
| `SERVER_PASSWORD` | empty | Leave empty for a public server |
| `MAX_PLAYERS` | `4` | Maximum number of simultaneous players |
| `P2P_PROXY_ADDRESS` | `127.0.0.1` | Internal socket proxy address |
| `PORT` | `7777` | Game port (UDP) |
| `QUERYPORT` | `7778` | Query port (UDP) |
| `WINDROSE_APP_ID` | `4129620` | Steam AppID |
| `STEAM_LOGIN` | `anonymous` | SteamCMD login |

---

## Volumes

| Host path | Container path | Contents |
|-----------|---------------|----------|
| `./data`  | `/data`       | Server files, saves, config |
| `./steam-home` | `/home/steam` | Wine prefix, SteamCMD cache |

---

## How players join

1. Find your **Invite Code** in `data/R5/ServerDescription.json` → `InviteCode` field
2. Share it with players — they use it in-game under **Join via Code**
3. No port forwarding is required

---

## Useful commands

```bash
# Start
docker compose up -d

# Stop
docker compose stop

# View live logs
docker compose logs -f windrose

# Force game update
docker compose down && docker compose up -d

# Check server process inside container
docker compose exec windrose pgrep -a WindroseServer

# Container status + health
docker compose ps
```

---

## Backup saves

```bash
# Manual backup
tar -czf windrose-backup-$(date +%F).tar.gz data/R5/Saved

# Cron — every 6 hours (add via crontab -e)
0 */6 * * * tar --warning=no-file-changed -czf /root/windrose-backup-$(date +\%F-\%H).tar.gz /path/to/windrose/data/R5/Saved

# Delete backups older than 7 days
find /root/windrose-backup-* -mtime +7 -delete
```

---

## Directory structure

```
windrose/
├── Dockerfile          # Ubuntu 22.04 + Wine + SteamCMD
├── docker-compose.yml  # Service definition
├── entrypoint.sh       # SteamCMD update + server start logic
├── .env                # Environment variables (do not commit with secrets)
├── data/               # Persistent server files and saves (created on first run)
│   └── R5/
│       ├── ServerDescription.json
│       └── Saved/
└── steam-home/         # Wine prefix and SteamCMD state (created on first run)
```

---

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| `wine: '/home/steam' is not owned by you` | Set `PUID` and `PGID` correctly in `.env`, then restart the container |
| `Server is already active for display 99` | Stale Xvfb lock — entrypoint removes it automatically on restart |
| `ERROR! Failed to install app` | Check SteamCMD logs and verify the app id and Steam login mode |
| Server not visible to players | Share the `InviteCode` from `ServerDescription.json` |
| Config reset after restart | Edit JSON only when container is stopped |

---

## Versioning policy

- Use `:latest` only for testing.
- Use pinned tags like `:v1.0.1` for production/stable servers.
- Create a new release tag when you change runtime behavior, dependencies, or startup logic.

Release commands for the next version:

```bash
cd /windrose
git fetch --all --tags
git tag v1.0.2
git push origin v1.0.2
```

---

## Technical notes

- Supports configurable `PUID` and `PGID` to align mounted volumes with the host
- `network_mode: host` — no Docker NAT, direct network access
- Xvfb provides a headless X display required by Wine
- `stop_grace_period: 90s` — allows the server to save before shutdown
- Optional env-based patching can update `ServerDescription.json` automatically

---

## Support

If this project saved you time and you want to support further maintenance, you can use:

- Ko-fi: https://ko-fi.com/uberdudepl
- PayPal: https://paypal.me/uberdudepl
- Revolut: https://revolut.me/uberdudepl

---

## License

MIT — see [LICENSE](LICENSE)
