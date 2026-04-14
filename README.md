# Windrose Dedicated Server — Docker

Self-hosted dedicated server for [Windrose](https://store.steampowered.com/app/2700940/Windrose/) running on Linux via Docker, SteamCMD and Wine.

> **No port forwarding required** — players join via **Invite Code** from `ServerDescription.json`.

---

## Features

- Automatic server download and update via SteamCMD on every start
- Wine + Xvfb headless runtime (no desktop required)
- Persistent saves and config via bind-mounted volumes
- `restart: unless-stopped` — survives host reboots automatically
- Healthcheck watching the server process
- Log rotation (20 MB × 5 files)
- Anonymous SteamCMD login — no Steam account needed

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

## Quick start (prebuilt image from GHCR)

Use the published image if you do not want to build locally.

Recommended (stable):

```
ghcr.io/uberdudepl/windrose-dedicated-server-docker:v1.0.0
```

Latest (testing/newest):

```
ghcr.io/uberdudepl/windrose-dedicated-server-docker:latest
```

### Minimal `docker-compose.yml` for users

```yaml
services:
  windrose:
    image: ghcr.io/uberdudepl/windrose-dedicated-server-docker:v1.0.0
    container_name: windrose
    restart: unless-stopped
    stop_grace_period: 90s
    network_mode: host
    env_file:
      - .env
    environment:
      WINDROSE_APP_ID: 4129620
      STEAM_LOGIN: ${STEAM_LOGIN:-anonymous}
      STEAM_PASS: ${STEAM_PASS:-}
      WINEDEBUG: -all
      DISPLAY: :99
      PORT: 7777
      QUERYPORT: 7778
    volumes:
      - ./data:/data
      - ./steam-home:/home/steam
```

`.env` example:

```dotenv
STEAM_LOGIN=anonymous
STEAM_PASS=
```

Start:

```bash
docker compose up -d
docker compose logs -f windrose
```

---

## Quick start

```bash
# 1. Clone the repository
git clone https://github.com/UberDudePL/windrose-dedicated-server-docker.git
cd windrose-dedicated-server-docker

# 2. Set ownership (required for Wine to work inside the container)
chown -R 1000:1000 .

# 3. Start the server (downloads game files on first run ~3 GB)
docker compose up -d

# 4. Follow logs
docker compose logs -f windrose
```

After a few minutes you will see:

```
Success! App '4129620' fully installed.
Starting Windrose dedicated server
```

---

## Configuration

### Server name, password, player limit

Edit **`data/R5/ServerDescription.json`** while the server is **stopped**:

```bash
docker compose stop
nano data/R5/ServerDescription.json
docker compose start
```

```json
{
  "Version": 1,
  "ServerDescription_Persistent": {
    "InviteCode": "xxxxxxxx",
    "IsPasswordProtected": true,
    "Password": "your-password",
    "ServerName": "My Windrose Server",
    "MaxPlayerCount": 4
  }
}
```

> ⚠️ Always stop the server before editing JSON — the server overwrites the file on shutdown.

### Environment variables (`.env`)

```dotenv
STEAM_LOGIN=anonymous        # SteamCMD login (anonymous works for this app)
WINDROSE_APP_ID=4129620      # Steam AppID for Windrose Dedicated Server
STEAM_PASS=                  # Leave empty for anonymous login
```

### `docker-compose.yml` overrides

| Variable | Default | Description |
|----------|---------|-------------|
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
| `wine: '/home/steam' is not owned by you` | Run `chown -R 1000:1000 .` on the host |
| `Server is already active for display 99` | Stale Xvfb lock — entrypoint removes it automatically on restart |
| `ERROR! Failed to install app` | Check SteamCMD logs; ensure `STEAM_LOGIN=anonymous` is set |
| Server not visible to players | Share the `InviteCode` from `ServerDescription.json` |
| Config reset after restart | Edit JSON only when container is stopped |

---

## Versioning policy

- Use `:latest` only for testing.
- Use pinned tags like `:v1.0.0` for production/stable servers.
- Create a new release tag when you change runtime behavior, dependencies, or startup logic.

Release commands:

```bash
cd /windrose
git fetch --all --tags
git tag v1.0.0
git push origin v1.0.0
```

---

## Public package and CI checklist

1. GitHub -> Packages -> `windrose-dedicated-server-docker` -> set visibility to **Public**.
2. Verify **Build and Publish Docker Image** workflow is green.
3. Verify **Secret Scan** workflow is green.
4. Confirm package tags exist (`latest`, `v*`, `sha-*`).
5. Keep `.env`, `data/`, `steam-home/`, and `game/` untracked.

---

## Technical notes

- Uses **UID 1000** inside the container — host directories must be owned by `1000:1000`
- `network_mode: host` — no Docker NAT, direct network access
- Xvfb provides a headless X display required by Wine
- `stop_grace_period: 90s` — allows the server to save before shutdown

---

## License

MIT — see [LICENSE](LICENSE)
