#!/usr/bin/env bash
#
# WordPress Framework Installer
#
# Usage: ./install.sh <app_dir> <site_name> <site_url>
#
# This script is called by site-create.sh when installing the WordPress framework.
#

set -euo pipefail

# Arguments
APP_DIR="$1"
SITE_NAME="$2"
SITE_URL="$3"

# Get script directory (for accessing config files)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load common library if available
if [[ -f "$SCRIPT_DIR/../../lib/common.sh" ]]; then
    source "$SCRIPT_DIR/../../lib/common.sh"
else
    # Fallback logging functions
    log_info()  { echo "[INFO] $1"; }
    log_ok()    { echo "[OK] $1"; }
    log_error() { echo "[ERROR] $1" >&2; }
fi

# =============================================================================
# DOWNLOAD WORDPRESS
# =============================================================================

log_info "Downloading WordPress from wordpress.org..."

tmp_file="/tmp/wordpress-$$.zip"

if ! curl -sL "https://wordpress.org/latest.zip" -o "$tmp_file"; then
    log_error "Failed to download WordPress"
    log_info "You can download it manually: curl -O https://wordpress.org/latest.zip"
    exit 1
fi

log_ok "WordPress downloaded"

# =============================================================================
# EXTRACT
# =============================================================================

log_info "Extracting WordPress..."

# Extract to app directory
unzip -q "$tmp_file" -d "$APP_DIR"

# Move files from wordpress/ subdirectory to public/
mkdir -p "$APP_DIR/public"
mv "$APP_DIR/wordpress"/* "$APP_DIR/public/"
rmdir "$APP_DIR/wordpress"

# Clean up
rm -f "$tmp_file"

log_ok "WordPress extracted to app/public/"

# =============================================================================
# CONFIGURE
# =============================================================================

log_info "Applying configuration..."

# Copy our custom wp-config.php
if [[ -f "$SCRIPT_DIR/public/wp-config.php" ]]; then
    cp -f "$SCRIPT_DIR/public/wp-config.php" "$APP_DIR/public/"

    # Replace placeholders
    sed_inplace "s|SITE_NAME|$SITE_NAME|g" "$APP_DIR/public/wp-config.php"
    sed_inplace "s|SITE_URL|$SITE_URL|g" "$APP_DIR/public/wp-config.php"

    log_ok "wp-config.php configured"
fi

# Copy .htaccess if exists
if [[ -f "$SCRIPT_DIR/public/.htaccess" ]]; then
    cp -f "$SCRIPT_DIR/public/.htaccess" "$APP_DIR/public/"
    log_ok ".htaccess configured"
fi

# =============================================================================
# POST-INSTALL INFO
# =============================================================================

log_ok "WordPress installation complete"
log_info "Next steps:"
echo "  1. Generate security keys: https://api.wordpress.org/secret-key/1.1/salt/"
echo "  2. Update keys in: $APP_DIR/public/wp-config.php"
echo "  3. Visit your site to complete WordPress setup"
