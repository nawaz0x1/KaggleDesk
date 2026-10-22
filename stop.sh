#!/usr/bin/env bash
# =============================================================================
# stop.sh - stop the tunnel, noVNC bridge and the X/VNC server
#
#   bash /kaggle/working/KaggleDesk/stop.sh
#
# Desktop files in this folder are left untouched; run start.sh to come back.
# =============================================================================
set -u
DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
export HOME=${HOME:-/root}

echo "==> stopping cloudflared"
if [ -s "$DIR/cf.pid" ] && kill -0 "$(cat "$DIR/cf.pid")" 2>/dev/null; then
  kill "$(cat "$DIR/cf.pid")" 2>/dev/null
  sleep 1
fi
rm -f "$DIR/cf.pid"
# fallback for tunnels started before pid files existed (never the notebook's own)
pkill -f "[c]loudflared tunnel.*--url http://127.0.0.1:${WEB_PORT:-6080}" 2>/dev/null || true

echo "==> stopping websockify"
if [ -s "$DIR/websockify.pid" ] && kill -0 "$(cat "$DIR/websockify.pid")" 2>/dev/null; then
  kill "$(cat "$DIR/websockify.pid")" 2>/dev/null
  sleep 1
fi
rm -f "$DIR/websockify.pid"

# fallback for processes started before pid files existed
pkill -f "[w]ebsockify --web /usr/share/novnc" 2>/dev/null || true

echo "==> stopping X/VNC on :${DISPLAY_NUM:-1}"
vncserver -kill "${DISPLAY_NUM:-:1}" >/dev/null 2>&1 || true
rm -f /tmp/.X1-lock /tmp/.X11-unix/X1 2>/dev/null || true

echo "stopped."
