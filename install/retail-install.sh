#!/usr/bin/env bash
source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"

export DEBIAN_FRONTEND=noninteractive

POSTGRES_VERSION="15"
POSTGRES_SUPER_PASS='DefSR10@_db210423'
HD_PASS='DefSR10@_r00t210423'
ORACLE_JDK_URL='https://download.oracle.com/java/21/latest/jdk-21_linux-x64_bin.deb'
ORACLE_JDK_DEB='/tmp/jdk-21_linux-x64_bin.deb'
PGDATA_DIR="/db/postgresql/15/main"

color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

install_base_packages() {
  msg_info "Installing base packages"
  apt-get install -y \
    ca-certificates \
    curl \
    wget \
    gnupg \
    gpg \
    lsb-release \
    software-properties-common \
    apt-transport-https \
    locales \
    sudo \
    tar \
    gzip \
    xz-utils \
    unzip \
    bash-completion \
    btop \
    mc \
    nginx \
    samba \
    ntpsec \
    ntpdate
  msg_ok "Base packages installed"
}

configure_all_locales_then_ru() {
  msg_info "Generating all available locales"

  cp /etc/locale.gen /etc/locale.gen.bak

  awk '
    /^[[:space:]]*#/ {
      line=$0
      sub(/^[[:space:]]*#[[:space:]]*/, "", line)
      if (line ~ /^[A-Za-z0-9_.@-]+[[:space:]]+[A-Za-z0-9_-]+$/) print line
      next
    }
    /^[[:space:]]*[A-Za-z0-9_.@-]+[[:space:]]+[A-Za-z0-9_-]+$/ { print; next }
  ' /etc/locale.gen.bak | sort -u > /etc/locale.gen

  locale-gen
  update-locale LANG=ru_RU.UTF-8 LC_ALL=ru_RU.UTF-8
  printf 'LANG=ru_RU.UTF-8\nLC_ALL=ru_RU.UTF-8\n' > /etc/default/locale

  msg_ok "All locales generated and ru_RU.UTF-8 set as system locale"
}

install_oracle_jdk() {
  msg_info "Installing Oracle JDK from .deb"
  curl -fsSL -o "${ORACLE_JDK_DEB}" "${ORACLE_JDK_URL}"
  apt-get install -y "${ORACLE_JDK_DEB}"
  java -version
  javac -version
  msg_ok "Oracle JDK installed"
}

check_db_mount() {
  msg_info "Checking /db mountpoint"

  if [[ ! -d /db ]]; then
    msg_error "/db directory does not exist. Add an LXC mountpoint first."
    exit 1
  fi

  if ! mountpoint -q /db; then
    msg_error "/db exists but is not a real mountpoint."
    exit 1
  fi

  msg_ok "/db mountpoint is present"
}

install_postgresql_15() {
  msg_info "Installing PostgreSQL 15"

  install -d -m 0755 /usr/share/keyrings
  curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc \
    | gpg --dearmor -o /usr/share/keyrings/postgresql.gpg

  cat > /etc/apt/sources.list.d/pgdg.list <<EOF
deb [signed-by=/usr/share/keyrings/postgresql.gpg] https://apt.postgresql.org/pub/repos/apt noble-pgdg main
EOF

  apt-get update -y
  apt-get install -y postgresql-15 postgresql-client-15 postgresql-common

  mkdir -p /db/postgresql/15
  chown -R postgres:postgres /db/postgresql
  chmod 700 /db/postgresql
  chmod 700 /db/postgresql/15

  systemctl stop postgresql || true

  if pg_lsclusters | awk '{print $1" "$2}' | grep -q '^15 main$'; then
    pg_dropcluster --stop 15 main
  fi

  pg_createcluster 15 main \
    --datadir="${PGDATA_DIR}" \
    --locale=ru_RU.UTF-8

  systemctl enable -q --now postgresql
  msg_ok "PostgreSQL 15 installed with datadir ${PGDATA_DIR}"
}

configure_linux_user_hd() {
  msg_info "Configuring Linux user hd"

  if id hd >/dev/null 2>&1; then
    usermod -s /bin/bash hd
    usermod -d /home/hd hd
    echo "hd:${HD_PASS}" | chpasswd
  else
    useradd -m -d /home/hd -s /bin/bash hd
    echo "hd:${HD_PASS}" | chpasswd
  fi

  usermod -aG sudo hd
  chown -R hd:hd /home/hd
  chmod 700 /home/hd

  msg_ok "Linux user hd configured"
}

configure_postgresql() {
  msg_info "Configuring PostgreSQL"

  sudo -u postgres psql -v ON_ERROR_STOP=1 <<SQL
ALTER USER postgres WITH PASSWORD '${POSTGRES_SUPER_PASS}';

DO \$\$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'hd') THEN
    ALTER ROLE hd WITH LOGIN SUPERUSER PASSWORD '${HD_PASS}';
  ELSE
    CREATE ROLE hd WITH LOGIN SUPERUSER PASSWORD '${HD_PASS}';
  END IF;
END
\$\$;
SQL

  cat > /etc/postgresql/${POSTGRES_VERSION}/main/pg_hba.conf <<'EOF'
local all all md5
host all all 127.0.0.1/32 md5
host all all ::1/128      md5
host all all 0.0.0.0/0    md5
EOF

  sed -ri "s|^#?\s*listen_addresses\s*=.*|listen_addresses = '*'|g" \
    /etc/postgresql/${POSTGRES_VERSION}/main/postgresql.conf

  systemctl restart postgresql
  msg_ok "PostgreSQL configured"
}

enable_services() {
  msg_info "Enabling services"

  systemctl enable -q --now nginx
  systemctl enable -q --now smbd || true

  if systemctl list-unit-files | grep -q '^ntpsec\.service'; then
    systemctl enable -q --now ntpsec
  elif systemctl list-unit-files | grep -q '^ntpd\.service'; then
    systemctl enable -q --now ntpd
  fi

  msg_ok "Services enabled"
}

show_summary() {
  msg_ok "Installation finished"
  echo
  echo "========== SUMMARY =========="
  echo "PostgreSQL version : $(psql --version 2>/dev/null || true)"
  echo "PostgreSQL data    : ${PGDATA_DIR}"
  echo "Java version       : $(java -version 2>&1 | head -1)"
  echo "Locale             : $(locale | grep '^LANG=' | head -1)"
  echo "Linux user         : hd"
  echo "PostgreSQL role    : hd (SUPERUSER)"
  echo "Nginx              : enabled"
  echo "Samba              : installed"
  echo "NTPsec             : installed"
  echo "================================"
}

install_base_packages
configure_all_locales_then_ru
install_oracle_jdk
check_db_mount
install_postgresql_15
configure_linux_user_hd
configure_postgresql
enable_services
motd_ssh
customize
cleanup_lxc
show_summary
