#!/usr/bin/env bash
set -euo pipefail

APP_DIR="/opt/mywebapp"

sudo mkdir -p "$APP_DIR"
sudo chown "$USER:$USER" "$APP_DIR"

sudo cp deploy/mywebapp-compose.service /etc/systemd/system/mywebapp.service

sudo systemctl daemon-reload
sudo systemctl enable mywebapp.service

echo "Target node prepared successfully."