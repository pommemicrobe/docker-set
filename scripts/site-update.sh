#!/usr/bin/env bash
#
# site-update.sh - Update an existing site's container
#
# Rebuilds the image with a freshly pulled base image and recreates the
# container. Can also change the runtime version and resource limits.
#
# Usage:
#   ./scripts/site-update.sh                      # Interactive mode
#   ./scripts/site-update.sh <name> [options]     # Direct mode
#   ./scripts/site-update.sh --all [--no-cache]   # Rebuild every site
#

# Load libraries
source "$(dirname "$0")/../lib/common.sh"
source "$(dirname "$0")/../lib/site.sh"

# =============================================================================
# HELP
# =============================================================================

show_help() {
    echo "Usage: $0 [site-name] [options]"
    echo ""
    echo "Update a site's container: rebuild its image with a freshly pulled"
    echo "base image and recreate the container. Optionally change the runtime"
    echo "version or resource limits first."
    echo ""
    echo "Run without arguments for interactive mode."
    echo ""
    echo "Options:"
    echo "  --php-version <ver>   Change PHP version (${PHP_VERSIONS[*]})"
    echo "  --node-version <ver>  Change Node.js version (${NODE_VERSIONS[*]})"
    echo "  --bun-version <ver>   Change Bun version (${BUN_VERSIONS[*]})"
    echo "  --go-version <ver>    Change Go version (${GO_VERSIONS[*]})"
    echo "  --cpu <num>           Change CPU limit (e.g., 0.5, 1, 2)"
    echo "  --memory <size>       Change memory limit (e.g., 256M, 512M, 1G)"
    echo "  --no-cache            Rebuild the image from scratch (no layer cache)"
    echo "  --all                 Rebuild all sites (no config changes allowed)"
    echo "  --help, -h            Show this help"
    echo ""
    echo "Examples:"
    echo "  $0                                   # Interactive"
    echo "  $0 my-blog                           # Rebuild with latest base image"
    echo "  $0 my-blog --php-version 8.4         # Upgrade PHP and rebuild"
    echo "  $0 my-blog --cpu 2 --memory 1G       # Raise resource limits"
    echo "  $0 my-blog --no-cache                # Full rebuild, no cache"
    echo "  $0 --all                             # Refresh every site's base image"
    echo ""
    echo "Existing sites:"
    list_sites
}

# =============================================================================
# UPDATE LOGIC
# =============================================================================

# Rebuild a site's image and recreate its container if it is running
# Usage: update_site_container <site_dir> <no_cache>
update_site_container() {
    local site_dir="$1"
    local no_cache="$2"
    local site_name
    site_name=$(basename "$site_dir")

    local -a build_opts=(--pull)
    [[ "$no_cache" == true ]] && build_opts+=(--no-cache)

    log_info "Rebuilding image (pulling latest base image)..."
    if ! (cd "$site_dir" && docker compose build "${build_opts[@]}"); then
        log_error "Failed to build image"
        return 1
    fi
    log_ok "Image rebuilt"

    if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${site_name}$"; then
        log_info "Recreating container..."
        if ! (cd "$site_dir" && docker compose up -d); then
            log_error "Failed to recreate container"
            return 1
        fi
        log_ok "Container recreated"
    else
        log_info "Container not running - start it with: cd $site_dir && sudo docker compose up -d"
    fi

    manifest_set "$site_dir" "updated_at" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" || true
    return 0
}

