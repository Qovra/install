#!/bin/bash
# =============================================================
#  Qovra - Hytale Hosting Platform
#  Installer v0.1.0
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
DIM='\033[2m'
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
  echo -e "  ${CYAN}[2]${NC} Reinstall CLI / repair ${DIM}(re-generates /usr/local/bin/qovra)${NC}"
  echo -e "  ${CYAN}[3]${NC} Exit"
  echo ""
  read -rp "$(echo -e ${BOLD}"  Choose an option [1-3]: "${NC})" MENU_CHOICE

  case $MENU_CHOICE in
    1) MODE="uninstall" ;;
    2) MODE="repair_cli" ;;
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

  info "Removing binaries and CLI..."
  rm -f /usr/local/bin/qovra-backend
  rm -f /usr/local/bin/qovra-daemon
  rm -f /usr/local/bin/qovra-proxy
  rm -f /usr/local/bin/hytale-downloader
  rm -f /usr/local/bin/qovra
  log "Binaries and CLI removed"

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
# REPAIR CLI (re-instala solo el CLI sin tocar servicios)
# =============================================================
if [ "$MODE" = "repair_cli" ]; then
  section "Reinstalling Qovra CLI"
  # install_cli() se define más abajo; para repair_cli la llamamos
  # después de definirla — redirigimos a una función late-bound.
  REPAIR_CLI_ONLY=true
fi

# =============================================================
# INSTALL
# =============================================================

# ── Alpha disclaimer ──────────────────────────────────────────
if [ "${REPAIR_CLI_ONLY:-false}" = "false" ]; then
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

  # ── Collect admin credentials ───────────────────────────────
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
fi

# ── Configuration ─────────────────────────────────────────────
GITHUB_ORG="Qovra"
GO_VERSION="1.22.4"
PG_VERSION="16"
PG_USER="qovra"
PG_DB="qovra"
INSTALLER_VERSION="${INSTALLER_VERSION:-0.1.1}"
REPOS=("daemon" "backend" "proxy" "panel")

if [ "${REPAIR_CLI_ONLY:-false}" = "false" ]; then
  PG_PASSWORD=$(openssl rand -base64 16 | tr -d '/+=')
  JWT_SECRET=$(openssl rand -base64 32 | tr -d '/+=')
  DAEMON_API_TOKEN=$(openssl rand -base64 32 | tr -d '/+=')
  NODE_IP=$(curl -s --max-time 5 https://api.ipify.org || hostname -I | awk '{print $1}')
  NODE_HOSTNAME=$(hostname)
  NODE_RAM_MB=$(free -m | awk '/^Mem:/{print $2}')
  BACKEND_PORT=3000
  DAEMON_PORT=8550
  PROXY_PORT=5520
fi

# ── Detect system architecture ────────────────────────────────
ARCH=$(uname -m)
case $ARCH in
  x86_64)  GOARCH="amd64" ;;
  aarch64) GOARCH="arm64" ;;
  armv7l)  GOARCH="arm"   ;;
  *)       error "Unsupported architecture: $ARCH" ;;
esac
info "Detected architecture: $ARCH → $GOARCH"

