#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_DIR="${COMPOSE_DIR:-$SCRIPT_DIR}"
SERVICE_NAME="${SERVICE_NAME:-windrose}"
MODE="${WINDROSE_MODE:-auto}"
DOCKER_BIN="${DOCKER_BIN:-docker}"
SELF_NAME="${WINDROSE_CMD_NAME:-$(basename "$0")}" 
read -r -a DOCKER_CMD <<< "$DOCKER_BIN"

require_tools() {
    if ! command -v docker >/dev/null 2>&1; then
        echo "[windrose] Error: docker is not installed or not in PATH."
        exit 1
    fi

    if [[ ! -f "$COMPOSE_DIR/docker-compose.yml" ]]; then
        echo "[windrose] Error: docker-compose.yml not found in $COMPOSE_DIR"
        exit 1
    fi
}

detect_mode() {
    if [[ "$MODE" == "auto" ]]; then
        if [[ -f "$COMPOSE_DIR/docker-compose.dev.yml" && "${COMPOSE_DIR##*/}" == *dev* ]]; then
            echo "dev"
        else
            echo "prod"
        fi
    else
        echo "$MODE"
    fi
}

ACTIVE_MODE="$(detect_mode)"
COMPOSE_FILES=(-f docker-compose.yml)
if [[ "$ACTIVE_MODE" == "dev" && -f "$COMPOSE_DIR/docker-compose.dev.yml" ]]; then
    COMPOSE_FILES+=(-f docker-compose.dev.yml)
fi

dc() {
    (
        cd "$COMPOSE_DIR"
        "${DOCKER_CMD[@]}" compose "${COMPOSE_FILES[@]}" "$@"
    )
}

usage() {
    cat <<EOF
Windrose helper script

Usage:
  $SELF_NAME start
  $SELF_NAME stop
  $SELF_NAME restart
  $SELF_NAME status
  $SELF_NAME logs
  $SELF_NAME pull
  $SELF_NAME update
  $SELF_NAME down
  $SELF_NAME install [target]

Notes:
  - compose directory: $COMPOSE_DIR
  - detected mode: $ACTIVE_MODE
  - set DOCKER_BIN="sudo docker" if your user needs sudo
  - set WINDROSE_MODE=prod or WINDROSE_MODE=dev to override auto detection
EOF
}

start_server() {
    echo "[windrose] Starting server ($ACTIVE_MODE mode)..."
    dc up -d
    dc ps
}

stop_server() {
    echo "[windrose] Stopping server..."
    dc stop "$SERVICE_NAME"
}

restart_server() {
    echo "[windrose] Restarting server..."
    if ! dc restart "$SERVICE_NAME"; then
        dc stop "$SERVICE_NAME" || true
        dc up -d
    fi
    dc ps
}

status_server() {
    echo "[windrose] Service status ($ACTIVE_MODE mode):"
    dc ps
}

follow_logs() {
    echo "[windrose] Following logs..."
    dc logs -f "$SERVICE_NAME"
}

pull_image() {
    echo "[windrose] Pulling image defined in compose..."
    dc pull
}

update_server() {
    echo "[windrose] Pulling the selected image tag and recreating the container..."
    dc pull
    dc up -d
    dc ps
}

down_server() {
    echo "[windrose] Stopping and removing the stack..."
    dc down
}

install_self() {
    local target="${1:-/usr/local/bin/windrosectl}"

    if ln -sf "$SCRIPT_DIR/windrose" "$target" 2>/dev/null; then
        echo "[windrose] Installed launcher at $target"
    else
        echo "[windrose] Could not write to $target"
        echo "[windrose] Try: sudo ln -sf \"$SCRIPT_DIR/windrose\" \"$target\""
        exit 1
    fi
}

require_tools

case "${1:-help}" in
    start)
        start_server
        ;;
    stop)
        stop_server
        ;;
    restart)
        restart_server
        ;;
    status|ps)
        status_server
        ;;
    logs)
        follow_logs
        ;;
    pull)
        pull_image
        ;;
    update)
        update_server
        ;;
    down)
        down_server
        ;;
    install)
        install_self "${2:-}"
        ;;
    help|-h|--help|"")
        usage
        ;;
    *)
        usage
        exit 1
        ;;
esac
