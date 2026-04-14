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

    # Determine the container mount point for app/ by reading the compose volume
    # PHP templates: ./app:/app/public  → container_app_dir=/app/public
    # Node templates: ./app:/app        → container_app_dir=/app
    local container_app_dir="/app"
    local compose_file="$site_dir/compose.yaml"
    if [[ -f "$compose_file" ]]; then
        local mount_target
        mount_target=$(grep -E '^\s*-\s*\./app:' "$compose_file" | sed 's/.*\.\/app://' | xargs)
        if [[ -n "$mount_target" ]]; then
            container_app_dir="$mount_target"
        fi
    fi

    # Copy framework files to app/.framework/
    cp -r "$framework_dir" "$app_dir/.framework"

    # Run install script inside the container
    log_info "Running framework installer in container..."
    if ! (cd "$site_dir" && docker compose run --rm \
        -e SITE_NAME="$site_name" -e SITE_URL="$site_url" \
        "$site_name" sh "$container_app_dir/.framework/install.sh"); then
        log_error "Framework installation failed"
        rm -rf "$app_dir/.framework"
        return 1
    fi

    # Clean up
    rm -rf "$app_dir/.framework"

    # Adjust compose.yaml for framework-specific server root
    local server_root
    server_root=$(get_framework_server_root "$framework_name")
    if [[ -n "$server_root" ]]; then
        local compose_file="$site_dir/compose.yaml"
        if grep -q "SERVER_ROOT=" "$compose_file" 2>/dev/null; then
            sed_inplace "s|SERVER_ROOT=/app/public|SERVER_ROOT=$server_root|g" "$compose_file"
            log_ok "SERVER_ROOT adjusted to $server_root"
        fi
    fi

    log_ok "Framework '$framework_name' installed"
}

# Get the server root path for a framework (inside the container)
# Usage: get_framework_server_root <framework_name>
# Returns: server root path, or empty string if no adjustment needed
get_framework_server_root() {
    local framework_name="$1"
    case "$framework_name" in
        laravel)    echo "/app/public/public" ;;
        wordpress)  echo "" ;; # WordPress copies files directly into public/
        *)          echo "" ;;
    esac
}
