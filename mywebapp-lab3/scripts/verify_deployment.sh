#!/usr/bin/env bash
set -euo pipefail

TARGET_HOST="${TARGET_HOST:?TARGET_HOST is required}"

curl -f "http://$TARGET_HOST/"
curl -f "http://$TARGET_HOST/items"

echo "Deployment verification passed."