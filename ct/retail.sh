#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/avtoradio48/ProxmoxVE/main/misc/build.func)

APP="retail"
var_tags="${var_tags:-database;java;web;tools}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-16}"
var_db_disk="${var_db_disk:-16}"
var_db_mount="${var_db_mount:-/db}"
var_os="${var_os:-ubuntu}"
var_version="${var_version:-24.04}"
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

choose_db_volume() {
  header_info
  msg_info "Configure PostgreSQL data volume"

  echo "Available storages:"
  pvesm status
  echo

  read -r -p "Enter storage name for PostgreSQL volume: " var_db_storage
  if [[ -z "${var_db_storage}" ]]; then
    msg_error "Storage name cannot be empty"
    exit 1
  fi

  if ! pvesm status | awk 'NR>1 {print $1}' | grep -qx "${var_db_storage}"; then
    msg_error "Storage '${var_db_storage}' not found"
    exit 1
  fi

  read -r -p "Enter PostgreSQL volume size in GB [${var_db_disk}]: " input_db_disk
  if [[ -n "${input_db_disk}" ]]; then
    var_db_disk="${input_db_disk}"
  fi

  if ! [[ "${var_db_disk}" =~ ^[0-9]+$ ]]; then
    msg_error "PostgreSQL volume size must be an integer number of GB"
    exit 1
  fi

  msg_ok "PostgreSQL volume: ${var_db_storage}:${var_db_disk}G -> ${var_db_mount}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if ! command -v psql >/dev/null 2>&1; then
    msg_error "No ${APP} installation found!"
    exit 1
  fi

  msg_info "Updating ${APP} LXC"
  $STD apt-get update
  $STD apt-get -y dist-upgrade
  msg_ok "Updated successfully!"
  exit
}

start
choose_db_volume
build_container
description

msg_ok "Completed successfully!"
echo -e "${INFO}${YW}Container ID:${CL} ${CTID}"
echo -e "${INFO}${YW}Container IP:${CL} ${IP}"
echo -e "${INFO}${YW}PostgreSQL:${CL} ${IP}:5432"
echo -e "${INFO}${YW}Nginx:${CL} http://${IP}/"
echo -e "${INFO}${YW}DB volume:${CL} ${var_db_storage}:${var_db_disk}G mounted at ${var_db_mount}"