# =============================================================
# FUNCTION: install_cli
# Genera el script /usr/local/bin/qovra y lo hace ejecutable.
# Se llama al final del install normal Y en repair_cli.
# =============================================================
install_cli() {
  section "Installing Qovra CLI → /usr/local/bin/qovra"

  # Leer versiones instaladas para embeber en el script si estamos
  # en repair — en install fresco se escriben antes de llamar a esta fn.
  local _installer_version="${INSTALLER_VERSION:-0.1.0}"
  local _github_org="${GITHUB_ORG:-Qovra}"
  local _install_dir="${INSTALL_DIR:-/opt/qovra}"
  local _goarch="${GOARCH:-amd64}"

  cat > /usr/local/bin/qovra << 'QOVRA_CLI_EOF'
#!/bin/bash
# =============================================================
#  Qovra CLI — /usr/local/bin/qovra
#  Auto-generated by install.sh — do not edit manually.
#  To regenerate: sudo bash install.sh  →  "Reinstall CLI"
# =============================================================

set -euo pipefail

# ── Colors ────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# ── Constants (injected at install time) ──────────────────────
QOVRA_CLI_EOF

  # Inyectar constantes con los valores reales del momento de instalación
  cat >> /usr/local/bin/qovra << QOVRA_CONSTANTS
INSTALL_DIR="${_install_dir}"
GITHUB_ORG="${_github_org}"
INSTALLER_VERSION="${_installer_version}"
GOARCH="${_goarch}"
QOVRA_CONSTANTS

  # Resto del CLI (heredoc literal — sin expansión)
  cat >> /usr/local/bin/qovra << 'QOVRA_CLI_BODY'

# ── Derived paths ─────────────────────────────────────────────
VERSIONS_FILE="${INSTALL_DIR}/.versions"
ENV_FILE="${INSTALL_DIR}/.env"

# ── Helpers ───────────────────────────────────────────────────
_log()   { echo -e "  ${GREEN}✔${NC}  $1"; }
_warn()  { echo -e "  ${YELLOW}⚠${NC}  $1"; }
_error() { echo -e "  ${RED}✘${NC}  $1" >&2; exit 1; }
_info()  { echo -e "  ${CYAN}→${NC}  $1"; }

_divider() {
  echo -e "  ${DIM}────────────────────────────────────────────${NC}"
}
_section() {
  echo ""
  echo -e "  ${BLUE}${BOLD}$1${NC}"
  _divider
}

# ── Require installed ─────────────────────────────────────────
_require_installed() {
  if [ ! -d "${INSTALL_DIR}" ] || [ ! -f "${ENV_FILE}" ]; then
    _error "Qovra is not installed. Run: sudo bash install.sh"
  fi
}

# ── Read installed version for a component ────────────────────
_get_version() {
  local component="$1"
  if [ -f "${VERSIONS_FILE}" ]; then
    grep "^${component}=" "${VERSIONS_FILE}" 2>/dev/null | cut -d'=' -f2 || echo "unknown"
  else
    echo "unknown"
  fi
}

# ── Read a value from .env ────────────────────────────────────
_get_env() {
  local key="$1"
  grep "^${key}=" "${ENV_FILE}" 2>/dev/null | cut -d'=' -f2- || echo ""
}

# ── Get latest GitHub release tag for a repo ─────────────────
_latest_release() {
  local repo="$1"
  curl -sf --max-time 10 \
    "https://api.github.com/repos/${GITHUB_ORG}/${repo}/releases/latest" \
    | grep '"tag_name"' \
    | sed 's/.*"tag_name": *"\([^"]*\)".*/\1/' \
    || echo ""
}

# ── Service status colored line ───────────────────────────────
_svc_line() {
  local svc="$1" label="$2"
  local status
  status=$(systemctl is-active "${svc}" 2>/dev/null || echo "inactive")

  local color badge
  case "${status}" in
    active)           color="${GREEN}";  badge="● running " ;;
    inactive|stopped) color="${YELLOW}"; badge="○ stopped " ;;
    failed)           color="${RED}";    badge="✘ failed  " ;;
    *)                color="${DIM}";    badge="? unknown " ;;
  esac

  local ver
  ver=$(_get_version "${label}")

  printf "  ${color}${BOLD}%-10s${NC}  %-10s  ${DIM}%-12s${NC}  ${DIM}%s${NC}\n" \
    "${badge}" "${label}" "v${ver}" "${svc}"
}

# =============================================================
# COMMAND: help
# =============================================================
cmd_help() {
  echo ""
  echo -e "  ${YELLOW}${BOLD}"
  cat << 'BANNER'
   ██████╗  ██████╗ ██╗   ██╗██████╗  █████╗ 
  ██╔═══██╗██╔═══██╗██║   ██║██╔══██╗██╔══██╗
  ██║   ██║██║   ██║██║   ██║██████╔╝███████║
  ██║▄▄ ██║██║   ██║╚██╗ ██╔╝██╔══██╗██╔══██║
  ╚██████╔╝╚██████╔╝ ╚████╔╝ ██║  ██║██║  ██║
   ╚══▀▀═╝  ╚═════╝   ╚═══╝  ╚═╝  ╚═╝╚═╝  ╚═╝
BANNER
  echo -e "${NC}"
  echo -e "  ${CYAN}Hytale Hosting Platform CLI${NC}"
  echo -e "  ${DIM}Installer v${INSTALLER_VERSION} · github.com/${GITHUB_ORG}${NC}"
  echo ""
  _divider
  echo ""
  echo -e "  ${BOLD}USAGE${NC}"
  echo -e "    ${CYAN}qovra${NC} <command> [target]"
  echo ""
  echo -e "  ${BOLD}COMMANDS${NC}"
  echo ""
  printf "    ${CYAN}%-22s${NC} %s\n" "help"            "Show this help message"
  printf "    ${CYAN}%-22s${NC} %s\n" "status"          "Show running state of all services"
  printf "    ${CYAN}%-22s${NC} %s\n" "info"            "Show platform info and endpoints"
  printf "    ${CYAN}%-22s${NC} %s\n" "check-update"    "Check for available updates"
  printf "    ${CYAN}%-22s${NC} %s\n" "update <target>" "Update a component (or all)"
  printf "    ${CYAN}%-22s${NC} %s\n" "self-update"     "Update the Qovra CLI itself"
  printf "    ${CYAN}%-22s${NC} %s\n" "reload"          "Restart background services"
  echo ""
  echo -e "  ${BOLD}UPDATE TARGETS${NC}"
  echo ""
  printf "    ${YELLOW}%-12s${NC} %s\n" "all"     "Update backend + daemon + proxy + panel"
  printf "    ${YELLOW}%-12s${NC} %s\n" "backend" "Backend API + panel file server"
  printf "    ${YELLOW}%-12s${NC} %s\n" "daemon"  "Node daemon"
  printf "    ${YELLOW}%-12s${NC} %s\n" "proxy"   "SNI proxy"
  printf "    ${YELLOW}%-12s${NC} %s\n" "panel"   "Web panel (React SPA)"
  echo ""
  _divider
  echo -e "  ${DIM}Examples:${NC}"
  echo -e "    ${DIM}qovra status${NC}"
  echo -e "    ${DIM}qovra update backend${NC}"
  echo -e "    ${DIM}qovra update all${NC}"
  echo -e "    ${DIM}qovra self-update${NC}"
  echo ""
}

