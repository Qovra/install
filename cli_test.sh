
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
  _svc_line "qovra-proxy"   "proxy"

  # Panel: no tiene servicio propio
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

  # Detener servicio, reemplazar, reiniciar
  local svc="qovra-${comp}"
  _info "Restarting ${svc}..."
  systemctl stop "${svc}"  2>/dev/null || true
  mv "${dest}.tmp" "${dest}"
  chmod +x "${dest}"
  systemctl start "${svc}" 2>/dev/null || _warn "${svc} failed to start — check: journalctl -u ${svc} -n 50"

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
  # pasando la bandera de repair para no re-instalar servicios.
  REPAIR_CLI_ONLY=true bash /tmp/qovra-install-new.sh 2>/dev/null \
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
  *)
    echo ""
    _error "Unknown command '${CMD}'. Run 'qovra help' for usage."
    ;;
esac
