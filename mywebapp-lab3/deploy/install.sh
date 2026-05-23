#!/usr/bin/env bash
set -euo pipefail

APP_NAME="mywebapp"
APP_USER="mywebapp"
APP_GROUP="mywebapp"
APP_DIR="/opt/mywebapp"
CONFIG_DIR="/etc/mywebapp"
CONFIG_FILE="$CONFIG_DIR/config.yaml"

DB_NAME="mywebapp"
DB_USER="mywebapp"
DB_PASSWORD="mywebapp_password"

GRADEBOOK_VALUE="5"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

DEFAULT_USER_TO_LOCK="${DEFAULT_USER_TO_LOCK:-ubuntu}"

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    echo "Run this script as root" >&2
    exit 1
  fi
}

install_packages() {
  export DEBIAN_FRONTEND=noninteractive

  apt update
  apt install -y \
    python3 \
    python3-pip \
    python3-venv \
    postgresql \
    postgresql-client \
    nginx \
    sudo \
    curl
}

create_system_users() {
  if ! id -u student >/dev/null 2>&1; then
    useradd -m -s /bin/bash student
  fi

  if ! id -u teacher >/dev/null 2>&1; then
    useradd -m -s /bin/bash teacher
  fi

  if ! id -u operator >/dev/null 2>&1; then
    useradd -m -s /bin/bash operator
  fi

  echo 'student:12345678' | chpasswd
  echo 'teacher:12345678' | chpasswd
  echo 'operator:12345678' | chpasswd

  chage -d 0 student
  chage -d 0 teacher
  chage -d 0 operator

  usermod -aG sudo student
  usermod -aG sudo teacher

  if ! getent group "$APP_GROUP" >/dev/null 2>&1; then
    groupadd --system "$APP_GROUP"
  fi

  if ! id -u "$APP_USER" >/dev/null 2>&1; then
    useradd --system --gid "$APP_GROUP" --home "$APP_DIR" --shell /usr/sbin/nologin "$APP_USER"
  fi
}

prepare_directories() {
  mkdir -p "$APP_DIR"
  mkdir -p "$CONFIG_DIR"
}

copy_project_files() {
  rm -rf "$APP_DIR/app" "$APP_DIR/db" "$APP_DIR/scripts"

  cp -r "$PROJECT_ROOT/app" "$APP_DIR/"
  cp -r "$PROJECT_ROOT/db" "$APP_DIR/"
  cp -r "$PROJECT_ROOT/scripts" "$APP_DIR/"

  chown -R "$APP_USER:$APP_GROUP" "$APP_DIR"
  find "$APP_DIR" -type d -exec chmod 755 {} \;
  chmod +x "$APP_DIR/scripts/run_migrations.sh"
}

create_config() {
  cat > "$CONFIG_FILE" <<EOF
database:
  dbname: $DB_NAME
  user: $DB_USER
  password: $DB_PASSWORD
  host: 127.0.0.1
  port: 5432
EOF

  chown root:"$APP_GROUP" "$CONFIG_FILE"
  chmod 640 "$CONFIG_FILE"
}

setup_python_env() {
  rm -rf "$APP_DIR/.venv"

  python3 -m venv "$APP_DIR/.venv"
  "$APP_DIR/.venv/bin/pip" install --upgrade pip
  "$APP_DIR/.venv/bin/pip" install fastapi uvicorn psycopg2-binary pyyaml

  chown -R "$APP_USER:$APP_GROUP" "$APP_DIR/.venv"
}

setup_database() {
  sudo -u postgres psql -f "$APP_DIR/db/bootstrap.sql"
  sudo -u "$APP_USER" "$APP_DIR/scripts/run_migrations.sh"
}

install_systemd_units() {
  cp "$PROJECT_ROOT/deploy/mywebapp.service" /etc/systemd/system/mywebapp.service
  cp "$PROJECT_ROOT/deploy/mywebapp.socket" /etc/systemd/system/mywebapp.socket

  chmod 644 /etc/systemd/system/mywebapp.service
  chmod 644 /etc/systemd/system/mywebapp.socket

  systemctl daemon-reload
  systemctl enable mywebapp.socket
  systemctl restart mywebapp.socket
}

install_nginx() {
  cp "$PROJECT_ROOT/deploy/nginx_mywebapp.conf" /etc/nginx/sites-available/mywebapp
  ln -sf /etc/nginx/sites-available/mywebapp /etc/nginx/sites-enabled/mywebapp
  rm -f /etc/nginx/sites-enabled/default

  nginx -t
  systemctl enable nginx
  systemctl restart nginx
}

install_operator_sudoers() {
  cp "$PROJECT_ROOT/deploy/sudoers_operator" /etc/sudoers.d/operator-mywebapp
  chmod 440 /etc/sudoers.d/operator-mywebapp
  visudo -cf /etc/sudoers.d/operator-mywebapp
}

create_gradebook() {
  echo "$GRADEBOOK_VALUE" > /home/student/gradebook
  chown student:student /home/student/gradebook
  chmod 644 /home/student/gradebook
}

lock_default_user() {
  if id -u "$DEFAULT_USER_TO_LOCK" >/dev/null 2>&1; then
    usermod -L "$DEFAULT_USER_TO_LOCK" || true
  fi
}

smoke_test() {
  curl --fail http://127.0.0.1/ >/dev/null
  curl --fail http://127.0.0.1/items >/dev/null
}

main() {
  require_root
  install_packages
  create_system_users
  prepare_directories
  copy_project_files
  create_config
  setup_python_env
  setup_database
  install_systemd_units
  install_nginx
  install_operator_sudoers
  create_gradebook
  lock_default_user
  smoke_test

  echo "Installation completed successfully"
}

main "$@"