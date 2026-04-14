#!/usr/bin/env bash
set -euo pipefail

APPID=${WINDROSE_APP_ID:-4129620}
SERVERDIR=/data
WINEPREFIX=/home/steam/.wine
STEAM_LOGIN=${STEAM_LOGIN:-anonymous}
STEAM_PASS=${STEAM_PASS:-}

PORT=${PORT:-7777}
QUERYPORT=${QUERYPORT:-7778}

rm -f /tmp/.X99-lock || true
Xvfb :99 -screen 0 1024x768x16 -nolisten tcp >/dev/null 2>&1 &
XVFB_PID=$!
trap 'kill ${XVFB_PID} 2>/dev/null || true' EXIT

# Init Wine
if [ ! -d "$WINEPREFIX" ]; then
  wineboot -i || true
fi

# Aktualizacja serwera
cmd=(/opt/steamcmd/steamcmd.sh +force_install_dir "$SERVERDIR")
if [ "$STEAM_LOGIN" = "anonymous" ]; then
  cmd+=(+login anonymous)
elif [ -n "$STEAM_PASS" ]; then
  cmd+=(+login "$STEAM_LOGIN" "$STEAM_PASS")
else
  cmd+=(+login "$STEAM_LOGIN")
fi
cmd+=(+app_update "$APPID" validate +quit)
"${cmd[@]}"

# Znajdź exe
SERVER_EXE=$(find "$SERVERDIR" -iname "WindroseServer-Win64-Shipping.exe" | head -n 1 || true)

if [ -z "$SERVER_EXE" ]; then
  echo "ERROR: Windrose server executable not found"
  find "$SERVERDIR" -maxdepth 4
  exit 1
fi

echo "Starting Windrose dedicated server"
echo "Executable: $SERVER_EXE"

exec wine "$SERVER_EXE" \
  -log \
  -MULTIHOME=0.0.0.0 \
  -PORT=$PORT \
  -QUERYPORT=$QUERYPORT
