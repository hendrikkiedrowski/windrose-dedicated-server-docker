#!/usr/bin/env bash
# Pterodactyl / Wings fork of the Windrose entrypoint.
# Key differences from the upstream image:
#   - No su/usermod — Wings runs the container as the correct user already.
#   - SERVERDIR=/home/container/data  (inside the Wings-mounted volume)
#   - STEAM_HOME=/home/container/.steam-home  (also persisted in the volume)
#   - WINEPREFIX lives inside STEAM_HOME so it persists across restarts.

set -euo pipefail

APPID="${WINDROSE_APP_ID:-4129620}"
SERVERDIR="${SERVERDIR:-/home/container/data}"
STEAM_HOME="${STEAM_HOME:-/home/container/.steam-home}"
WINEPREFIX="${WINEPREFIX:-$STEAM_HOME/.wine}"

# SteamCMD requires a writable HOME and XDG dirs — Wings doesn't set these.
export HOME="$STEAM_HOME"
export XDG_DATA_HOME="$STEAM_HOME/.local/share"
export XDG_CONFIG_HOME="$STEAM_HOME/.config"
export XDG_CACHE_HOME="$STEAM_HOME/.cache"
STEAM_LOGIN="${STEAM_LOGIN:-anonymous}"
STEAM_PASS="${STEAM_PASS:-}"
UPDATE_ON_START="${UPDATE_ON_START:-true}"
GENERATE_SETTINGS="${GENERATE_SETTINGS:-true}"
PORT="${PORT:-7777}"
QUERYPORT="${QUERYPORT:-7778}"
MULTIHOME="${MULTIHOME:-0.0.0.0}"
INVITE_CODE="${INVITE_CODE:-}"
SERVER_NAME="${SERVER_NAME:-}"
SERVER_NOTE="${SERVER_NOTE:-}"
SERVER_PASSWORD="${SERVER_PASSWORD:-}"
MAX_PLAYERS="${MAX_PLAYERS:-4}"
P2P_PROXY_ADDRESS="${P2P_PROXY_ADDRESS:-127.0.0.1}"
FIRST_RUN_TIMEOUT="${FIRST_RUN_TIMEOUT:-120}"

SERVER_DESC="$SERVERDIR/R5/ServerDescription.json"
SERVER_PID=""
XVFB_PID=""

log() { echo "[windrose] $*"; }
quote() { printf '%q' "$1"; }

cleanup_xvfb() {
  if [ -n "$XVFB_PID" ] && kill -0 "$XVFB_PID" 2>/dev/null; then
    kill "$XVFB_PID" 2>/dev/null || true
  fi
}

shutdown_server() {
  log "Stopping Windrose dedicated server"
  pkill -TERM -f 'WindroseServer-Win64-Shipping.exe' 2>/dev/null || true
  pkill -TERM -f 'wineserver' 2>/dev/null || true
  for _ in $(seq 1 30); do
    if ! pgrep -f 'WindroseServer-Win64-Shipping.exe|wineserver' >/dev/null 2>&1; then
      break
    fi
    sleep 1
  done
  pkill -KILL -f 'WindroseServer-Win64-Shipping.exe|wineserver' 2>/dev/null || true
}

trap 'shutdown_server; exit 0' TERM INT
trap 'cleanup_xvfb' EXIT

init_dirs() {
  mkdir -p "$SERVERDIR" "$STEAM_HOME" "$WINEPREFIX"
  mkdir -p "$XDG_DATA_HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME"
  # SteamCMD writes its config/package cache to ~/Steam — point that into our writable volume
  mkdir -p "$STEAM_HOME/Steam"
  if [ ! -L "$STEAM_HOME/.steam" ]; then
    ln -sf "$STEAM_HOME/Steam" "$STEAM_HOME/.steam" 2>/dev/null || true
  fi
}

init_xvfb() {
  rm -f /tmp/.X99-lock || true
  Xvfb :99 -screen 0 1024x768x16 -nolisten tcp >/dev/null 2>&1 &
  XVFB_PID=$!
}

init_wine() {
  if [ ! -f "$WINEPREFIX/system.reg" ]; then
    log "Initializing Wine prefix at $WINEPREFIX"
    WINEPREFIX="$WINEPREFIX" wineboot -i >/dev/null 2>&1 || true
  fi
}

