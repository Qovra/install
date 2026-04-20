#!/bin/bash
# =============================================================
#  Qovra - Hotfix Script
#  Aplica los fixes sin reinstalar desde cero.
#
#  Fixes incluidos:
#    1. Reconstruye el panel con API_BASE relativo (/api)
#    2. Recompila el backend con soporte para servir el panel SPA
#    3. Agrega PANEL_DIST_PATH al .env
#    4. Reinicia los servicios
#
#  Uso: sudo bash hotfix.sh
# =============================================================

set -e

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

if [ "$EUID" -ne 0 ]; then
  error "Please run as root: sudo bash hotfix.sh"
fi

INSTALL_DIR="/opt/qovra"

if [ ! -d "$INSTALL_DIR" ]; then
  error "No Qovra installation found at $INSTALL_DIR. Run install.sh first."
fi

export PATH=$PATH:/usr/local/go/bin

# =============================================================
section "Fix 1 — Patching Panel API_BASE"
# =============================================================
PANEL_SRC="$INSTALL_DIR/panel/src"

info "Pulling latest panel source..."
git -C "$INSTALL_DIR/panel" pull || warn "Could not pull, using existing source"

info "Patching Login.jsx..."
sed -i "s|const API_BASE = 'http://127.0.0.1:3000/api'|const API_BASE = '/api'|g" \
  "$PANEL_SRC/Login.jsx"

info "Patching Dashboard.jsx..."
sed -i "s|const API_BASE = 'http://127.0.0.1:3000/api'|const API_BASE = '/api'|g" \
  "$PANEL_SRC/Dashboard.jsx"

log "API_BASE patched in Login.jsx and Dashboard.jsx"

# =============================================================
section "Fix 2 — Rebuilding Panel (React)"
# =============================================================
cd "$INSTALL_DIR/panel"

if ! command -v pnpm &>/dev/null; then
  info "Installing pnpm..."
  npm install -g pnpm
fi

info "Installing dependencies..."
pnpm install --frozen-lockfile

info "Building panel..."
pnpm build

PANEL_DIST="$INSTALL_DIR/panel/dist"
if [ ! -f "$PANEL_DIST/index.html" ]; then
  error "Build failed: $PANEL_DIST/index.html not found"
fi

log "Panel built → $PANEL_DIST"

# =============================================================
section "Fix 3 — Recompiling Backend (Go)"
# =============================================================
cd "$INSTALL_DIR/backend"

info "Pulling latest backend source..."
git -C "$INSTALL_DIR/backend" pull || warn "Could not pull, using existing source"

if ! command -v go &>/dev/null; then
  error "Go not found. Install Go first or re-run install.sh"
fi

info "Applying SPA handler patch to main.go..."

# Patch: replace the hardcoded API_BASE in main.go to serve static files
# This replaces the binary in-place without needing a GitHub release
cat > /tmp/main_patch.py << 'PYEOF'
import sys

content = open(sys.argv[1]).read()

# Check if SPA handler already applied
if 'spaHandler' in content:
    print("SPA handler already present, skipping patch")
    sys.exit(0)

# Inject spaHandler before corsMiddleware call
old = '\t// Allow extremely forgiving CORS to connect our React cleanly\n\thandler := corsMiddleware(mux)'
new = '''\t// ── Static Panel (React SPA) ─────────────────────────────────────────────
\t// PANEL_DIST_PATH from .env; fallback to /opt/qovra/panel/dist.
\tdistPath := os.Getenv("PANEL_DIST_PATH")
\tif distPath == "" {
\t\tdistPath = "/opt/qovra/panel/dist"
\t}
\tmux.HandleFunc("/", spaHandler(distPath))

\t// Allow extremely forgiving CORS to connect our React cleanly
\thandler := corsMiddleware(mux)'''

content = content.replace(old, new)

# Add import for path/filepath if missing
if '"path/filepath"' not in content:
    content = content.replace(
        '"os"',
        '"os"\n\t"path/filepath"'
    )

# Append spaHandler function before corsMiddleware function
spa_func = '''
// spaHandler serves static files and falls back to index.html for SPA routing.
func spaHandler(distPath string) http.HandlerFunc {
\tfs := http.FileServer(http.Dir(distPath))
\treturn func(w http.ResponseWriter, r *http.Request) {
\t\tabsPath := filepath.Join(distPath, filepath.Clean("/"+r.URL.Path))
\t\tinfo, err := os.Stat(absPath)
\t\tif os.IsNotExist(err) || (err == nil && info.IsDir()) {
\t\t\thttp.ServeFile(w, r, filepath.Join(distPath, "index.html"))
\t\t\treturn
\t\t}
\t\tfs.ServeHTTP(w, r)
\t}
}

'''
content = content.replace('func corsMiddleware', spa_func + 'func corsMiddleware')

open(sys.argv[1], 'w').write(content)
print("Patch applied successfully")
PYEOF

python3 /tmp/main_patch.py "$INSTALL_DIR/backend/main.go"
rm -f /tmp/main_patch.py

info "Compiling backend..."
cd "$INSTALL_DIR/backend"
go build -ldflags="-s -w" -o /usr/local/bin/qovra-backend .
log "Backend compiled → /usr/local/bin/qovra-backend"

# =============================================================
section "Fix 4 — Updating .env with PANEL_DIST_PATH"
# =============================================================
ENV_FILE="$INSTALL_DIR/.env"
ENV_SERVICE="$INSTALL_DIR/.env.service"
ENV_BACKEND="$INSTALL_DIR/backend/.env"

if ! grep -q "PANEL_DIST_PATH" "$ENV_FILE" 2>/dev/null; then
  echo "" >> "$ENV_FILE"
  echo "# ── Panel static files (React SPA dist) ───────────" >> "$ENV_FILE"
  echo "PANEL_DIST_PATH=${INSTALL_DIR}/panel/dist"            >> "$ENV_FILE"
  log "PANEL_DIST_PATH added to $ENV_FILE"
else
  log "PANEL_DIST_PATH already in .env"
fi

# Regenerar .env.service y backend/.env limpios
grep -v '^#' "$ENV_FILE" | grep -v '^$' > "$ENV_SERVICE"
cp "$ENV_SERVICE" "$ENV_BACKEND"
log ".env.service and backend/.env updated"

# =============================================================
section "Fix 5 — Restarting services"
# =============================================================
info "Restarting qovra-backend..."
systemctl restart qovra-backend
sleep 2

STATUS=$(systemctl is-active qovra-backend || true)
if [ "$STATUS" = "active" ]; then
  log "qovra-backend is running ✓"
else
  warn "qovra-backend status: $STATUS"
  echo ""
  warn "Check logs with: journalctl -u qovra-backend -n 50"
fi

# =============================================================
section "✅  Hotfix complete"
# =============================================================
NODE_IP=$(grep 'NODE_IP=' "$ENV_FILE" | cut -d= -f2 | head -1)
BACKEND_PORT=$(grep 'PANEL_PORT=' "$ENV_FILE" | cut -d= -f2 | head -1)
BACKEND_PORT=${BACKEND_PORT:-3000}

echo ""
echo -e "  🌐 Panel Web UI:  ${YELLOW}http://${NODE_IP}:${BACKEND_PORT}/${NC}"
echo -e "  🔌 API:           ${YELLOW}http://${NODE_IP}:${BACKEND_PORT}/api/${NC}"
echo ""
echo -e "  ${CYAN}Open the URL above in your browser to access the panel.${NC}"
echo -e "  ${CYAN}Use the admin credentials you set during installation.${NC}"
echo ""
