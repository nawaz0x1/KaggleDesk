#!/usr/bin/env bash
# =============================================================================
# setup.sh - one-shot bootstrap for a browser-accessible Linux desktop
#
# Installs the Xfce/noVNC/Xvnc stack into the current (Kaggle) container,
# configures it, starts it, and prints the public Cloudflare URL.
#
#   bash /kaggle/working/KaggleDesk/setup.sh
#
# Safe to re-run: package installs and processes are skipped when already
# present. Re-run start.sh for a routine restart instead.
# =============================================================================
set -euo pipefail

DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
export DEBIAN_FRONTEND=noninteractive

if [ "$(id -u)" -ne 0 ]; then
  echo "setup.sh must run as root (use sudo bash $0)" >&2
  exit 1
fi

need_pkgs=()
check() { dpkg -s "$1" >/dev/null 2>&1 || need_pkgs+=("$1"); }

for p in xfce4 xfce4-terminal dbus-x11 tigervnc-standalone-server \
         tigervnc-common novnc websockify xterm x11-utils scrot; do
  check "$p"
done

if [ ${#need_pkgs[@]} -gt 0 ]; then
  echo "==> installing: ${need_pkgs[*]}"
  apt-get update -qq
  apt-get install -y --no-install-recommends "${need_pkgs[@]}" > "$DIR/apt.log" 2>&1 \
    || { echo "apt failed, see $DIR/apt.log" >&2; tail -20 "$DIR/apt.log" >&2; exit 1; }
else
  echo "==> desktop packages already installed"
fi

# The distro websockify works, but 0.13+ is what this setup was verified with.
if ! python3 - <<'PY' >/dev/null 2>&1
import importlib.metadata as m
raise SystemExit(0 if tuple(int(x) for x in m.version("websockify").split(".")[:2]) >= (0, 13) else 1)
PY
then
  echo "==> installing websockify >= 0.13 (pip)"
  python3 -m pip install -q --upgrade "websockify>=0.13" || true
fi

# Needed on hosts where cloudflared is not preinstalled (Kaggle ships it).
if ! command -v cloudflared >/dev/null 2>&1; then
  case "$(uname -m)" in
    x86_64|amd64) cf_arch=amd64 ;;
    aarch64|arm64) cf_arch=arm64 ;;
    *) echo "unsupported arch $(uname -m) for cloudflared" >&2; exit 1 ;;
  esac
  echo "==> installing cloudflared ($cf_arch)"
  curl -fsSL -o /usr/local/bin/cloudflared \
    "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-$cf_arch"
  chmod +x /usr/local/bin/cloudflared
fi

echo "==> configuring"
bash "$DIR/start.sh"
