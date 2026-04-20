#!/bin/bash
# =============================================================
#  Qovra - Hytale Hosting Platform
#  Installer v0.1.0-alpha
#
#  ⚠️  ALPHA SOFTWARE - NOT FOR PRODUCTION USE
#
#  Usage: sudo bash install.sh
# =============================================================

set -e

# ── Colors ────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

log()     { echo -e "${GREEN}[✔]${NC} $1"; }
warn()    { echo -e "${YELLOW}[!]${NC} $1"; }
error()   { echo -e "${RED}[✘]${NC} $1"; exit 1; }
info()    { echo -e "${CYAN}[i]${NC} $1"; }
section() {
  echo ""
  echo -e "${BLUE}${BOLD}══════════════════════════════════════════════${NC}"
  echo -e "${BLUE}${BOLD}  $1${NC}"
  echo -e "${BLUE}${BOLD}══════════════════════════════════════════════${NC}"
}

# ── Banner ────────────────────────────────────────────────────
show_banner() {
  clear
  echo -e "${YELLOW}${BOLD}"
  cat << 'EOF'
  ██████╗  ██████╗ ██╗   ██╗██████╗  █████╗ 
 ██╔═══██╗██╔═══██╗██║   ██║██╔══██╗██╔══██╗
 ██║   ██║██║   ██║██║   ██║██████╔╝███████║
 ██║▄▄ ██║██║   ██║╚██╗ ██╔╝██╔══██╗██╔══██║
 ╚██████╔╝╚██████╔╝ ╚████╔╝ ██║  ██║██║  ██║
  ╚══▀▀═╝  ╚═════╝   ╚═══╝  ╚═╝  ╚═╝╚═╝  ╚═╝
EOF
  echo -e "${NC}"
  echo -e "${CYAN}  Hytale Hosting Platform by Qovra${NC}"
  echo -e "${CYAN}  https://github.com/Qovra${NC}"
  echo -e "${RED}${BOLD}  ⚠️  ALPHA v0.1.0 — NOT FOR PRODUCTION USE${NC}"
  echo ""
}

# ── Root check ────────────────────────────────────────────────
check_root() {
  if [ "$EUID" -ne 0 ]; then
    error "Please run as root: sudo bash install.sh"
  fi
}

# ── Detect installation state ─────────────────────────────────
INSTALL_DIR="/opt/qovra"
is_installed() {
  [ -d "$INSTALL_DIR" ] && [ -f "$INSTALL_DIR/.env" ]
}

# ── Resolve latest release version for a given repo ──────────
get_latest_version() {
  curl -s "https://api.github.com/repos/Qovra/$1/releases/latest" \
    | grep '"tag_name"' | cut -d'"' -f4
}

# ── Detect architecture ───────────────────────────────────────
detect_arch() {
  case "$(uname -m)" in
    x86_64)  echo "amd64" ;;
    aarch64) echo "arm64" ;;
    *) error "Unsupported architecture: $(uname -m)" ;;
  esac
}

# =============================================================
# MAIN MENU
# =============================================================
show_banner
check_root

if is_installed; then
  echo -e "  ${GREEN}Qovra installation detected at ${INSTALL_DIR}${NC}"
  echo ""
  echo -e "  ${BOLD}What would you like to do?${NC}"
  echo ""
  echo -e "  ${CYAN}[1]${NC} Uninstall"
  echo -e "  ${CYAN}[2]${NC} Update ${YELLOW}(Coming Soon)${NC}"
  echo -e "  ${CYAN}[3]${NC} Exit"
  echo ""
  read -rp "$(echo -e ${BOLD}"  Choose an option [1-3]: "${NC})" MENU_CHOICE

  case $MENU_CHOICE in
    1) MODE="uninstall" ;;
    2)
      echo ""
      warn "The updater is not available yet. Stay tuned for future releases."
      echo ""
      exit 0
      ;;
    3) exit 0 ;;
    *)
      error "Invalid option."
      ;;
  esac
