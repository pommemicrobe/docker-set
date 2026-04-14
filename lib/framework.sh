#!/usr/bin/env bash
#
# framework.sh - Framework installation for docker-set
#
# Usage: source "$(dirname "$0")/../lib/framework.sh"
# Requires: common.sh to be sourced first
#
# Each framework has a self-contained install.sh that runs inside the site container.
# Flow: copy framework dir to app/.framework/ → docker compose run → cleanup
#

# =============================================================================
# FRAMEWORK DISCOVERY
# =============================================================================

# Get available frameworks
# Usage: get_frameworks
get_frameworks() {
    local frameworks=()
    for dir in "$FRAMEWORKS_DIR"/*/; do
        if [[ -d "$dir" && -n "$(ls -A "$dir" 2>/dev/null)" ]]; then
            frameworks+=("$(basename "$dir")")
        fi
    done
    echo "${frameworks[@]}"
}

# =============================================================================
# FRAMEWORK INSTALLATION
# =============================================================================

# Install a framework into a site's app directory
# Usage: install_framework <framework_name> <app_dir> <site_name> <site_url> <runtime_version>
#
# Steps:
#   1. Build the site image
#   2. Copy framework files to app/.framework/
#   3. Run install.sh inside the container (via docker compose run)
#   4. Clean up app/.framework/
install_framework() {
    local framework_name="$1"
    local app_dir="$2"
    local site_name="$3"
    local site_url="$4"
    local runtime_version="${5:-}"

    local framework_dir="$FRAMEWORKS_DIR/$framework_name"
    local install_script="$framework_dir/install.sh"
    local site_dir
    site_dir="$(dirname "$app_dir")"

    if [[ ! -f "$install_script" ]]; then
        log_error "No install.sh found for framework '$framework_name'"
        return 1
    fi

    log_info "Installing framework '$framework_name'..."
    mkdir -p "$app_dir"

    # Build image (--pull ensures latest base image for the selected version)
    log_info "Building image..."
    if ! (cd "$site_dir" && docker compose build --pull --quiet 2>&1); then
        log_error "Failed to build image"
        return 1
    fi

    # Copy framework files to app/.framework/
    cp -r "$framework_dir" "$app_dir/.framework"

    # Run install script inside the container
    log_info "Running framework installer in container..."
    if ! (cd "$site_dir" && docker compose run --rm \
        -e SITE_NAME="$site_name" -e SITE_URL="$site_url" \
        "$site_name" sh /app/.framework/install.sh); then
        log_error "Framework installation failed"
        rm -rf "$app_dir/.framework"
        return 1
    fi

    # Clean up
    rm -rf "$app_dir/.framework"

    log_ok "Framework '$framework_name' installed"
}
