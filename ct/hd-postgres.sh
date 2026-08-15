#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/build.func)
# Copyright (c) 2021-2026 community-scripts ORG
# Author: Codex
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: User custom requirements

APP="HD Postgres Stack"
var_tags="${var_tags:-postgres;ubuntu}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-12}"
var_db_disk="${var_db_disk:-20}"
var_os="${var_os:-ubuntu}"
var_version="${var_version:-24.04}"
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -f /etc/postgresql/15/main/postgresql.conf ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  msg_info "Updating ${APP} LXC"
  $STD apt update
  $STD apt upgrade -y
  msg_ok "Updated successfully!"
  exit
}

start
build_container
description

msg_info "Adding second disk for PostgreSQL data"
STORAGE_TARGET="$(pct config "$CTID" | awk -F '[:,]' '/^rootfs:/{gsub(/^[ \t]+|[ \t]+$/, "", $2); print $2; exit}')"
if [[ -z "$STORAGE_TARGET" ]]; then
  msg_error "Unable to detect container storage target"
  exit 1
fi

if pct config "$CTID" | grep -q '^mp0:'; then
  msg_ok "Second disk already configured (mp0 exists)"
else
  pct set "$CTID" -mp0 "${STORAGE_TARGET}:${var_db_disk},mp=/mnt/postgres-data" >/dev/null
  msg_ok "Second disk attached: ${var_db_disk}G mounted at /mnt/postgres-data"
fi

msg_info "Configuring PostgreSQL to use second disk"
pct exec "$CTID" -- bash -lc '
set -e
systemctl stop postgresql
mkdir -p /mnt/postgres-data/15/main
chown -R postgres:postgres /mnt/postgres-data
if [[ ! -s /mnt/postgres-data/15/main/PG_VERSION ]]; then
  rsync -a /var/lib/postgresql/15/main/ /mnt/postgres-data/15/main/
fi
chown -R postgres:postgres /mnt/postgres-data/15/main

sed -i "s|^#\?listen_addresses\s*=.*|listen_addresses = '\''*'\''|" /etc/postgresql/15/main/postgresql.conf
if grep -q "^data_directory" /etc/postgresql/15/main/postgresql.conf; then
  sed -i "s|^data_directory\s*=.*|data_directory = '\''/mnt/postgres-data/15/main'\''|" /etc/postgresql/15/main/postgresql.conf
else
  echo "data_directory = '\''/mnt/postgres-data/15/main'\''" >> /etc/postgresql/15/main/postgresql.conf
fi

cat >/etc/postgresql/15/main/pg_hba.conf <<HBA
local all all md5
host all all 127.0.0.1/32 md5
host all all ::1/128 md5
host all all 0.0.0.0/0 md5
HBA

systemctl start postgresql
sudo -u postgres psql -c "ALTER USER postgres WITH PASSWORD '\''DefSR10@_db210423'\'';"
'
msg_ok "PostgreSQL moved to second disk and reconfigured"

msg_ok "Completed successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW}Second disk for PostgreSQL:${CL} ${TAB}${BGN}/mnt/postgres-data${CL}"
echo -e "${INFO}${YW}System user:${CL} ${TAB}${BGN}hd${CL}"