# =============================================================
# COMMAND: status
# =============================================================
cmd_status() {
  _require_installed
  _section "Service Status"
  echo ""
  printf "  ${BOLD}${DIM}%-12s  %-10s  %-14s  %s${NC}\n" \
    "STATE" "COMPONENT" "VERSION" "SYSTEMD UNIT"
  echo ""

  _svc_line "qovra-backend" "backend"
  _svc_line "qovra-daemon"  "daemon"
  
  # Proxy: now managed natively by Daemon
  local proxy_ver
  proxy_ver=$(_get_version "proxy")
  printf "  ${CYAN}${BOLD}%-10s${NC}  %-10s  ${DIM}v%-12s${NC}  ${DIM}%s${NC}\n" \
    "◈ managed " "proxy" "${proxy_ver}" "(managed by daemon)"
  local panel_ver
  panel_ver=$(_get_version "panel")
  printf "  ${CYAN}${BOLD}%-10s${NC}  %-10s  ${DIM}%-14s${NC}  ${DIM}%s${NC}\n" \
    "◈ static  " "panel" "v${panel_ver}" "(served by backend)"

  echo ""

  # Aviso si el CLI / installer tiene actualización
  local latest_installer
  latest_installer=$(_latest_release "install" 2>/dev/null || echo "")
  if [ -n "${latest_installer}" ] && [ "v${INSTALLER_VERSION}" != "${latest_installer}" ]; then
    _divider
    _warn "CLI update available: ${DIM}v${INSTALLER_VERSION}${NC} → ${GREEN}${latest_installer}${NC}  Run: ${CYAN}qovra self-update${NC}"
  fi

  echo ""
}

# =============================================================
# COMMAND: info
# =============================================================
cmd_info() {
  _require_installed

  local node_ip panel_port daemon_port proxy_port node_hostname admin_user

  node_ip=$(_get_env "NODE_IP")
  panel_port=$(_get_env "PANEL_PORT")
  daemon_port=$(_get_env "DAEMON_PORT")
  proxy_port=$(_get_env "PROXY_PORT")
  node_hostname=$(_get_env "NODE_HOSTNAME")
  admin_user=$(_get_env "ADMIN_USERNAME")

  [ -z "${panel_port}" ]  && panel_port="3000"
  [ -z "${daemon_port}" ] && daemon_port="8550"
  [ -z "${proxy_port}" ]  && proxy_port="5520"

  local v_backend v_daemon v_proxy v_panel
  v_backend=$(_get_version "backend")
  v_daemon=$(_get_version "daemon")
  v_proxy=$(_get_version "proxy")
  v_panel=$(_get_version "panel")

  echo ""
  echo -e "  ${GREEN}${BOLD}╔══════════════════════════════════════════════╗${NC}"
  echo -e "  ${GREEN}${BOLD}║      Qovra Platform — Installation Info      ║${NC}"
  echo -e "  ${GREEN}${BOLD}║               ⚠️  ALPHA v${INSTALLER_VERSION}               ║${NC}"
  echo -e "  ${GREEN}${BOLD}╚══════════════════════════════════════════════╝${NC}"
  echo ""
  echo -e "  📁  Install dir      ${YELLOW}${INSTALL_DIR}${NC}"
  echo -e "  🔐  Credentials      ${YELLOW}${INSTALL_DIR}/.env${NC}"
  echo ""
  _section "Endpoints"
  echo ""
  echo -e "  🌐  Node IP          ${YELLOW}${node_ip:-unknown}${NC}"
  echo -e "  🖥️   Panel Web UI     ${YELLOW}http://${node_ip:-localhost}:${panel_port}/${NC}"
  echo -e "  🔌  Backend API      ${YELLOW}http://${node_ip:-localhost}:${panel_port}/api/${NC}"
  echo -e "  ⚙️   Daemon API       ${YELLOW}http://localhost:${daemon_port}${NC}"
  echo -e "  🎮  Proxy (QUIC)     ${YELLOW}UDP ${proxy_port}${NC}"
  echo ""
  _section "Node"
  echo ""
  echo -e "  🖧   Hostname        ${YELLOW}${node_hostname:-unknown}${NC}"
  echo ""
  _section "Component Versions"
  echo ""
  printf "    ${DIM}%-10s${NC}  %s\n" "backend" "v${v_backend}"
  printf "    ${DIM}%-10s${NC}  %s\n" "daemon"  "v${v_daemon}"
  printf "    ${DIM}%-10s${NC}  %s\n" "proxy"   "v${v_proxy}"
  printf "    ${DIM}%-10s${NC}  %s\n" "panel"   "v${v_panel}"
  printf "    ${DIM}%-10s${NC}  %s\n" "cli"     "v${INSTALLER_VERSION}"
  echo ""
  _section "Useful Commands"
  echo ""
  echo -e "    systemctl status qovra-backend"
  echo -e "    systemctl status qovra-daemon"
  echo -e "    systemctl status qovra-proxy"
  echo -e "    journalctl -u qovra-backend -f"
  echo -e "    journalctl -u qovra-daemon  -f"
  echo -e "    hytale-downloader --help"
  echo ""
  echo -e "  ${RED}  ⚠️  Keep your .env file secure. Never commit it to Git.${NC}"
  echo ""
}