update_server() {
  if [ "$UPDATE_ON_START" != "true" ]; then
    log "UPDATE_ON_START=false, skipping SteamCMD update"
    return
  fi

  local login_cmd
  if [ "$STEAM_LOGIN" = "anonymous" ]; then
    login_cmd='+login anonymous'
  elif [ -n "$STEAM_PASS" ]; then
    login_cmd="+login $(quote "$STEAM_LOGIN") $(quote "$STEAM_PASS")"
  else
    login_cmd="+login $(quote "$STEAM_LOGIN")"
  fi

  log "Initialising SteamCMD (first-run bootstrapper pass)"
  /opt/steamcmd/steamcmd.sh +quit || true
  sleep 2

  log "Updating/validating server files via SteamCMD"
  local attempts=0
  local exit_code=0
  until [ "$attempts" -ge 3 ]; do
    attempts=$((attempts + 1))
    /opt/steamcmd/steamcmd.sh \
      +force_install_dir "$SERVERDIR" \
      $login_cmd \
      +app_update "$APPID" validate \
      +quit && exit_code=0 && break || exit_code=$?
    if [ "$exit_code" -eq 254 ]; then
      log "SteamCMD self-updated (exit 254), retrying (attempt $attempts/3)..."
      sleep 2
    else
      log "SteamCMD failed with exit code $exit_code"
      exit "$exit_code"
    fi
  done
}

find_server_exe() {
  find "$SERVERDIR" -iname 'WindroseServer-Win64-Shipping.exe' | head -n 1 || true
}

first_run_generate_config() {
  local exe="$1"
  if [ "$GENERATE_SETTINGS" != "true" ] || [ -f "$SERVER_DESC" ]; then
    return
  fi
  log "First run: starting server briefly to generate ServerDescription.json"
  WINEPREFIX="$WINEPREFIX" wine "$exe" \
    -log \
    -MULTIHOME="$MULTIHOME" \
    -PORT="$PORT" \
    -QUERYPORT="$QUERYPORT" \
    >/tmp/windrose-first-run.log 2>&1 &
  local warmup_pid=$!
  local count=0
  while [ ! -f "$SERVER_DESC" ] && [ "$count" -lt "$FIRST_RUN_TIMEOUT" ]; do
    sleep 1
    count=$((count + 1))
  done
  kill "$warmup_pid" 2>/dev/null || true
  wait "$warmup_pid" 2>/dev/null || true
  pkill -TERM -f 'wineserver' 2>/dev/null || true
  if [ ! -f "$SERVER_DESC" ]; then
    log "Warning: ServerDescription.json was not generated"
  fi
}

patch_server_config() {
  if [ "$GENERATE_SETTINGS" != "true" ]; then
    log "GENERATE_SETTINGS=false, skipping config patch"
    return
  fi
  if [ ! -f "$SERVER_DESC" ]; then
    log "ServerDescription.json not found, skipping patch"
    return
  fi
  log "Patching ServerDescription.json from environment variables"
  tr -d '\r' <"$SERVER_DESC" | jq \
    --arg invite "$INVITE_CODE" \
    --arg name "$SERVER_NAME" \
    --arg note "$SERVER_NOTE" \
    --arg password "$SERVER_PASSWORD" \
    --arg proxy "$P2P_PROXY_ADDRESS" \
    --argjson maxplayers "$MAX_PLAYERS" \
    '
        .ServerDescription_Persistent.P2pProxyAddress = $proxy |
        if $invite   != "" then .ServerDescription_Persistent.InviteCode  = $invite   else . end |
        if $name     != "" then .ServerDescription_Persistent.ServerName  = $name     else . end |
        if $note     != "" then .ServerDescription_Persistent.Note        = $note     else . end |
        if $password != "" then
            .ServerDescription_Persistent.IsPasswordProtected = true |
            .ServerDescription_Persistent.Password = $password
        else
            .ServerDescription_Persistent.IsPasswordProtected = false |
            .ServerDescription_Persistent.Password = ""
        end |
        .ServerDescription_Persistent.MaxPlayerCount = $maxplayers
        ' >"$SERVER_DESC.tmp"
  mv "$SERVER_DESC.tmp" "$SERVER_DESC"
}

start_server() {
  local exe="$1"
  log "Starting Windrose dedicated server"
  log "Executable : $exe"
  log "Port       : $PORT  QueryPort: $QUERYPORT  Multihome: $MULTIHOME"
  WINEPREFIX="$WINEPREFIX" wine "$exe" \
    -log \
    -MULTIHOME="$MULTIHOME" \
    -PORT="$PORT" \
    -QUERYPORT="$QUERYPORT" &
  SERVER_PID=$!
  wait "$SERVER_PID"
}

# ── Main ────────────────────────────────────────────────────────────────────
init_dirs
init_xvfb
init_wine
update_server

SERVER_EXE=$(find_server_exe)
if [ -z "$SERVER_EXE" ]; then
  log "ERROR: WindroseServer-Win64-Shipping.exe not found under $SERVERDIR"
  find "$SERVERDIR" -maxdepth 4 2>/dev/null || true
  exit 1
fi

first_run_generate_config "$SERVER_EXE"
patch_server_config
start_server "$SERVER_EXE"
