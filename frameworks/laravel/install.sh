#!/usr/bin/env bash
#
# Laravel Framework Installer
#
# Usage: ./install.sh <app_dir> <site_name> <site_url>
#
# This script is called by site-create.sh when installing the Laravel framework.
# It uses Docker to run Composer, so no local Composer installation is required.
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
# INSTALL LARAVEL
# =============================================================================

log_info "Installing Laravel via Composer (Docker)..."

# Use Docker to run Composer - no local installation required
# The composer image runs as root, matching the container user
if ! docker run --rm -v "$APP_DIR:/app" -w /app composer:latest \
    create-project --prefer-dist --no-interaction laravel/laravel . 2>&1; then
    log_error "Failed to install Laravel"
    exit 1
fi

log_ok "Laravel installed"

# =============================================================================
# CONFIGURE
# =============================================================================

log_info "Configuring Laravel..."

# Update .env file
ENV_FILE="$APP_DIR/.env"
if [[ -f "$ENV_FILE" ]]; then
    # App settings
    sed_inplace "s|APP_NAME=Laravel|APP_NAME=$SITE_NAME|g" "$ENV_FILE"
    sed_inplace "s|APP_URL=http://localhost|APP_URL=https://$SITE_URL|g" "$ENV_FILE"

    # Database settings (use docker-set MySQL container)
    DB_NAME="${SITE_NAME//-/_}_db"
    DB_USER="${SITE_NAME//-/_}"

    sed_inplace "s|DB_CONNECTION=sqlite|DB_CONNECTION=mysql|g" "$ENV_FILE"
    sed_inplace "s|# DB_HOST=127.0.0.1|DB_HOST=mysql|g" "$ENV_FILE"
    sed_inplace "s|# DB_PORT=3306|DB_PORT=3306|g" "$ENV_FILE"
    sed_inplace "s|# DB_DATABASE=laravel|DB_DATABASE=$DB_NAME|g" "$ENV_FILE"
    sed_inplace "s|# DB_USERNAME=root|DB_USERNAME=$DB_USER|g" "$ENV_FILE"
    sed_inplace "s|# DB_PASSWORD=|DB_PASSWORD=|g" "$ENV_FILE"

    log_ok ".env configured"
fi

# =============================================================================
# POST-INSTALL INFO
# =============================================================================

log_ok "Laravel installation complete"
log_info "Next steps:"
echo "  1. Update DB_PASSWORD in: $APP_DIR/.env"
echo "  2. Run migrations: docker exec -it $SITE_NAME php artisan migrate"
echo "  3. Visit your site: https://$SITE_URL"
