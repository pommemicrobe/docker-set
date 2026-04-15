#!/usr/bin/env bash
#
# framework.sh - Framework installation for docker-set
#
# Usage: source "$(dirname "$0")/../lib/framework.sh"
# Requires: common.sh, site.sh to be sourced first
#
# Each framework has a self-contained install.sh that runs inside the site container.
# Flow: build image → start container → docker cp + docker exec → cleanup
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

# Check if compose ports are available
# Usage: _has_port_conflict <compose_file>
# Returns: 0 if a conflict exists, 1 if all ports are free
_has_port_conflict() {
    local compose_file="$1"

    local ports
    ports=$(grep -Eo '"([0-9]+):[0-9]+"' "$compose_file" 2>/dev/null | grep -Eo '^"[0-9]+' | tr -d '"')

    for port in $ports; do
        if ! check_port_conflict "$port" >/dev/null 2>&1; then
            return 0
        fi
    done

    return 1
}

# Install a framework into a site's app directory
# Usage: install_framework <framework_name> <app_dir> <site_name> <site_url> <runtime_version>
#
# Steps:
#   1. Build the image via docker compose build
#   2. Check ports: if free → docker compose up; if busy → docker run (no ports)
#   3. docker cp framework files + docker exec install.sh
#   4. Clean up container
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
    # Node templates: ./app:/app        → container_app_dir=/app
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

    # Start the container
    # Check if published ports are already in use (standalone templates)
    # If ports are free → docker compose up
    # If ports are busy → docker run without port bindings
    local use_tmp_container=false
    local tmp_container="${site_name}-framework-install"

    log_info "Starting container for installation..."
    if _has_port_conflict "$compose_file"; then
        log_warn "Ports already in use, starting temporary container without port bindings..."
        use_tmp_container=true

        local image_name
        image_name=$(cd "$site_dir" && docker compose config --images 2>/dev/null | head -1)
        if [[ -z "$image_name" ]]; then
            log_error "Could not determine built image name"
            return 1
        fi

        local abs_app_dir
        abs_app_dir=$(cd "$app_dir" && pwd)

        if ! docker run -d \
            --name "$tmp_container" \
            -v "$abs_app_dir:$container_app_dir" \
            "$image_name" sleep 3600 >/dev/null; then
            log_error "Failed to start temporary container"
            return 1
        fi
    else
        if ! (cd "$site_dir" && docker compose up -d 2>&1); then
            log_error "Failed to start container"
            return 1
        fi
    fi

    # Determine which container name to use for cp/exec
    local target_container="$site_name"
    if [[ "$use_tmp_container" == true ]]; then
        target_container="$tmp_container"
    fi

    # Copy framework files into the container
    log_info "Copying framework files into container..."
    if ! docker cp "$framework_dir/." "$target_container:/tmp/.framework"; then
        log_error "Failed to copy framework files"
        _framework_cleanup "$use_tmp_container" "$tmp_container" "$site_dir"
        return 1
    fi

    # Clean the app directory (base images may include default files like index.php)
    docker exec "$target_container" sh -c "rm -rf ${container_app_dir:?}/* ${container_app_dir}/.[!.]* 2>/dev/null || true"

    # Execute the install script
    log_info "Running framework installer in container..."
    if ! docker exec \
        -e SITE_NAME="$site_name" \
        -e SITE_URL="$site_url" \
        -e APP_DIR="$container_app_dir" \
        "$target_container" sh /tmp/.framework/install.sh; then
        log_error "Framework installation failed"
        _framework_cleanup "$use_tmp_container" "$tmp_container" "$site_dir"
        return 1
    fi

    # Clean up container
    _framework_cleanup "$use_tmp_container" "$tmp_container" "$site_dir"

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

# Clean up after framework installation
# Usage: _framework_cleanup <use_tmp_container> <tmp_container_name> <site_dir>
_framework_cleanup() {
    local use_tmp="$1"
    local tmp_name="$2"
    local site_dir="$3"

    if [[ "$use_tmp" == true ]]; then
        docker rm -f "$tmp_name" >/dev/null 2>&1 || true
    else
        (cd "$site_dir" && docker compose down 2>/dev/null) || true
    fi
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
