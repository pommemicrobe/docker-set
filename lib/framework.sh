#!/usr/bin/env bash
#
# framework.sh - Framework installation for docker-set
#
# Usage: source "$(dirname "$0")/../lib/framework.sh"
# Requires: common.sh, site.sh to be sourced first
#
# Each framework has a self-contained install.sh that runs inside the site container.
# Flow: build image → docker run temp container (with sleep) → docker cp + exec → rm
#
# We always use a temporary container with `sleep` instead of the image's default CMD
# because the CMD typically expects project files (package.json, etc.) that don't
# exist yet. This also avoids port binding conflicts on standalone templates.
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
#   1. Build the image via docker compose build
#   2. Start a temporary container with `sleep` (no ports, overrides CMD)
#   3. docker cp framework files + docker exec install.sh
#   4. Remove the temporary container
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
    local compose_file="$site_dir/compose.yaml"

    if [[ ! -f "$install_script" ]]; then
        log_error "No install.sh found for framework '$framework_name'"
        return 1
    fi

    log_info "Installing framework '$framework_name'..."
    mkdir -p "$app_dir"

    # Determine the container mount point for app/
    # PHP templates: ./app:/app/public  → container_app_dir=/app/public
    # Node/Bun templates: ./app:/app    → container_app_dir=/app
    local container_app_dir="/app"
    if [[ -f "$compose_file" ]]; then
        local mount_target
        mount_target=$(grep -E '^\s*-\s*\./app:' "$compose_file" | sed 's/.*\.\/app://' | xargs)
        if [[ -n "$mount_target" ]]; then
            container_app_dir="$mount_target"
        fi
    fi

    # Build image
    log_info "Building image..."
    if ! (cd "$site_dir" && docker compose build --pull --quiet 2>&1); then
        log_error "Failed to build image"
        return 1
    fi

    # Get the built image name
    local image_name
    image_name=$(cd "$site_dir" && docker compose config --images 2>/dev/null | head -1)
    if [[ -z "$image_name" ]]; then
        log_error "Could not determine built image name"
        return 1
    fi

    # Start a temporary container with `sleep` to override the image's default CMD
    # This avoids: (a) CMD failing on missing project files, (b) port binding conflicts
    local tmp_container="${site_name}-framework-install"
    local abs_app_dir
    abs_app_dir=$(cd "$app_dir" && pwd)

    log_info "Starting temporary container..."
    if ! docker run -d \
        --name "$tmp_container" \
        -v "$abs_app_dir:$container_app_dir" \
        "$image_name" sleep 3600 >/dev/null; then
        log_error "Failed to start temporary container"
        return 1
    fi

    # Copy framework files into the container
    log_info "Copying framework files into container..."
    if ! docker cp "$framework_dir/." "$tmp_container:/tmp/.framework"; then
        log_error "Failed to copy framework files"
        docker rm -f "$tmp_container" >/dev/null 2>&1 || true
        return 1
    fi

    # Clean the app directory (base images may include default files like index.php)
    docker exec "$tmp_container" sh -c "rm -rf ${container_app_dir:?}/* ${container_app_dir}/.[!.]* 2>/dev/null || true"

    # Execute the install script
    log_info "Running framework installer in container..."
    if ! docker exec \
        -e SITE_NAME="$site_name" \
        -e SITE_URL="$site_url" \
        -e APP_DIR="$container_app_dir" \
        "$tmp_container" sh /tmp/.framework/install.sh; then
        log_error "Framework installation failed"
        docker rm -f "$tmp_container" >/dev/null 2>&1 || true
        return 1
    fi

    # Remove the temporary container
    docker rm -f "$tmp_container" >/dev/null 2>&1 || true

    # Adjust compose.yaml for framework-specific server root
    local server_root
    server_root=$(get_framework_server_root "$framework_name")
    if [[ -n "$server_root" ]]; then
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