else
  echo -e "  ${YELLOW}No Qovra installation found.${NC}"
  echo ""
  echo -e "  ${BOLD}What would you like to do?${NC}"
  echo ""
  echo -e "  ${CYAN}[1]${NC} Install Qovra Platform"
  echo -e "  ${CYAN}[2]${NC} Exit"
  echo ""
  read -rp "$(echo -e ${BOLD}"  Choose an option [1-2]: "${NC})" MENU_CHOICE

  case $MENU_CHOICE in
    1) MODE="install" ;;
    2) exit 0 ;;
    *)
      error "Invalid option."
      ;;
  esac
fi

# =============================================================
# UNINSTALL
# =============================================================
if [ "$MODE" = "uninstall" ]; then
  section "Uninstall Qovra Platform"

  echo -e "${RED}${BOLD}  ⚠️  This will remove all Qovra services, binaries and files.${NC}"
  echo ""
  read -rp "$(echo -e ${BOLD}"  Remove the database and all server data as well? [y/N]: "${NC})" REMOVE_DB
  echo ""
  read -rp "$(echo -e ${RED}${BOLD}"  Are you absolutely sure? Type 'yes' to confirm: "${NC})" FINAL_CONFIRM

  if [ "$FINAL_CONFIRM" != "yes" ]; then
    warn "Uninstall cancelled."
    exit 0
  fi

  info "Stopping and disabling services..."
  for SVC in qovra-backend qovra-daemon qovra-proxy; do
    systemctl stop "$SVC"    2>/dev/null || true
    systemctl disable "$SVC" 2>/dev/null || true
    rm -f "/etc/systemd/system/${SVC}.service"
    log "$SVC removed"
  done
  systemctl daemon-reload

  info "Removing binaries..."
  rm -f /usr/local/bin/qovra-backend
  rm -f /usr/local/bin/qovra-daemon
  rm -f /usr/local/bin/qovra-proxy
  rm -f /usr/local/bin/hytale-downloader
  log "Binaries removed"

  info "Closing firewall rules..."
  ufw delete allow 3000/tcp 2>/dev/null || true
  ufw delete allow 5000/tcp 2>/dev/null || true
  ufw delete allow 5520/udp 2>/dev/null || true
  ufw reload
  log "Firewall rules removed"

  if [[ "$REMOVE_DB" =~ ^[Yy]$ ]]; then
    info "Dropping database and user..."
    sudo -u postgres psql -c "DROP DATABASE IF EXISTS qovra;" 2>/dev/null || true
    sudo -u postgres psql -c "DROP USER IF EXISTS qovra;"     2>/dev/null || true
    log "Database removed"

    info "Removing install directory..."
    rm -rf "$INSTALL_DIR"
    log "Install directory removed"
  else
    info "Removing install directory (preserving DB)..."
    rm -rf "$INSTALL_DIR"
    log "Install directory removed. Database preserved."
  fi

  echo ""
  log "Qovra has been uninstalled successfully."
  echo ""
  exit 0
fi

# =============================================================
# INSTALL
# =============================================================

# ── Alpha disclaimer ──────────────────────────────────────────
echo -e "${RED}${BOLD}  ⚠️  ALPHA SOFTWARE WARNING${NC}"
echo -e "${YELLOW}  - This software is in early alpha stage${NC}"
echo -e "${YELLOW}  - Expect bugs and incomplete features${NC}"
echo -e "${YELLOW}  - Breaking changes may occur without notice${NC}"
echo -e "${YELLOW}  - Not recommended for production environments${NC}"
echo ""
read -rp "$(echo -e ${BOLD}"  I understand, continue with installation? [y/N]: "${NC})" CONFIRM
if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
  warn "Installation cancelled."
  exit 0
fi

# ── Collect admin credentials ─────────────────────────────────
section "Admin Account Setup"
echo -e "  ${CYAN}Create your administrator account:${NC}"
echo ""

while true; do
  read -rp "$(echo -e "  ${BOLD}Username: ${NC}")" ADMIN_USERNAME
  [[ -n "$ADMIN_USERNAME" ]] && break
  warn "Username cannot be empty."
done

while true; do
  read -rp "$(echo -e "  ${BOLD}Email: ${NC}")" ADMIN_EMAIL
  [[ "$ADMIN_EMAIL" =~ ^[^@]+@[^@]+\.[^@]+$ ]] && break
  warn "Please enter a valid email address."
done