# Rebuild every site, continuing on failures
# Usage: update_all_sites <no_cache>
update_all_sites() {
    local no_cache="$1"
    local updated=0 failed=0
    local -a failed_sites=()

    for site_dir in "$SITES_DIR"/*/; do
        [[ -d "$site_dir" && -f "$site_dir/compose.yaml" ]] || continue
        local name
        name=$(basename "$site_dir")

        print_header "Updating '$name'"
        if update_site_container "$site_dir" "$no_cache"; then
            ((updated++)) || true
        else
            ((failed++)) || true
            failed_sites+=("$name")
        fi
    done

    echo ""
    print_header "Update Summary"
    log_ok "$updated site(s) updated"
    if [[ $failed -gt 0 ]]; then
        log_error "$failed site(s) failed: ${failed_sites[*]}"
        return 1
    fi
    if [[ $updated -eq 0 ]]; then
        log_info "No sites found"
    else
        log_info "Old image layers may remain - clean up with: docker image prune"
    fi
    return 0
}

# =============================================================================
# INTERACTIVE MODE
# =============================================================================

interactive_mode() {
    print_header "Update Site"

    # Site selection
    local -a sites=()
    for dir in "$SITES_DIR"/*/; do
        [[ -d "$dir" && -f "$dir/compose.yaml" ]] && sites+=("$(basename "$dir")")
    done
    if [[ ${#sites[@]} -eq 0 ]]; then
        log_error "No sites found in $SITES_DIR"
        exit 1
    fi

    log_info "Existing sites:"
    for i in "${!sites[@]}"; do
        echo "  $((i + 1))) ${sites[$i]}"
    done

    local choice
    while true; do
        read -p "$(echo -e "${YELLOW}?${NC} Select site [1-${#sites[@]}]: ")" choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && [[ $choice -ge 1 ]] && [[ $choice -le ${#sites[@]} ]]; then
            SITE_NAME="${sites[$((choice - 1))]}"
            break
        fi
        echo "  Invalid choice."
    done
    log_ok "Site: $SITE_NAME"

    local site_dir="$SITES_DIR/$SITE_NAME"
    local runtime current_version current_cpu current_memory
    runtime=$(get_site_runtime "$site_dir")
    current_version=$(get_site_version "$site_dir" "$runtime" 2>/dev/null || echo "")
    current_cpu=$(sed -n "s|.*cpus: '\([^']*\)'.*|\1|p" "$site_dir/compose.yaml" | head -1)
    current_memory=$(sed -n "s|.*memory: '\([^']*\)'.*|\1|p" "$site_dir/compose.yaml" | head -1)

    echo ""
    log_info "Current configuration:"
    echo "  Runtime:  $runtime ${current_version:+($current_version)}"
    echo "  CPU:      ${current_cpu:-?}"
    echo "  Memory:   ${current_memory:-?}"

    # Runtime version change
    if [[ "$runtime" != "unknown" && -n "$current_version" ]]; then
        echo ""
        if confirm "Change $runtime version (current: $current_version)?"; then
            select_runtime_version "$runtime"
            if [[ "$RUNTIME_VERSION" != "$current_version" ]]; then
                VERSION_RUNTIME="$runtime"
            else
                log_info "Version unchanged"
                RUNTIME_VERSION=""
            fi
        fi
    fi

    # Resource limits change
    echo ""
    local input
    while true; do
        input=$(prompt_value "CPU limit" "${current_cpu:-1}")
        if [[ -z "$input" || "$input" == "$current_cpu" ]]; then
            break
        fi
        if validate_cpu_limit "$input"; then
            NEW_CPU="$input"
            break
        fi
    done
    while true; do
        input=$(prompt_value "Memory limit" "${current_memory:-512M}")
        if [[ -z "$input" || "$input" == "$current_memory" ]]; then
            break
        fi
        if validate_memory_limit "$input"; then
            NEW_MEMORY="$input"
            break
        fi
    done

    # Build options
    echo ""
    if confirm "Rebuild image without cache? (slower, fully fresh)"; then
        NO_CACHE=true
    fi

    # Summary
    echo ""
    print_header "Summary"
    echo "  Site:       $SITE_NAME"
    if [[ -n "$RUNTIME_VERSION" ]]; then
        echo "  Version:    $current_version -> $RUNTIME_VERSION"
    fi
    [[ -n "$NEW_CPU" ]] && echo "  CPU:        ${current_cpu:-?} -> $NEW_CPU"
    [[ -n "$NEW_MEMORY" ]] && echo "  Memory:     ${current_memory:-?} -> $NEW_MEMORY"
    echo "  Rebuild:    $([[ "$NO_CACHE" == true ]] && echo "full (no cache)" || echo "with latest base image")"
    echo ""

    if ! confirm "Proceed with update?" "y"; then
        log_info "Cancelled"
        exit 0
    fi
}

# =============================================================================
# ARGUMENTS
# =============================================================================

SITE_NAME=""
RUNTIME_VERSION=""
VERSION_RUNTIME=""
NEW_CPU=""
NEW_MEMORY=""
NO_CACHE=false
ALL=false

POSITIONAL=()
while [[ $# -gt 0 ]]; do
    case $1 in
        --php-version)
            RUNTIME_VERSION="$2"; VERSION_RUNTIME="php"
            shift 2
            ;;
        --node-version)
            RUNTIME_VERSION="$2"; VERSION_RUNTIME="nodejs"
            shift 2
            ;;
        --bun-version)
            RUNTIME_VERSION="$2"; VERSION_RUNTIME="bun"
            shift 2
            ;;
        --go-version)
            RUNTIME_VERSION="$2"; VERSION_RUNTIME="go"
            shift 2
            ;;
        --cpu)
            NEW_CPU="$2"
            shift 2
            ;;
        --memory)
            NEW_MEMORY="$2"
            shift 2
            ;;
        --no-cache)
            NO_CACHE=true
            shift
            ;;
        --all)
            ALL=true
            shift
            ;;
        --help|-h)
            show_help
            exit 0
            ;;
        *)
            POSITIONAL+=("$1")
            shift
            ;;
    esac
