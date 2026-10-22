#!/usr/bin/env bash
# =============================================================================
# start.sh - start (or restart) the desktop and print its public URL
#
#   bash /kaggle/working/KaggleDesk/start.sh
#
# Idempotent: starts only the parts that are not already running.
# Environment overrides:
#   GEOMETRY=1600x900   screen size
#   WEB_PORT=6080       local noVNC port
#   VNC_PORT=5901       local VNC port
# =============================================================================
set -euo pipefail

DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
export HOME=${HOME:-/root}
GEOMETRY=${GEOMETRY:-1600x900}
DISPLAY_NUM=${DISPLAY_NUM:-:1}
VNC_PORT=${VNC_PORT:-5901}
WEB_PORT=${WEB_PORT:-6080}

mkdir -p "$DIR" /root/.vnc
cd "$DIR"

port_up() { ss -ltn 2>/dev/null | awk '{print $4}' | grep -q ":$1$"; }

# ---------------------------------------------------------------- password ---
if [ ! -s "$DIR/vnc_password.txt" ]; then
  python3 -c "import secrets,string;print(''.join(secrets.choice(string.ascii_letters+string.digits) for _ in range(10)))" \
    > "$DIR/vnc_password.txt"
fi
PW=$(cat "$DIR/vnc_password.txt")
python3 "$DIR/vncpw.py" "$PW" /root/.vnc/passwd
chmod 600 /root/.vnc/passwd

# ------------------------------------------------------------- X session -----
if [ ! -x /root/.vnc/xstartup ]; then
  cat > /root/.vnc/xstartup <<'EOS'
#!/bin/sh
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS
export XDG_SESSION_TYPE=x11 XDG_CURRENT_DESKTOP=XFCE
exec dbus-launch --exit-with-session startxfce4
EOS
  chmod +x /root/.vnc/xstartup
fi

if port_up "$VNC_PORT"; then
  echo "==> X/VNC already listening on $VNC_PORT"
else
  echo "==> starting Xtigervnc on $DISPLAY_NUM ($GEOMETRY)"
  vncserver "$DISPLAY_NUM" -geometry "$GEOMETRY" -depth 24 -localhost yes \
    -SecurityTypes VncAuth -PasswordFile /root/.vnc/passwd \
    -BlacklistThreshold 10000 -xstartup /root/.vnc/xstartup > vnc.log 2>&1
  for _ in $(seq 1 15); do sleep 1; port_up "$VNC_PORT" && break; done
  port_up "$VNC_PORT" || { echo "VNC failed to start, see $DIR/vnc.log" >&2; tail -20 vnc.log >&2; exit 1; }
fi

# --------------------------------------------------------------- websockify --
if port_up "$WEB_PORT"; then
  echo "==> noVNC already listening on $WEB_PORT"
else
  WS_BIN=$(command -v /usr/local/bin/websockify || command -v websockify)
  echo "==> starting websockify on 127.0.0.1:$WEB_PORT"
  setsid nohup "$WS_BIN" --web /usr/share/novnc \
    "127.0.0.1:$WEB_PORT" "127.0.0.1:$VNC_PORT" > websockify.log 2>&1 < /dev/null &
  echo $! > websockify.pid
  for _ in $(seq 1 15); do sleep 1; port_up "$WEB_PORT" && break; done
  port_up "$WEB_PORT" || { echo "websockify failed, see $DIR/websockify.log" >&2; tail -20 websockify.log >&2; exit 1; }
fi

# ------------------------------------------------------------ cloudflared ----
URL=""
if [ -s cf.pid ] && kill -0 "$(cat cf.pid)" 2>/dev/null; then
  URL=$(grep -oE 'https://[a-z0-9-]+\.trycloudflare\.com' cf.log 2>/dev/null | tail -1 || true)
fi

if [ -z "$URL" ]; then
  # the notebook already runs one cloudflared on the default metrics port
  METRICS_PORT=$(python3 -c 'import socket;s=socket.socket();s.bind(("127.0.0.1",0));p=s.getsockname()[1];s.close();print(p)')
  echo "==> opening Cloudflare quick tunnel"
  : > cf.log
  setsid nohup cloudflared tunnel --no-autoupdate --protocol http2 \
    --metrics "127.0.0.1:$METRICS_PORT" --url "http://127.0.0.1:$WEB_PORT" \
    > cf.log 2>&1 < /dev/null &
  echo $! > cf.pid

  for _ in $(seq 1 40); do
    sleep 2
    URL=$(grep -oE 'https://[a-z0-9-]+\.trycloudflare\.com' cf.log | tail -1 || true)
    [ -n "$URL" ] && break
  done
  if [ -z "$URL" ]; then
    echo "tunnel did not come up, see $DIR/cf.log" >&2
    tail -20 cf.log >&2
    exit 1
  fi
fi

echo "$URL" > url.txt

cat <<EOF

  Desktop    : $URL/vnc.html
  One-click  : $URL/vnc.html?autoconnect=1&resize=scale&path=websockify&password=$PW
  Password   : $PW
  Local      : http://127.0.0.1:$WEB_PORT/vnc.html
  Logs       : $DIR/{vnc,websockify,cf}.log
  Stop       : bash $DIR/stop.sh

EOF
