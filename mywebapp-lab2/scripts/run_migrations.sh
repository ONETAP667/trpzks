#!/usr/bin/env bash
set -euo pipefail

CONFIG_PATH="${CONFIG_PATH:-/etc/mywebapp/config.yaml}"
MIGRATION_PATH="${MIGRATION_PATH:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/db/migrate.sql}"

if [[ ! -f "$CONFIG_PATH" ]]; then
  echo "Config file not found: $CONFIG_PATH" >&2
  exit 1
fi

if [[ ! -f "$MIGRATION_PATH" ]]; then
  echo "Migration file not found: $MIGRATION_PATH" >&2
  exit 1
fi

if ! command -v psql >/dev/null 2>&1; then
  echo "psql is not installed" >&2
  exit 1
fi

readarray -t DB_INFO < <(python3 - <<'PY' "$CONFIG_PATH"
import sys
import yaml

config_path = sys.argv[1]

with open(config_path, "r", encoding="utf-8") as f:
    data = yaml.safe_load(f)

if not data or "database" not in data:
    raise SystemExit("Missing 'database' section in config")

db = data["database"]
required = ["dbname", "user", "password", "host", "port"]
for key in required:
    if key not in db:
        raise SystemExit(f"Missing database config field: {key}")

print(db["dbname"])
print(db["user"])
print(db["password"])
print(db["host"])
print(db["port"])
PY
)

DB_NAME="${DB_INFO[0]}"
DB_USER="${DB_INFO[1]}"
DB_PASSWORD="${DB_INFO[2]}"
DB_HOST="${DB_INFO[3]}"
DB_PORT="${DB_INFO[4]}"

export PGPASSWORD="$DB_PASSWORD"

psql \
  --host="$DB_HOST" \
  --port="$DB_PORT" \
  --username="$DB_USER" \
  --dbname="$DB_NAME" \
  --set=ON_ERROR_STOP=1 \
  --file="$MIGRATION_PATH"

echo "Migrations applied successfully"
