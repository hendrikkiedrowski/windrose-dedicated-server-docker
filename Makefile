.PHONY: up down restart logs build status backup update

# Start the server (build image if needed)
up:
	docker compose up -d --build

# Stop the server gracefully
down:
	docker compose stop

# Restart the server
restart:
	docker compose down && docker compose up -d

# Follow live logs
logs:
	docker compose logs -f windrose

# Build image only
build:
	docker compose build

# Container status + health
status:
	docker compose ps

# Manual backup of saves
backup:
	tar --warning=no-file-changed -czf windrose-backup-$$(date +%F-%H%M).tar.gz data/R5/Saved
	@echo "Backup saved: windrose-backup-$$(date +%F-%H%M).tar.gz"

# Force game update (stops, re-downloads, starts)
update:
	docker compose stop
	docker compose run --rm windrose /opt/steamcmd/steamcmd.sh \
		+force_install_dir /data \
		+login anonymous \
		+app_update 4129620 validate \
		+quit
	docker compose up -d

# Show server invite code
invite:
	@grep -o '"InviteCode": "[^"]*"' data/R5/ServerDescription.json || echo "Server not yet started — run 'make up' first"
