#!/usr/bin/env bash
#
# site-deploy.sh - Deploy an existing site
#
# Pulls the latest code when the site was created from a git repository
# (--from-git), then applies it according to the site's mode:
#   prod: rebuild the image (code is baked in) and recreate the container
#   dev:  restart the container (live mount; startup reinstalls dependencies)
#
# Usage:
#   ./scripts/site-deploy.sh                      # Interactive mode
#   ./scripts/site-deploy.sh <name> [options]     # Direct mode
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
    echo "Deploy a site: pull the latest code when the site was created from a"
    echo "git repository (--from-git), then rebuild the image and recreate the"
    echo "container (prod mode) or restart the container (dev mode)."
    echo ""
    echo "Run without arguments for interactive mode."
    echo ""
    echo "Options:"
    echo "  --no-prune            Keep old images after a prod deploy (by default"
    echo "                        dangling images are pruned to reclaim disk space)"
    echo "  --no-cache            Rebuild the image from scratch (prod mode only)"
    echo "  --help, -h            Show this help"
    echo ""
    echo "Git sources:"
    echo "  Sites created with --from-git are pulled (fast-forward only) before"
    echo "  deploying, using containerized git - no git needed on the host."
    echo "  Private HTTPS repos can embed a deploy token in the stored URL:"
    echo "  https://TOKEN@github.com/owner/repo.git"
    echo ""
    echo "Examples:"
    echo "  $0                                   # Interactive"
    echo "  $0 my-app                            # Pull (if git) + rebuild/restart"
    echo "  $0 my-app --no-cache                 # Prod: full image rebuild"
    echo "  $0 my-app --no-prune                 # Keep previous images around"
    echo ""
    echo "Existing sites:"
    list_sites
}

# =============================================================================
# DEPLOY LOGIC
# =============================================================================

# Run git in a throwaway container against a site's app/ directory.
# No git needed on the host; runs as the invoking user so files in app/
# keep their ownership; safe.directory covers checkouts made by other uids.
# Usage: git_in_container <app_dir> <git-args...>
git_in_container() {
    local app_dir="$1"
    shift

    docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp \
        -e GIT_CONFIG_COUNT=1 -e GIT_CONFIG_KEY_0=safe.directory \
        -e GIT_CONFIG_VALUE_0='*' \
        -v "$app_dir:/repo" -w /repo alpine/git "$@"
}

# Pull the latest code for a git-sourced site (fast-forward only)
# Usage: pull_site_source <site_dir>
pull_site_source() {
    local site_dir="$1"

    local branch
    branch=$(manifest_get "$site_dir" "source_branch" || true)

    local -a pull_args=(pull --ff-only)
    [[ -n "$branch" ]] && pull_args+=(origin "$branch")

    log_info "Pulling latest code${branch:+ (branch: $branch)}..."
    if ! git_in_container "$site_dir/app" "${pull_args[@]}"; then
        log_error "git pull failed"
        log_info "The checkout in $site_dir/app may have diverged or contain local changes"
        return 1
    fi
    log_ok "Code up to date"
}

# Apply the new code according to the site's mode and stamp the manifest
# Usage: deploy_site_container <site_dir> <mode> <no_cache> <no_prune>
deploy_site_container() {
    local site_dir="$1"
    local mode="$2"
    local no_cache="$3"
    local no_prune="$4"
    local site_name
    site_name=$(basename "$site_dir")

    if [[ "$mode" == "prod" ]]; then
        # Prod images are immutable: bake the new code into a fresh image
        local -a build_opts=(--pull)
        [[ "$no_cache" == true ]] && build_opts+=(--no-cache)

        log_info "Building image (pulling latest base image)..."
        if ! (cd "$site_dir" && docker compose build "${build_opts[@]}"); then
            log_error "Failed to build image"
            return 1
        fi
        log_ok "Image built"

        log_info "Recreating container..."
        if ! (cd "$site_dir" && docker compose up -d); then
            log_error "Failed to start container"
            return 1
        fi
        log_ok "Container running"

        if [[ "$no_prune" == true ]]; then
            log_info "Image prune skipped (--no-prune) - reclaim space later with: docker image prune"
        else
            # Each prod deploy strands the previous image as an untagged layer;
            # prune only removes dangling images (used images are never touched)
            log_info "Pruning dangling images..."
            if docker image prune -f >/dev/null 2>&1; then
                log_ok "Dangling images removed"
            else
                log_warn "Image prune failed - run manually: docker image prune"
            fi
        fi
    else
        # Dev containers mount ./app live; a restart picks up the new code
        # (container startup reinstalls dependencies)
        [[ "$no_cache" == true ]] && log_info "--no-cache has no effect in dev mode (no image build)"

        if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${site_name}$"; then
            log_info "Restarting container..."
            if ! (cd "$site_dir" && docker compose restart); then
                log_error "Failed to restart container"
                return 1
            fi
            log_ok "Container restarted"
        else
            log_info "Container not running - starting it..."
            if ! (cd "$site_dir" && docker compose up -d); then
                log_error "Failed to start container"
                return 1
            fi
            log_ok "Container started"
        fi
    fi

    manifest_set "$site_dir" "deployed_at" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" || true
    return 0
}

# =============================================================================
# INTERACTIVE MODE
# =============================================================================

interactive_mode() {
    print_header "Deploy Site"

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
    local mode source_type source_repo
    mode=$(get_site_mode "$site_dir")
    source_type=$(manifest_get "$site_dir" "source_type" || true)
    source_repo=$(manifest_get "$site_dir" "source_repo" || true)

    echo ""
    log_info "Deployment plan:"
    if [[ "$source_type" == "git" ]]; then
        echo "  Source:   git pull ($source_repo)"
    else
        echo "  Source:   local files (no git pull)"
    fi
    if [[ "$mode" == "prod" ]]; then
        echo "  Mode:     prod (rebuild image + recreate container)"
    else
        echo "  Mode:     dev (restart container)"
    fi
    echo ""

    if ! confirm "Proceed with deployment?" "y"; then
        log_info "Cancelled"
        exit 0
    fi
}

# =============================================================================
# ARGUMENTS
# =============================================================================

SITE_NAME=""
NO_PRUNE=false
NO_CACHE=false

POSITIONAL=()
while [[ $# -gt 0 ]]; do
    case $1 in
        --no-prune)
            NO_PRUNE=true
            shift
            ;;
        --no-cache)
            NO_CACHE=true
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
# VALIDATION
# =============================================================================

# Interactive mode if no site name given
if [[ -z "$SITE_NAME" ]]; then
    interactive_mode
fi

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

# =============================================================================
# DEPLOY
# =============================================================================

print_header "Deploying site '$SITE_NAME'"

MODE=$(get_site_mode "$SITE_DIR")
SOURCE_TYPE=$(manifest_get "$SITE_DIR" "source_type" || true)

if [[ "$SOURCE_TYPE" == "git" ]]; then
    if ! pull_site_source "$SITE_DIR"; then
        exit 1
    fi
else
    log_info "Local source (no git pull)"
fi

if ! deploy_site_container "$SITE_DIR" "$MODE" "$NO_CACHE" "$NO_PRUNE"; then
    exit 1
fi

echo ""
log_ok "Site '$SITE_NAME' deployed ($MODE mode)"
