#!/usr/bin/env bash
set -euo pipefail

TARGET_HOST="${TARGET_HOST:?TARGET_HOST is required}"
TARGET_USER="${TARGET_USER:?TARGET_USER is required}"
IMAGE_TAG="${IMAGE_TAG:?IMAGE_TAG is required}"
IMAGE_NAME="${IMAGE_NAME:?IMAGE_NAME is required}"

APP_DIR="/opt/mywebapp"

ssh "$TARGET_USER@$TARGET_HOST" "mkdir -p $APP_DIR"

scp docker-compose.yml "$TARGET_USER@$TARGET_HOST:$APP_DIR/docker-compose.yml"
scp -r config deploy db scripts "$TARGET_USER@$TARGET_HOST:$APP_DIR/"

ssh "$TARGET_USER@$TARGET_HOST" "
  cd $APP_DIR
  export IMAGE_NAME='$IMAGE_NAME'
  export IMAGE_TAG='$IMAGE_TAG'
  docker pull '$IMAGE_NAME:$IMAGE_TAG'
  sudo systemctl daemon-reload
  sudo systemctl restart mywebapp.service
  sudo systemctl status mywebapp.service --no-pager
"