while true; do
  read -rsp "$(echo -e "  ${BOLD}Password: ${NC}")" ADMIN_PASSWORD
  echo ""
  read -rsp "$(echo -e "  ${BOLD}Confirm password: ${NC}")" ADMIN_PASSWORD_CONFIRM
  echo ""
  if [ "$ADMIN_PASSWORD" = "$ADMIN_PASSWORD_CONFIRM" ]; then
    [[ ${#ADMIN_PASSWORD} -ge 8 ]] && break
    warn "Password must be at least 8 characters."
  else
    warn "Passwords do not match. Try again."
  fi
done

log "Admin account details collected"

# ── Configuration ─────────────────────────────────────────────
GITHUB_ORG="Qovra"
ARCH=$(detect_arch)
PG_VERSION="16"
PG_USER="qovra"
PG_DB="qovra"
PG_PASSWORD=$(openssl rand -base64 16 | tr -d '/+=')
JWT_SECRET=$(openssl rand -base64 32 | tr -d '/+=')
DAEMON_API_TOKEN=$(openssl rand -base64 32 | tr -d '/+=')
NODE_IP=$(curl -s --max-time 5 https://api.ipify.org || hostname -I | awk '{print $1}')
NODE_HOSTNAME=$(hostname)
NODE_RAM_MB=$(free -m | awk '/^Mem:/{print $2}')
BACKEND_PORT=3000
DAEMON_PORT=5000
PROXY_PORT=5520

# =============================================================
section "Step 1 — System update & base dependencies"
# =============================================================
apt update -y && apt upgrade -y
apt install -y \
  curl wget ufw openssl unzip \
  software-properties-common \
  ca-certificates lsb-release gnupg
log "Base dependencies installed"

# =============================================================
section "Step 2 — Installing Java 25 (required for Hytale Server)"
# =============================================================
if java -version 2>&1 | grep -q "25"; then
  log "Java 25 already installed"
else
  info "Adding Adoptium repository..."
  wget -qO - https://packages.adoptium.net/artifactory/api/gpg/key/public \
    | gpg --dearmor -o /etc/apt/trusted.gpg.d/adoptium.gpg
  echo "deb [signed-by=/etc/apt/trusted.gpg.d/adoptium.gpg] \
https://packages.adoptium.net/artifactory/deb $(lsb_release -cs) main" \
    > /etc/apt/sources.list.d/adoptium.list
  apt update -y
  apt install -y temurin-25-jdk || {
    warn "Java 25 not available via apt, falling back to Java 21..."
    apt install -y openjdk-21-jre-headless
  }
  log "Java installed: $(java -version 2>&1 | head -1)"
fi

# =============================================================
section "Step 3 — Installing PostgreSQL ${PG_VERSION}"
# =============================================================
if ! command -v psql &> /dev/null; then
  info "Adding PostgreSQL repository..."
  curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc \
    | gpg --dearmor -o /etc/apt/trusted.gpg.d/postgresql.gpg
  echo "deb [signed-by=/etc/apt/trusted.gpg.d/postgresql.gpg] \
http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" \
    > /etc/apt/sources list.d/pgdg.list
  apt update -y
  apt install -y postgresql-$PG_VERSION
  log "PostgreSQL ${PG_VERSION} installed"
else
  log "PostgreSQL already installed"
fi

systemctl enable --now postgresql

# ── Ensure pg_hba.conf allows password auth over localhost ────
PG_HBA=$(sudo -u postgres psql -t -P format=unaligned -c "SHOW hba_file;")
info "pg_hba.conf location: $PG_HBA"

# Add a host entry for the qovra user if not already present
if ! grep -q "^host.*${PG_DB}.*${PG_USER}.*127.0.0.1" "$PG_HBA" 2>/dev/null; then
  # Insert before the first "host" line so it takes priority
  sed -i "/^host/i host    ${PG_DB}    ${PG_USER}    127.0.0.1/32    scram-sha-256" "$PG_HBA"
  sed -i "/^host/i host    ${PG_DB}    ${PG_USER}    ::1/128          scram-sha-256" "$PG_HBA"
  systemctl reload postgresql
  log "pg_hba.conf updated for password auth"
fi

sudo -u postgres psql -c \
  "CREATE USER $PG_USER WITH PASSWORD '$PG_PASSWORD';" 2>/dev/null \
  || warn "User $PG_USER already exists"
sudo -u postgres psql -c \
  "CREATE DATABASE $PG_DB OWNER $PG_USER;" 2>/dev/null \
  || warn "Database $PG_DB already exists"
log "PostgreSQL configured (user: $PG_USER / db: $PG_DB)"

# =============================================================
section "Step 4 — Installing Hytale Downloader CLI"
# =============================================================
info "Downloading Hytale Downloader CLI..."
wget -q https://downloader.hytale.com/hytale-downloader.zip -O /tmp/hytale-downloader.zip
unzip -o /tmp/hytale-downloader.zip -d /tmp/hytale-downloader/
chmod +x /tmp/hytale-downloader/hytale-downloader-linux-amd64
mv /tmp/hytale-downloader/hytale-downloader-linux-amd64 /usr/local/bin/hytale-downloader
rm -rf /tmp/hytale-downloader /tmp/hytale-downloader.zip
log "hytale-downloader installed → available globally as 'hytale-downloader'"

# =============================================================
section "Step 5 — Resolving latest release versions"
# =============================================================
info "Fetching latest versions from GitHub..."
BACKEND_VERSION=$(get_latest_version "backend")
DAEMON_VERSION=$(get_latest_version "daemon")
PROXY_VERSION=$(get_latest_version "proxy")
PANEL_VERSION=$(get_latest_version "panel")

[[ -z "$BACKEND_VERSION" ]] && error "Could not resolve backend version"
[[ -z "$DAEMON_VERSION"  ]] && error "Could not resolve daemon version"
[[ -z "$PROXY_VERSION"   ]] && error "Could not resolve proxy version"
[[ -z "$PANEL_VERSION"   ]] && error "Could not resolve panel version"

log "backend  → ${BACKEND_VERSION}"
log "daemon   → ${DAEMON_VERSION}"
log "proxy    → ${PROXY_VERSION}"
log "panel    → ${PANEL_VERSION}"
log "arch     → ${ARCH}"

# =============================================================
section "Step 6 — Downloading binaries"
# =============================================================
mkdir -p "$INSTALL_DIR"

download_binary() {
  local REPO=$1
  local VERSION=$2
  local BINARY_NAME=$3
  local DEST=$4

  local URL="https://github.com/${GITHUB_ORG}/${REPO}/releases/download/${VERSION}/${BINARY_NAME}-linux-${ARCH}"
  info "Downloading ${BINARY_NAME} ${VERSION}..."
  wget -q "$URL" -O "$DEST" || error "Failed to download ${BINARY_NAME} from ${URL}"
  chmod +x "$DEST"
  log "${BINARY_NAME} ready"
}

download_binary "backend" "$BACKEND_VERSION" "qovra-backend" "/usr/local/bin/qovra-backend"
download_binary "daemon"  "$DAEMON_VERSION"  "qovra-daemon"  "/usr/local/bin/qovra-daemon"
download_binary "proxy"   "$PROXY_VERSION"   "qovra-proxy"   "/usr/local/bin/qovra-proxy"

# =============================================================
section "Step 7 — Downloading Panel"
# =============================================================
info "Downloading panel ${PANEL_VERSION}..."
mkdir -p "$INSTALL_DIR/panel"
wget -q "https://github.com/${GITHUB_ORG}/panel/releases/download/${PANEL_VERSION}/qovra-panel.tar.gz" \
  -O /tmp/qovra-panel.tar.gz || error "Failed to download panel"
tar -xzf /tmp/qovra-panel.tar.gz -C "$INSTALL_DIR/panel"
rm /tmp/qovra-panel.tar.gz
log "Panel ready → $INSTALL_DIR/panel"

# =============================================================
section "Step 8 — Applying database schema"
# =============================================================
info "Applying schema..."
PGPASSWORD=$PG_PASSWORD psql -h localhost -U $PG_USER -d $PG_DB << 'SCHEMA'
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

CREATE TYPE user_role AS ENUM ('admin', 'staff', 'customer');

CREATE TABLE IF NOT EXISTS users (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    username     VARCHAR(50)  NOT NULL UNIQUE,
    email        VARCHAR(200) NOT NULL UNIQUE,
    password     VARCHAR(255) NOT NULL,
    role         user_role    NOT NULL DEFAULT 'customer',
    created_at   TIMESTAMP    NOT NULL DEFAULT NOW(),
    updated_at   TIMESTAMP    NOT NULL DEFAULT NOW()
);

CREATE TYPE node_status AS ENUM ('online', 'offline', 'maintenance');

CREATE TABLE IF NOT EXISTS nodes (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    hostname      VARCHAR(200) NOT NULL UNIQUE,
    ip            VARCHAR(50)  NOT NULL,
    daemon_port   INTEGER      NOT NULL DEFAULT 8080,
    ram_total_mb  INTEGER      NOT NULL,
    status        node_status  NOT NULL DEFAULT 'offline',
    created_at    TIMESTAMP    NOT NULL DEFAULT NOW(),
    updated_at    TIMESTAMP    NOT NULL DEFAULT NOW()
);

CREATE TYPE server_status AS ENUM ('running', 'stopped', 'crashed', 'installing');

CREATE TABLE IF NOT EXISTS servers (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    node_id          UUID         NOT NULL REFERENCES nodes(id) ON DELETE RESTRICT,
    owner_id         UUID         NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    name             VARCHAR(100) NOT NULL,
    hostname         VARCHAR(255) NOT NULL,
    server_type      VARCHAR(20)  NOT NULL DEFAULT 'proxy',
    installing       BOOLEAN      NOT NULL DEFAULT FALSE,
    install_progress INTEGER      NOT NULL DEFAULT 0,
    port             INTEGER      NOT NULL,
    ram_mb           INTEGER      NOT NULL,
    version          VARCHAR(20)  NOT NULL,
    status           server_status NOT NULL DEFAULT 'installing',
    config           JSONB        NOT NULL DEFAULT '{}',
    created_at       TIMESTAMP    NOT NULL DEFAULT NOW(),
    updated_at       TIMESTAMP    NOT NULL DEFAULT NOW(),
    CONSTRAINT unique_port_per_node     UNIQUE (node_id, port),
    CONSTRAINT unique_hostname_per_node UNIQUE (node_id, hostname)
);

CREATE INDEX IF NOT EXISTS idx_servers_node_id  ON servers(node_id);
CREATE INDEX IF NOT EXISTS idx_servers_owner_id ON servers(owner_id);
CREATE INDEX IF NOT EXISTS idx_servers_status   ON servers(status);
CREATE INDEX IF NOT EXISTS idx_nodes_status     ON nodes(status);

CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_users_updated_at ON users;
CREATE TRIGGER trg_users_updated_at
    BEFORE UPDATE ON users
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

DROP TRIGGER IF EXISTS trg_nodes_updated_at ON nodes;
CREATE TRIGGER trg_nodes_updated_at
    BEFORE UPDATE ON nodes
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

DROP TRIGGER IF EXISTS trg_servers_updated_at ON servers;
CREATE TRIGGER trg_servers_updated_at
    BEFORE UPDATE ON servers
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TABLE IF NOT EXISTS user_sessions (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id      UUID         NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    token        VARCHAR(512) NOT NULL UNIQUE,
    ip           VARCHAR(50),
    user_agent   TEXT,
    expires_at   TIMESTAMP    NOT NULL,
    created_at   TIMESTAMP    NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_sessions_user_id ON user_sessions(user_id);
CREATE INDEX IF NOT EXISTS idx_sessions_token   ON user_sessions(token);
CREATE INDEX IF NOT EXISTS idx_sessions_expires ON user_sessions(expires_at);

CREATE TYPE log_level  AS ENUM ('info', 'warning', 'error', 'critical');
CREATE TYPE log_target AS ENUM ('server', 'node', 'user', 'system');

CREATE TABLE IF NOT EXISTS event_logs (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    level        log_level    NOT NULL DEFAULT 'info',
    target       log_target   NOT NULL,
    target_id    UUID,
    user_id      UUID REFERENCES users(id) ON DELETE SET NULL,
    action       VARCHAR(100) NOT NULL,
    message      TEXT         NOT NULL,
    metadata     JSONB        NOT NULL DEFAULT '{}',
    created_at   TIMESTAMP    NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_logs_target     ON event_logs(target, target_id);
CREATE INDEX IF NOT EXISTS idx_logs_user_id    ON event_logs(user_id);
CREATE INDEX IF NOT EXISTS idx_logs_level      ON event_logs(level);
CREATE INDEX IF NOT EXISTS idx_logs_created_at ON event_logs(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_logs_action     ON event_logs(action);
SCHEMA
log "Schema applied"

# =============================================================
section "Step 9 — Seeding database"
# =============================================================
info "Creating admin user and registering this node..."

SAFE_PASSWORD="${ADMIN_PASSWORD//\'/\'\'}"
SAFE_USERNAME="${ADMIN_USERNAME//\'/\'\'}"
SAFE_EMAIL="${ADMIN_EMAIL//\'/\'\'}"

PGPASSWORD=$PG_PASSWORD psql -h localhost -U $PG_USER -d $PG_DB << SEED
INSERT INTO users (username, email, password, role)
VALUES (
    '${SAFE_USERNAME}',
    '${SAFE_EMAIL}',
    crypt('${SAFE_PASSWORD}', gen_salt('bf', 10)),
    'admin'
) ON CONFLICT (email) DO NOTHING;

INSERT INTO nodes (hostname, ip, daemon_port, ram_total_mb, status)
VALUES (
    '${NODE_HOSTNAME}',
    '${NODE_IP}',
    ${DAEMON_PORT},
    ${NODE_RAM_MB},
    'offline'
) ON CONFLICT (hostname) DO NOTHING;
SEED
log "Admin user '${ADMIN_USERNAME}' created"
log "Node '${NODE_HOSTNAME}' registered (IP: ${NODE_IP}, RAM: ${NODE_RAM_MB}MB)"

# =============================================================
section "Step 10 — Generating .env configuration"
# =============================================================
mkdir -p "$INSTALL_DIR/servers"

cat > "$INSTALL_DIR/.env" << EOF
# ── Database ──────────────────────────────────────
DB_URL=postgresql://${PG_USER}:${PG_PASSWORD}@localhost:5432/${PG_DB}

# ── Auth ──────────────────────────────────────────
JWT_SECRET=${JWT_SECRET}
DAEMON_API_TOKEN=${DAEMON_API_TOKEN}

# ── Services ──────────────────────────────────────
BACKEND_URL=http://localhost:${BACKEND_PORT}
PANEL_PORT=${BACKEND_PORT}
DAEMON_PORT=${DAEMON_PORT}
PROXY_PORT=${PROXY_PORT}

# ── Node identity ─────────────────────────────────
NODE_IP=${NODE_IP}
NODE_HOSTNAME=${NODE_HOSTNAME}

# ── Hytale paths ──────────────────────────────────
PROXY_BINARY=/usr/local/bin/qovra-proxy
SERVERS_PATH=${INSTALL_DIR}/servers

# ── Versions ──────────────────────────────────────
BACKEND_VERSION=${BACKEND_VERSION}
DAEMON_VERSION=${DAEMON_VERSION}
PROXY_VERSION=${PROXY_VERSION}
PANEL_VERSION=${PANEL_VERSION}
EOF

log ".env generated"

# =============================================================
section "Step 11 — Installing systemd services"
# =============================================================
cat > /etc/systemd/system/qovra-backend.service << EOF
[Unit]
Description=Qovra Backend (Orchestrator)
After=network.target postgresql.service
Requires=postgresql.service

[Service]
Type=simple
User=root
WorkingDirectory=${INSTALL_DIR}
EnvironmentFile=${INSTALL_DIR}/.env
ExecStart=/usr/local/bin/qovra-backend
Restart=always
RestartSec=5
StartLimitIntervalSec=60
StartLimitBurst=5

[Install]
WantedBy=multi-user.target
EOF

cat > /etc/systemd/system/qovra-daemon.service << EOF
[Unit]
Description=Qovra Daemon (Node Manager)
After=network.target qovra-backend.service
Wants=qovra-backend.service

[Service]
Type=simple
User=root
WorkingDirectory=${INSTALL_DIR}
EnvironmentFile=${INSTALL_DIR}/.env
ExecStart=/usr/local/bin/qovra-daemon
Restart=always
RestartSec=5
StartLimitIntervalSec=60
StartLimitBurst=5

[Install]
WantedBy=multi-user.target
EOF

cat > /etc/systemd/system/qovra-proxy.service << EOF
[Unit]
Description=Qovra Proxy (SNI Ingress)
After=network.target qovra-daemon.service

[Service]
Type=simple
User=root
WorkingDirectory=${INSTALL_DIR}
EnvironmentFile=${INSTALL_DIR}/.env
ExecStart=/usr/local/bin/qovra-proxy
Restart=always
RestartSec=5
StartLimitIntervalSec=60
StartLimitBurst=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable qovra-backend qovra-daemon qovra-proxy
systemctl start  qovra-backend qovra-daemon qovra-proxy
log "All services installed and started"

# =============================================================
section "Step 12 — Configuring firewall (UFW)"
# =============================================================
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp               comment 'SSH'
ufw allow ${BACKEND_PORT}/tcp  comment 'Qovra Backend API'
ufw allow ${DAEMON_PORT}/tcp   comment 'Qovra Daemon API'
ufw allow ${PROXY_PORT}/udp    comment 'Hytale Proxy QUIC'
ufw --force enable
log "Firewall configured"

# =============================================================
section "Step 13 — Verifying services"
# =============================================================
sleep 3
ALL_OK=true
for SVC in qovra-backend qovra-daemon qovra-proxy; do
  STATUS=$(systemctl is-active "$SVC")
  if [ "$STATUS" = "active" ]; then
    log "$SVC is running"
  else
    warn "$SVC is $STATUS — check with: journalctl -u $SVC -n 50"
    ALL_OK=false
  fi
done

# =============================================================
section "✅  Installation complete"
# =============================================================
echo ""
echo -e "${GREEN}${BOLD}╔══════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}${BOLD}║    Qovra Platform installed successfully     ║${NC}"
echo -e "${GREEN}${BOLD}║              ⚠️  ALPHA v0.1.0                ║${NC}"
echo -e "${GREEN}${BOLD}╚══════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  📁 Install dir:      ${YELLOW}${INSTALL_DIR}${NC}"
echo -e "  🌐 Node IP:          ${YELLOW}${NODE_IP}${NC}"
echo -e "  🖥️  Panel API:        ${YELLOW}http://${NODE_IP}:${BACKEND_PORT}${NC}"
echo -e "  ⚙️  Daemon API:       ${YELLOW}http://localhost:${DAEMON_PORT}${NC}"
echo -e "  🎮 Proxy (QUIC):     ${YELLOW}UDP ${PROXY_PORT}${NC}"
echo -e "  👤 Admin user:       ${YELLOW}${ADMIN_USERNAME} (${ADMIN_EMAIL})${NC}"
echo -e "  🖧  Node registered: ${YELLOW}${NODE_HOSTNAME} — ${NODE_RAM_MB}MB RAM${NC}"
echo ""
echo -e "  📦 Versions installed:"
echo -e "     backend  ${YELLOW}${BACKEND_VERSION}${NC}"
echo -e "     daemon   ${YELLOW}${DAEMON_VERSION}${NC}"
echo -e "     proxy    ${YELLOW}${PROXY_VERSION}${NC}"
echo -e "     panel    ${YELLOW}${PANEL_VERSION}${NC}"
echo ""
echo -e "  🔐 Credentials:      ${YELLOW}${INSTALL_DIR}/.env${NC}"
echo ""

if [ "$ALL_OK" = false ]; then
  echo -e "${YELLOW}  ⚠️  One or more services failed to start.${NC}"
  echo -e "${YELLOW}     Check logs with: journalctl -u <service> -n 50${NC}"
  echo ""
fi

echo -e "${YELLOW}  Useful commands:${NC}"
echo -e "    systemctl status qovra-backend"
echo -e "    systemctl status qovra-daemon"
echo -e "    systemctl status qovra-proxy"
echo -e "    journalctl -u qovra-daemon -f"
echo -e "    hytale-downloader --help"
echo ""
echo -e "${RED}  ⚠️  Keep your .env file secure. Never commit it to Git.${NC}"
echo ""