# =============================================================
# COMMAND: check-update
# =============================================================
cmd_check_update() {
  _require_installed
  _section "Checking for updates"
  echo ""

  local components=("backend" "daemon" "proxy" "panel")
  local any_update=false

  for comp in "${components[@]}"; do
    local installed latest
    installed=$(_get_version "${comp}")
    _info "Checking ${comp}..."
    latest=$(_latest_release "${comp}" 2>/dev/null || echo "")

    if [ -z "${latest}" ]; then
      printf "  ${YELLOW}%-10s${NC}  ${DIM}v%-12s${NC}  %s\n" \
        "${comp}" "${installed}" "⚠  could not reach GitHub"
      continue
    fi

    if [ "v${installed}" = "${latest}" ] || [ "${installed}" = "${latest}" ]; then
      printf "  ${GREEN}%-10s${NC}  ${DIM}v%-12s${NC}  %s\n" \
        "${comp}" "${installed}" "✔  up to date"
    else
      printf "  ${YELLOW}%-10s${NC}  ${DIM}v%-10s${NC}  ${CYAN}→ %-10s${NC}  %s\n" \
        "${comp}" "${installed}" "${latest}" "update available"
      any_update=true
    fi
  done

  # CLI / installer
  echo ""
  local latest_cli
  latest_cli=$(_latest_release "install" 2>/dev/null || echo "")
  if [ -n "${latest_cli}" ]; then
    if [ "v${INSTALLER_VERSION}" = "${latest_cli}" ] || [ "${INSTALLER_VERSION}" = "${latest_cli}" ]; then
      printf "  ${GREEN}%-10s${NC}  ${DIM}v%-12s${NC}  %s\n" \
        "cli" "${INSTALLER_VERSION}" "✔  up to date"
    else
      printf "  ${YELLOW}%-10s${NC}  ${DIM}v%-10s${NC}  ${CYAN}→ %-10s${NC}  %s\n" \
        "cli" "${INSTALLER_VERSION}" "${latest_cli}" "update available"
      any_update=true
    fi
  fi

  echo ""
  if [ "${any_update}" = true ]; then
    _info "Run ${CYAN}qovra update all${NC} to update components"
    _info "Run ${CYAN}qovra self-update${NC} to update the CLI"
  else
    _log "Everything is up to date."
  fi
  echo ""
}

# =============================================================
# COMMAND: update <target>
# =============================================================
cmd_update() {
  _require_installed

  if [ "${EUID:-$(id -u)}" -ne 0 ]; then
    _error "qovra update requires root. Run: sudo qovra update $1"
  fi

  local target="${1:-}"
  if [ -z "${target}" ]; then
    _error "Usage: qovra update <backend|daemon|proxy|panel|all>"
  fi

  case "${target}" in
    all)     _update_component backend && _update_component daemon \
               && _update_component proxy && _update_component panel ;;
    backend) _update_component backend ;;
    daemon)  _update_component daemon ;;
    proxy)   _update_component proxy ;;
    panel)   _update_component panel ;;
    *)       _error "Unknown target '${target}'. Valid: backend daemon proxy panel all" ;;
  esac

  echo ""
  _log "Update complete."
  echo ""
}

# ── Internal: update a single component ───────────────────────
_update_component() {
  local comp="$1"
  local installed latest

  installed=$(_get_version "${comp}")
  _info "Fetching latest release for ${CYAN}${comp}${NC}..."
  latest=$(_latest_release "${comp}" 2>/dev/null || echo "")

  if [ -z "${latest}" ]; then
    _warn "${comp}: could not reach GitHub — skipping."
    return 0
  fi

  if [ "v${installed}" = "${latest}" ] || [ "${installed}" = "${latest}" ]; then
    _log "${comp} is already at ${latest} — nothing to do."
    return 0
  fi

  _info "${comp}: ${DIM}v${installed}${NC} → ${GREEN}${latest}${NC}"

  if [ "${comp}" = "panel" ]; then
    _update_panel "${latest}"
  else
    _update_binary "${comp}" "${latest}"
  fi

  # Guardar nueva versión (sin prefijo 'v')
  local clean_ver="${latest#v}"
  if [ -f "${VERSIONS_FILE}" ]; then
    sed -i "s/^${comp}=.*/${comp}=${clean_ver}/" "${VERSIONS_FILE}" 2>/dev/null \
      || echo "${comp}=${clean_ver}" >> "${VERSIONS_FILE}"
  else
    echo "${comp}=${clean_ver}" >> "${VERSIONS_FILE}"
  fi

  _log "${comp} updated to ${latest}"
}

