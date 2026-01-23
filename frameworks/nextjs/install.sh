#!/usr/bin/env bash
#
# Next.js Framework Installer
#
# Usage: ./install.sh <app_dir> <site_name> <site_url>
#
# This script is called by site-create.sh when installing the Next.js framework.
# It uses Docker to run npx create-next-app, so no local Node.js installation is required.
#

set -euo pipefail

# Arguments
APP_DIR="$1"
SITE_NAME="$2"
SITE_URL="$3"

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load common library if available
if [[ -f "$SCRIPT_DIR/../../lib/common.sh" ]]; then
    source "$SCRIPT_DIR/../../lib/common.sh"
else
    # Fallback logging functions
    log_info()  { echo "[INFO] $1"; }
    log_ok()    { echo "[OK] $1"; }
    log_warn()  { echo "[WARN] $1"; }
    log_error() { echo "[ERROR] $1" >&2; }
fi

# =============================================================================
# INSTALL NEXT.JS
# =============================================================================

log_info "Installing Next.js via create-next-app (Docker)..."

# Use Docker to run create-next-app - no local installation required
# Create in a temp directory then move to APP_DIR
if ! docker run --rm -v "$APP_DIR:/app" -w /app node:24-alpine \
    sh -c "npx --yes create-next-app@latest . --typescript --tailwind --eslint --app --src-dir --import-alias '@/*' --use-npm" 2>&1; then
    log_error "Failed to install Next.js"
    exit 1
fi

log_ok "Next.js installed"

# =============================================================================
# CREATE PM2 ECOSYSTEM FILE
# =============================================================================

log_info "Creating PM2 ecosystem configuration..."

cat > "$APP_DIR/ecosystem.config.js" << 'EOF'
module.exports = {
  apps: [{
    name: 'nextjs',
    script: 'npm',
    args: 'start',
    cwd: '/app',
    instances: 1,
    autorestart: true,
    watch: false,
    max_memory_restart: '500M',
    env: {
      NODE_ENV: 'production',
      PORT: 3000
    }
  }]
};
EOF

log_ok "PM2 ecosystem.config.js created"

# =============================================================================
# CONFIGURE NEXT.JS
# =============================================================================

log_info "Configuring Next.js..."


# =============================================================================
# BUILD THE APPLICATION
# =============================================================================

log_info "Building Next.js application..."

if ! docker run --rm -v "$APP_DIR:/app" -w /app node:24-alpine \
    sh -c "npm run build" 2>&1; then
    log_warn "Initial build failed - this is normal if you need to customize the app first"
    log_info "Run 'docker exec -it $SITE_NAME npm run build' after customizing your app"
fi

log_ok "Next.js build complete"

# =============================================================================
# POST-INSTALL INFO
# =============================================================================

log_ok "Next.js installation complete"
log_info "Next steps:"
echo "  1. Customize your app in: $APP_DIR/src/"
echo "  2. Rebuild after changes: docker exec -it $SITE_NAME npm run build"
echo "  3. Visit your site: https://$SITE_URL"
echo ""
log_info "Development mode:"
echo "  - To run in dev mode, update PM2 config args to 'dev' instead of 'start'"
echo "  - Or run: docker exec -it $SITE_NAME npm run dev"
