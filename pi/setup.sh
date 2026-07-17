#!/usr/bin/env bash
# Idempotent setup for the Cellar Pi scan station service.
# Safe to re-run any time (e.g. after `git pull`) — it only installs what's
# missing and never overwrites an existing .env.
#
# Run ON THE PI, as a user with sudo (typically `pi`), from this directory:
#   cd ~/cellar-pi/pi && ./setup.sh
#
# Does NOT run on macOS — this installs apt packages and a systemd unit.
# See README.md for how to run the mock service on the Mac instead.

set -euo pipefail

if [[ "$(uname -s)" != "Linux" ]]; then
  echo "setup.sh targets Raspberry Pi OS (Linux)." >&2
  echo "On macOS, run the mock service instead — see README.md." >&2
  exit 1
fi

PI_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVICE_USER="${SUDO_USER:-$(whoami)}"
VENV_DIR="$PI_DIR/.venv"

echo "==> Cellar Pi setup — dir: $PI_DIR, user: $SERVICE_USER"

echo "==> Installing system dependencies (apt)"
sudo apt-get update
sudo apt-get install -y \
  python3-venv \
  python3-pip \
  python3-picamera2 \
  python3-libcamera \
  libcap-dev

echo "==> Creating venv (with --system-site-packages so it can see apt's picamera2)"
if [[ ! -d "$VENV_DIR" ]]; then
  python3 -m venv --system-site-packages "$VENV_DIR"
else
  echo "    $VENV_DIR already exists, reusing it."
fi

echo "==> Installing Python dependencies"
"$VENV_DIR/bin/pip" install --upgrade pip
"$VENV_DIR/bin/pip" install -r "$PI_DIR/requirements.txt"

echo "==> Ensuring .env exists"
if [[ ! -f "$PI_DIR/.env" ]]; then
  cp "$PI_DIR/.env.example" "$PI_DIR/.env"
  echo "    Created $PI_DIR/.env from .env.example — fill in GEMINI_API_KEY before starting the service."
else
  echo "    $PI_DIR/.env already exists, leaving it untouched."
fi

echo "==> Installing systemd unit"
SERVICE_SRC="$PI_DIR/systemd/cellar-pi.service"
SERVICE_DST="/etc/systemd/system/cellar-pi.service"
# The checked-in unit file documents a default path (/home/pi/cellar-pi/pi);
# rewrite it to wherever this checkout actually lives so the service works
# regardless of clone location or username.
sudo sed \
  -e "s#/home/pi/cellar-pi/pi/.venv/bin/python#$VENV_DIR/bin/python#" \
  -e "s#/home/pi/cellar-pi/pi#$PI_DIR#g" \
  -e "s/^User=pi/User=$SERVICE_USER/" \
  "$SERVICE_SRC" | sudo tee "$SERVICE_DST" > /dev/null

sudo systemctl daemon-reload
sudo systemctl enable cellar-pi.service

echo "==> Setup complete."
echo "    1. Edit $PI_DIR/.env — set GEMINI_API_KEY and confirm GPIO pins."
echo "    2. sudo systemctl start cellar-pi"
echo "    3. sudo systemctl status cellar-pi"
echo "    4. journalctl -u cellar-pi -f"