_update_binary() {
  local comp="$1" tag="$2"
  local binary_name="qovra-${comp}-linux-${GOARCH}"
  local url="https://github.com/${GITHUB_ORG}/${comp}/releases/download/${tag}/${binary_name}"
  local dest="/usr/local/bin/qovra-${comp}"

  _info "Downloading ${binary_name}..."
  wget -q "${url}" -O "${dest}.tmp" \
    || { _warn "Failed to download ${comp} from ${url}"; rm -f "${dest}.tmp"; return 1; }

  # Stop service if it's not proxy (proxy is daemon managed)
  local svc="qovra-${comp}"
  if [ "${comp}" != "proxy" ]; then
    _info "Restarting ${svc}..."
    systemctl stop "${svc}"  2>/dev/null || true
  fi

  mv "${dest}.tmp" "${dest}"
  chmod +x "${dest}"

  if [ "${comp}" != "proxy" ]; then
    systemctl start "${svc}" 2>/dev/null || _warn "${svc} failed to start — check: journalctl -u ${svc} -n 50"
  else
    _info "Restarting daemon to apply new proxy binary..."
    systemctl restart qovra-daemon 2>/dev/null || true
  fi

  # Register new version
  sed -i "/^${comp}=/d" "${VERSIONS_FILE}" 2>/dev/null || true
  echo "${comp}=${tag#v}" >> "${VERSIONS_FILE}"
}

