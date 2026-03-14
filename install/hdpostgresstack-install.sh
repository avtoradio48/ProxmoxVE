#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Codex
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: User custom requirements

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Generating all locales and setting ru_RU.UTF-8"
sed -i -E '/^# [a-z]{2}_[A-Z]{2}(\.[A-Za-z0-9_-]+)?( [A-Za-z0-9@_-]+)?$/ s/^# //' /etc/locale.gen
locale-gen
update-locale LANG=ru_RU.UTF-8 LC_ALL=ru_RU.UTF-8
msg_ok "Locales generated and ru_RU.UTF-8 configured"

msg_info "Installing base dependencies"
$STD apt install -y sudo curl gnupg ca-certificates lsb-release wget rsync software-properties-common
msg_ok "Installed base dependencies"

msg_info "Installing PostgreSQL 15 repository"
install -d -m 0755 /etc/apt/keyrings
curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor -o /etc/apt/keyrings/postgresql.gpg
chmod a+r /etc/apt/keyrings/postgresql.gpg
echo "deb [signed-by=/etc/apt/keyrings/postgresql.gpg] http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" >/etc/apt/sources.list.d/pgdg.list
$STD apt update
msg_ok "PostgreSQL repository ready"

msg_info "Installing requested software"
$STD apt install -y \
  postgresql-15 \
  postgresql-client-15 \
  btop \
  mc \
  ntp \
  ntpdate \
  samba \
  nginx
msg_ok "Requested software installed"

msg_info "Installing Oracle JDK 21"
wget -qO /tmp/jdk-21_linux-x64_bin.deb https://download.oracle.com/java/21/latest/jdk-21_linux-x64_bin.deb
$STD apt install -y /tmp/jdk-21_linux-x64_bin.deb
rm -f /tmp/jdk-21_linux-x64_bin.deb
msg_ok "Installed Oracle JDK 21"

msg_info "Creating admin user hd"
if ! id -u hd >/dev/null 2>&1; then
  useradd -m -s /bin/bash hd
fi
echo 'hd:DefSR10@_r00t210423' | chpasswd
usermod -aG sudo hd
msg_ok "User hd configured with sudo rights"

motd_ssh
customize
cleanup_lxc
