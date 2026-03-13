#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/build.func)

APP="retail"
var_tags="${var_tags:-database;java;web;tools}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-16}"
var_os="${var_os:-ubuntu}"
var_version="${var_version:-24.04}"
var_unprivileged="${var_unprivileged:-1}"

DB_MOUNT_HOST_PATH=""
DB_MOUNT_SIZE=""
DB_MOUNT_MODE=""

header_info "$APP"
variables
color
catch_errors

choose_db_mountpoint() {
  header_info
  msg_info "Configure PostgreSQL data mountpoint"

  echo "Choose mountpoint mode:"
  echo "  1) Bind mount existing host directory"
  echo "  2) Allocate volume from Proxmox storage"
  echo "  3) Skip extra mountpoint"
  echo

  read -r -p "Select [1-3]: " DB_MOUNT_MODE

  case "$DB_MOUNT_MODE" in
    1)
      echo
      echo "Examples:"
      echo "  /mnt/ssdpg/customstack-${CTID}"
      echo "  /srv/lxc-db/customstack-${CTID}"
      read -r -p "Enter host directory for /db: " DB_MOUNT_HOST_PATH

      if [[ -z "$DB_MOUNT_HOST_PATH" ]]; then
        msg_error "Host directory cannot be empty"
        exit 1
      fi

      mkdir -p "$DB_MOUNT_HOST_PATH"
      msg_ok "Host directory prepared: $DB_MOUNT_HOST_PATH"
      ;;
    2)
      echo
      pvesm status
      echo
      read -r -p "Enter storage name for extra volume: " DB_MOUNT_HOST_PATH
      read -r -p "Enter size in GB for /db volume [20]: " DB_MOUNT_SIZE
      DB_MOUNT_SIZE="${DB_MOUNT_SIZE:-20}"

      if [[ -z "$DB_MOUNT_HOST_PATH" ]]; then
        msg_error "Storage name cannot be empty"
        exit 1
      fi

      if ! [[ "$DB_MOUNT_SIZE" =~ ^[0-9]+$ ]]; then
        msg_error "Size must be an integer number of GB"
        exit 1
      fi
      ;;
    3)
      msg_warn "Extra mountpoint skipped. PostgreSQL will fail later if /db is required by install script."
      ;;
    *)
      msg_error "Invalid selection"
      exit 1
      ;;
  esac
}

attach_db_mountpoint() {
  case "$DB_MOUNT_MODE" in
    1)
      msg_info "Attaching bind mount as /db"
      pct set "$CTID" -mp0 "$DB_MOUNT_HOST_PATH,mp=/db"
      msg_ok "Bind mount attached: $DB_MOUNT_HOST_PATH -> /db"
      ;;
    2)
      msg_info "Attaching storage-backed mount as /db"
      pct set "$CTID" -mp0 "$DB_MOUNT_HOST_PATH:${DB_MOUNT_SIZE},mp=/db"
      msg_ok "Storage-backed volume attached: $DB_MOUNT_HOST_PATH:${DB_MOUNT_SIZE}G -> /db"
      ;;
    3)
      ;;
  esac
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
choose_db_mountpoint
build_container
attach_db_mountpoint
description

msg_ok "Completed successfully!"
echo -e "${INFO}${YW}Container ID:${CL} ${CTID}"
echo -e "${INFO}${YW}Container IP:${CL} ${IP}"
echo -e "${INFO}${YW}PostgreSQL:${CL} ${IP}:5432"
echo -e "${INFO}${YW}Nginx:${CL} http://${IP}/"
echo -e "${INFO}${YW}DB mountpoint:${CL} /db"