_update_panel() {
  local tag="$1"
  local panel_dist="${INSTALL_DIR}/panel/dist"
  local url="https://github.com/${GITHUB_ORG}/panel/releases/download/${tag}/qovra-panel.tar.gz"

  _info "Downloading panel ${tag}..."
  wget -q "${url}" -O /tmp/qovra-panel-update.tar.gz \
    || { _warn "Failed to download panel from ${url}"; return 1; }

  _info "Replacing panel dist..."
  rm -rf "${panel_dist:?}"/*
  tar -xzf /tmp/qovra-panel-update.tar.gz -C "${panel_dist}"
  rm -f /tmp/qovra-panel-update.tar.gz

  # Register new version
  sed -i "/^panel=/d" "${VERSIONS_FILE}" 2>/dev/null || true
  echo "panel=${tag#v}" >> "${VERSIONS_FILE}"

  # Recargar backend para que sirva los archivos nuevos
  systemctl restart qovra-backend 2>/dev/null || true
}

# =============================================================
# COMMAND: reload
# =============================================================
cmd_reload() {
  if [ "${EUID:-$(id -u)}" -ne 0 ]; then
    _error "qovra reload requires root. Run: sudo qovra reload"
  fi

  _section "Reloading Qovra Services"
  echo ""
  
  _info "Restarting qovra-backend..."
  systemctl restart qovra-backend 2>/dev/null || _warn "Failed to restart qovra-backend"
  
  _info "Restarting qovra-daemon..."
  systemctl restart qovra-daemon 2>/dev/null || _warn "Failed to restart qovra-daemon"
  
  # Note: qovra-proxy is natively managed by Daemon, no systemctl interaction needed for it
  
  echo ""
  _log "Services reloaded successfully."
  echo ""
}

# =============================================================
# COMMAND: self-update
# =============================================================
cmd_self_update() {
  if [ "${EUID:-$(id -u)}" -ne 0 ]; then
    _error "qovra self-update requires root. Run: sudo qovra self-update"
  fi

  _section "Updating Qovra CLI"
  echo ""

  local latest
  latest=$(_latest_release "install" 2>/dev/null || echo "")

  if [ -z "${latest}" ]; then
    _error "Could not reach GitHub to check for updates."
  fi

  if [ "v${INSTALLER_VERSION}" = "${latest}" ] || [ "${INSTALLER_VERSION}" = "${latest}" ]; then
    _log "CLI is already at ${latest} — nothing to do."
    echo ""
    return 0
  fi

  _info "New version available: ${DIM}v${INSTALLER_VERSION}${NC} → ${GREEN}${latest}${NC}"
  _info "Downloading install.sh from Qovra/install@${latest}..."

  local install_url="https://raw.githubusercontent.com/${GITHUB_ORG}/install/${latest}/install.sh"
  wget -q "${install_url}" -O /tmp/qovra-install-new.sh \
    || _error "Failed to download install.sh from ${install_url}"

  chmod +x /tmp/qovra-install-new.sh

  _info "Re-generating CLI from new installer..."
  # Extraer y ejecutar solo la parte que genera el CLI,
  # pasando la bandera de repair y el version tag dinámico.
  REPAIR_CLI_ONLY=true INSTALLER_VERSION="${latest#v}" bash /tmp/qovra-install-new.sh 2>/dev/null \
    || _error "Failed to regenerate CLI from new installer."

  rm -f /tmp/qovra-install-new.sh

  _log "CLI updated to ${latest}"
  echo ""
}

# =============================================================
# ENTRYPOINT
# =============================================================
CMD="${1:-help}"
shift || true

case "${CMD}" in
  help|--help|-h)  cmd_help ;;
  status)          cmd_status ;;
  info)            cmd_info ;;
  check-update)    cmd_check_update ;;
  update)          cmd_update "${1:-}" ;;
  self-update)     cmd_self_update ;;
  reload)          cmd_reload ;;
  *)
    echo ""
    _error "Unknown command '${CMD}'. Run 'qovra help' for usage."
    ;;
esac
QOVRA_CLI_BODY

  chmod +x /usr/local/bin/qovra
  log "Qovra CLI installed → /usr/local/bin/qovra"
}

# ── Si solo estamos reparando el CLI, hacerlo y salir ─────────
if [ "${REPAIR_CLI_ONLY:-false}" = "true" ]; then
  install_cli
  echo ""
  log "CLI repaired. Run 'qovra help' to verify."
  echo ""
  exit 0
fi

# =============================================================
section "Step 1 — System update & base dependencies"
# =============================================================
apt update -y && apt upgrade -y
apt install -y \
  curl wget git ufw openssl unzip \
  software-properties-common \
  build-essential ca-certificates \
  lsb-release gnupg
if [ "$GOARCH" = "arm64" ]; then
  apt install -y qemu-user-static binfmt-support || true
  log "qemu-user-static installed for amd64 emulation on arm64"
fi
log "Base dependencies installed"

# =============================================================
section "Step 2 — Installing Go ${GO_VERSION}"
# =============================================================
if command -v go &> /dev/null && go version | grep -q "$GO_VERSION"; then
  log "Go ${GO_VERSION} already installed"
else
  info "Downloading Go ${GO_VERSION} for ${GOARCH}..."
  wget -q "https://go.dev/dl/go${GO_VERSION}.linux-${GOARCH}.tar.gz" -O /tmp/go.tar.gz
  rm -rf /usr/local/go
  tar -C /usr/local -xzf /tmp/go.tar.gz
  rm /tmp/go.tar.gz
  echo 'export PATH=$PATH:/usr/local/go/bin' >> /etc/profile
  export PATH=$PATH:/usr/local/go/bin
  log "Go ${GO_VERSION} installed"
fi

# =============================================================
section "Step 3 — Installing Java 21 (required for Hytale Server)"
# =============================================================
if java -version 2>&1 | grep -qE "21|25"; then
  log "Java already installed: $(java -version 2>&1 | head -1)"
else
  info "Installing Java 21..."
  apt update -y
  apt install -y openjdk-21-jre-headless || {
    info "openjdk-21 not available, trying Adoptium..."
    wget -qO - https://packages.adoptium.net/artifactory/api/gpg/key/public \
      | gpg --dearmor -o /etc/apt/trusted.gpg.d/adoptium.gpg
    echo "deb [signed-by=/etc/apt/trusted.gpg.d/adoptium.gpg] \
https://packages.adoptium.net/artifactory/deb $(lsb_release -cs) main" \
      > /etc/apt/sources.list.d/adoptium.list
    apt update -y
    apt install -y temurin-21-jdk
  }
  log "Java installed: $(java -version 2>&1 | head -1)"
fi

# =============================================================
section "Step 4 — Installing PostgreSQL ${PG_VERSION}"
# =============================================================
if ! command -v psql &> /dev/null; then
  info "Adding PostgreSQL repository..."
  curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc \
    | gpg --dearmor -o /etc/apt/trusted.gpg.d/postgresql.gpg
  echo "deb [signed-by=/etc/apt/trusted.gpg.d/postgresql.gpg] \
http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" \
    > /etc/apt/sources.list.d/pgdg.list
  apt update -y
  apt install -y postgresql-$PG_VERSION
  log "PostgreSQL ${PG_VERSION} installed"
else
  log "PostgreSQL already installed"
fi

systemctl enable --now postgresql

PG_HBA=$(sudo -u postgres psql -t -P format=unaligned -c "SHOW hba_file;")
info "pg_hba.conf: $PG_HBA"
if ! grep -qE "^host[[:space:]]+${PG_DB}[[:space:]]+${PG_USER}" "$PG_HBA" 2>/dev/null; then
  sed -i "/^host/i host    ${PG_DB}    ${PG_USER}    127.0.0.1/32    scram-sha-256" "$PG_HBA"
  sed -i "/^host/i host    ${PG_DB}    ${PG_USER}    ::1/128          scram-sha-256" "$PG_HBA"
  systemctl reload postgresql
  log "pg_hba.conf updated for password auth"
fi

sudo -u postgres psql -c \
  "CREATE USER $PG_USER WITH PASSWORD '$PG_PASSWORD';" 2>/dev/null \
  || warn "User $PG_USER already exists"
sudo -u postgres psql -c \
  "ALTER USER $PG_USER WITH PASSWORD '$PG_PASSWORD';" 2>/dev/null || true
sudo -u postgres psql -c \
  "CREATE DATABASE $PG_DB OWNER $PG_USER;" 2>/dev/null \
  || warn "Database $PG_DB already exists"
log "PostgreSQL configured (user: $PG_USER / db: $PG_DB)"

# =============================================================
section "Step 5 — Installing Hytale Downloader CLI"
# =============================================================
info "Downloading Hytale Downloader CLI..."
wget -q https://downloader.hytale.com/hytale-downloader.zip -O /tmp/hytale-downloader.zip
unzip -o /tmp/hytale-downloader.zip -d /tmp/hytale-downloader/
chmod +x /tmp/hytale-downloader/hytale-downloader-linux-amd64
mv /tmp/hytale-downloader/hytale-downloader-linux-amd64 /usr/local/bin/hytale-downloader
rm -rf /tmp/hytale-downloader /tmp/hytale-downloader.zip
log "hytale-downloader installed"

# =============================================================
section "Step 6 — Cloning repositories from github.com/${GITHUB_ORG}"
# =============================================================
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

for REPO in "${REPOS[@]}"; do
  TARGET_DIR="$INSTALL_DIR/$REPO"
  if [ -d "$TARGET_DIR/.git" ]; then
    info "$REPO already exists — pulling latest..."
    git -C "$TARGET_DIR" pull || warn "Could not pull $REPO, continuing with existing version"
  else
    if [ -d "$TARGET_DIR" ]; then
      warn "$REPO directory exists but is not a valid Git repo — removing it..."
      rm -rf "$TARGET_DIR"
    fi
    info "Cloning $REPO..."
    git clone "https://github.com/$GITHUB_ORG/$REPO.git" "$TARGET_DIR" \
      || error "Failed to clone $REPO from github.com/$GITHUB_ORG/$REPO"
  fi
  log "$REPO ready"
done

# =============================================================
section "Step 7 — Applying database schema"
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
section "Step 8 — Seeding database"
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
section "Step 9 — Generating .env configuration"
# =============================================================
cat > "$INSTALL_DIR/.env" << EOF
# ── Database ──────────────────────────────────────
PG_URL=postgresql://${PG_USER}:${PG_PASSWORD}@localhost:5432/${PG_DB}?sslmode=disable

# ── Auth ──────────────────────────────────────────
JWT_SECRET=${JWT_SECRET}
DAEMON_API_TOKEN=${DAEMON_API_TOKEN}

# ── Services ──────────────────────────────────────
PANEL_PORT=${BACKEND_PORT}
PANEL_FRONTEND_URL=http://${NODE_IP}:${BACKEND_PORT}
BACKEND_URL=http://localhost:${BACKEND_PORT}
DAEMON_PORT=${DAEMON_PORT}
PROXY_PORT=${PROXY_PORT}

# ── Panel static files (React SPA dist) ───────────
PANEL_DIST_PATH=${INSTALL_DIR}/panel/dist

# ── Node identity ─────────────────────────────────
NODE_IP=${NODE_IP}
NODE_HOSTNAME=${NODE_HOSTNAME}
ADMIN_USERNAME=${ADMIN_USERNAME}

# ── Hytale paths ──────────────────────────────────
PROXY_BINARY=/usr/local/bin/qovra-proxy
SERVERS_PATH=${INSTALL_DIR}/servers
PROXY_TEMPLATES_PATH=${INSTALL_DIR}/proxy/templates
EOF

grep -v '^#' "$INSTALL_DIR/.env" | grep -v '^$' > "$INSTALL_DIR/.env.service"
cp "$INSTALL_DIR/.env.service" "$INSTALL_DIR/backend/.env"
cp "$INSTALL_DIR/.env.service" "$INSTALL_DIR/daemon/.env"
cp "$INSTALL_DIR/.env.service" "$INSTALL_DIR/proxy/.env"

mkdir -p "$INSTALL_DIR/servers"
log ".env generated and distributed"

mkdir -p "$INSTALL_DIR/proxy/config"
cat > "$INSTALL_DIR/proxy/config/config.json" << EOF
{
    "listen": ":${PROXY_PORT}",
    "session_timeout": 7200,
    "metrics_listen": ":9090",
    "handlers": [
        {
            "type": "ip-ratelimit",
            "config": {
                "max_conns_per_ip": 10,
                "refill_per_sec": 1
            }
        },
        {
            "type": "ip-connlimit",
            "config": {
                "max_conns_per_ip": 5,
                "burst": 3
            }
        },
        {
            "type": "sni-router",
            "config": {
                "routes": {
                    "localhost": ["127.0.0.1:5520", "127.0.0.1:5522"]
                }
            }
        },
        {
            "type": "forwarder"
        }
    ]
}
EOF
log "Proxy config generated"

# =============================================================
section "Step 10 — Downloading pre-built binaries from GitHub Releases"
# =============================================================
info "Architecture: $ARCH → $GOARCH"

# ── Detect latest release tag per component and download ──────
for BINARY in backend daemon proxy; do
  info "Fetching latest release for ${BINARY}..."
  RELEASE_TAG=$(curl -sf --max-time 10 \
    "https://api.github.com/repos/${GITHUB_ORG}/${BINARY}/releases/latest" \
    | grep '"tag_name"' \
    | sed 's/.*"tag_name": *"\([^"]*\)".*/\1/' \
    || echo "")

  if [ -z "$RELEASE_TAG" ]; then
    error "Could not determine latest release for ${BINARY}. Check GitHub connectivity."
  fi

  BINARY_NAME="qovra-${BINARY}-linux-${GOARCH}"
  DOWNLOAD_URL="https://github.com/${GITHUB_ORG}/${BINARY}/releases/download/${RELEASE_TAG}/${BINARY_NAME}"

  info "Downloading qovra-${BINARY} ${RELEASE_TAG}..."
  wget -q "$DOWNLOAD_URL" -O "/usr/local/bin/qovra-${BINARY}" \
    || error "Failed to download ${BINARY} from ${DOWNLOAD_URL}"

  chmod +x "/usr/local/bin/qovra-${BINARY}"

  # Guardar versión instalada (sin 'v')
  echo "${BINARY}=${RELEASE_TAG#v}" >> "$INSTALL_DIR/.versions"
  log "qovra-${BINARY} ${RELEASE_TAG} installed"
done

# =============================================================
section "Step 11 — Downloading pre-built Panel (React)"
# =============================================================
info "Fetching latest release for panel..."
PANEL_TAG=$(curl -sf --max-time 10 \
  "https://api.github.com/repos/${GITHUB_ORG}/panel/releases/latest" \
  | grep '"tag_name"' \
  | sed 's/.*"tag_name": *"\([^"]*\)".*/\1/' \
  || echo "")

if [ -z "$PANEL_TAG" ]; then
  error "Could not determine latest release for panel. Check GitHub connectivity."
fi

PANEL_URL="https://github.com/${GITHUB_ORG}/panel/releases/download/${PANEL_TAG}/qovra-panel.tar.gz"
PANEL_DIST="$INSTALL_DIR/panel/dist"

info "Downloading pre-built panel ${PANEL_TAG}..."
mkdir -p "$PANEL_DIST"
wget -q "$PANEL_URL" -O /tmp/qovra-panel.tar.gz \
  || error "Failed to download panel from $PANEL_URL"

info "Extracting panel to $PANEL_DIST..."
tar -xzf /tmp/qovra-panel.tar.gz -C "$PANEL_DIST"
rm -f /tmp/qovra-panel.tar.gz

echo "panel=${PANEL_TAG#v}" >> "$INSTALL_DIR/.versions"
log "Panel ${PANEL_TAG} extracted → $PANEL_DIST"

# =============================================================
section "Step 12 — Installing systemd services"
# =============================================================
cat > /etc/systemd/system/qovra-backend.service << EOF
[Unit]
Description=Qovra Backend (Orchestrator + Panel)
After=network.target postgresql.service
Requires=postgresql.service

[Service]
Type=simple
User=root
WorkingDirectory=${INSTALL_DIR}/backend
EnvironmentFile=${INSTALL_DIR}/backend/.env
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
WorkingDirectory=${INSTALL_DIR}/daemon
EnvironmentFile=${INSTALL_DIR}/daemon/.env
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
WorkingDirectory=${INSTALL_DIR}/proxy
EnvironmentFile=${INSTALL_DIR}/proxy/.env
ExecStart=/usr/local/bin/qovra-proxy -config ${INSTALL_DIR}/proxy/config/config.json
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
section "Step 13 — Configuring firewall (UFW)"
# =============================================================
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp               comment 'SSH'
ufw allow ${BACKEND_PORT}/tcp  comment 'Qovra Backend API + Panel'
ufw allow ${DAEMON_PORT}/tcp   comment 'Qovra Daemon API'
ufw allow ${PROXY_PORT}/udp    comment 'Hytale Proxy QUIC'
ufw --force enable
log "Firewall configured"

# =============================================================
section "Step 14 — Installing Qovra CLI"
# =============================================================
install_cli

# =============================================================
section "Step 15 — Verifying services"
# =============================================================
sleep 3
ALL_OK=true
for SVC in qovra-backend qovra-daemon qovra-proxy; do
  STATUS=$(systemctl is-active "$SVC" || true)
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
echo -e "  🖥️  Panel Web UI:     ${YELLOW}http://${NODE_IP}:${BACKEND_PORT}/${NC}"
echo -e "  🔌 Backend API:      ${YELLOW}http://${NODE_IP}:${BACKEND_PORT}/api/${NC}"
echo -e "  ⚙️  Daemon API:       ${YELLOW}http://localhost:${DAEMON_PORT}${NC}"
echo -e "  🎮 Proxy (QUIC):     ${YELLOW}UDP ${PROXY_PORT}${NC}"
echo -e "  👤 Admin user:       ${YELLOW}${ADMIN_USERNAME} (${ADMIN_EMAIL})${NC}"
echo -e "  🖧  Node registered: ${YELLOW}${NODE_HOSTNAME} — ${NODE_RAM_MB}MB RAM${NC}"
echo ""
echo -e "  🔐 Credentials:      ${YELLOW}${INSTALL_DIR}/.env${NC}"
echo -e "  📋 CLI:              ${YELLOW}qovra help${NC}"
echo ""

if [ "$ALL_OK" = false ]; then
  echo -e "${YELLOW}  ⚠️  One or more services failed to start.${NC}"
  echo -e "${YELLOW}     Check logs with: journalctl -u <service> -n 50${NC}"
  echo ""
fi

echo -e "${YELLOW}  Useful commands:${NC}"
echo -e "    qovra status"
echo -e "    qovra info"
echo -e "    qovra check-update"
echo -e "    qovra update all"
echo -e "    qovra self-update"
echo ""
echo -e "${RED}  ⚠️  Keep your .env file secure. Never commit it to Git.${NC}"
echo ""