done

set -- "${POSITIONAL[@]+"${POSITIONAL[@]}"}"
[[ $# -ge 1 ]] && SITE_NAME="$1"

require_docker

# =============================================================================
# ALL-SITES MODE
# =============================================================================

if [[ "$ALL" == true ]]; then
    if [[ -n "$SITE_NAME" || -n "$RUNTIME_VERSION" || -n "$NEW_CPU" || -n "$NEW_MEMORY" ]]; then
        log_error "--all cannot be combined with a site name or config changes"
        log_info "Config changes (version, cpu, memory) are per-site"
        exit 1
    fi
    update_all_sites "$NO_CACHE"
    exit $?
fi

# =============================================================================
# SINGLE-SITE MODE
# =============================================================================

# Interactive mode if no site name given
if [[ -z "$SITE_NAME" ]]; then
    interactive_mode
fi

# Validation
if ! validate_site_name "$SITE_NAME"; then
    exit 1
fi

SITE_DIR="$SITES_DIR/$SITE_NAME"
if [[ ! -d "$SITE_DIR" ]]; then
    log_error "Site '$SITE_NAME' does not exist"
    echo ""
    list_sites
    exit 1
fi
if [[ ! -f "$SITE_DIR/compose.yaml" ]]; then
    log_error "Site '$SITE_NAME' has no compose.yaml"
    exit 1
fi

RUNTIME=$(get_site_runtime "$SITE_DIR")

# Validate a requested version change against the site's runtime
if [[ -n "$RUNTIME_VERSION" ]]; then
    if [[ "$VERSION_RUNTIME" != "$RUNTIME" ]]; then
        log_error "--${VERSION_RUNTIME}-version cannot be used on a '$RUNTIME' site"
        exit 1
    fi
    if ! validate_version "$RUNTIME" "$RUNTIME_VERSION"; then
        exit 1
    fi
fi

# Validate resource limit changes
if [[ -n "$NEW_CPU" ]] && ! validate_cpu_limit "$NEW_CPU"; then
    exit 1
fi
if [[ -n "$NEW_MEMORY" ]] && ! validate_memory_limit "$NEW_MEMORY"; then
    exit 1
fi

# =============================================================================
# UPDATE
# =============================================================================

print_header "Updating site '$SITE_NAME'"

# Apply version change
if [[ -n "$RUNTIME_VERSION" ]]; then
    CURRENT_VERSION=$(get_site_version "$SITE_DIR" "$RUNTIME" 2>/dev/null || echo "?")
    if [[ "$RUNTIME_VERSION" == "$CURRENT_VERSION" ]]; then
        log_info "Version already $RUNTIME_VERSION, nothing to change"
    else
        log_info "Changing $RUNTIME version: $CURRENT_VERSION -> $RUNTIME_VERSION"
        if ! update_site_version "$SITE_DIR" "$RUNTIME" "$RUNTIME_VERSION"; then
            log_error "Failed to update version (missing .env?)"
            exit 1
        fi
    fi
fi

# Apply resource limit changes
if [[ -n "$NEW_CPU" || -n "$NEW_MEMORY" ]]; then
    update_site_resources "$SITE_DIR" "$NEW_CPU" "$NEW_MEMORY"
fi

# Rebuild and recreate
if ! update_site_container "$SITE_DIR" "$NO_CACHE"; then
    exit 1
fi

echo ""
log_ok "Site '$SITE_NAME' updated"
log_info "Old image layers may remain - clean up with: docker image prune"