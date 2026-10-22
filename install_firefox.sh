#!/usr/bin/env bash

set -euo pipefail

DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
export DEBIAN_FRONTEND=noninteractive

if [ "$(id -u)" -ne 0 ]; then
  echo "install_firefox.sh must run as root (use sudo bash $0)" >&2
  exit 1
fi

KEYRING=/etc/apt/keyrings/packages.mozilla.org.asc
LIST=/etc/apt/sources.list.d/mozilla.list
PREF=/etc/apt/preferences.d/mozilla

if [ ! -s "$KEYRING" ]; then
  echo "==> adding Mozilla APT signing key"
  install -d -m 0755 /etc/apt/keyrings
  curl -fsSL https://packages.mozilla.org/apt/repo-signing-key.gpg -o "$KEYRING"
fi

if [ ! -s "$LIST" ]; then
  echo "==> adding Mozilla APT repository"
  echo "deb [signed-by=$KEYRING] https://packages.mozilla.org/apt mozilla main" > "$LIST"
fi

if [ ! -s "$PREF" ]; then
  echo "==> pinning packages.mozilla.org (priority 1000)"
  printf 'Package: *\nPin: origin packages.mozilla.org\nPin-Priority: 1000\n' > "$PREF"
fi

echo "==> updating package lists"
apt-get update -qq > "$DIR/apt.log" 2>&1 \
  || { echo "apt-get update failed, see $DIR/apt.log" >&2; tail -20 "$DIR/apt.log" >&2; exit 1; }

echo "==> installing firefox"
apt-get install -y -qq firefox >> "$DIR/apt.log" 2>&1 \
  || { echo "apt-get install failed, see $DIR/apt.log" >&2; tail -20 "$DIR/apt.log" >&2; exit 1; }

echo "==> installed: $(firefox --version 2>/dev/null || echo unknown)"


smoke_profile=$(mktemp -d)
if timeout 60 firefox --headless --profile "$smoke_profile" \
     --screenshot /tmp/ff-smoke.png about:blank >/dev/null 2>&1 \
     && [ -s /tmp/ff-smoke.png ]; then
  echo "==> headless check OK"
else
  echo "==> warning: headless smoke test failed (GUI may still work)" >&2
fi
rm -rf "$smoke_profile" /tmp/ff-smoke.png
