#!/usr/bin/env bash
#
# site-shell.sh - Open an interactive shell inside a site's container
#
# Uses docker compose exec on the site's service so no runtime has to be
# installed on the host. Prefers bash, falls back to sh (alpine images).
#
# Usage:
#   ./scripts/site-shell.sh           # Interactive mode
#   ./scripts/site-shell.sh <name>    # Direct mode
#

# Load libraries
source "$(dirname "$0")/../lib/common.sh"
source "$(dirname "$0")/../lib/site.sh"

# =============================================================================
# HELP
# =============================================================================

show_help() {
    echo "Usage: $0 [site-name]"
    echo ""
    echo "Open an interactive shell inside a site's running container."
    echo "Uses bash when the image provides it, falls back to sh."
    echo ""
    echo "Run without arguments for interactive mode."
    echo ""
    echo "Options:"
    echo "  --help, -h   Show this help"
    echo ""
    echo "Examples:"
    echo "  $0                # Interactive site selection"
    echo "  $0 my-blog        # Shell into the 'my-blog' container"
    echo ""
    echo "Existing sites:"
    list_sites
}

# =============================================================================
# INTERACTIVE MODE
# =============================================================================

interactive_mode() {
    print_header "Site Shell"

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
}

# =============================================================================
# ARGUMENTS
# =============================================================================

SITE_NAME=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --help|-h)
            show_help
            exit 0
            ;;
        -*)
            log_error "Unknown option: $1"
            show_help
            exit 1
            ;;
        *)
            if [[ -n "$SITE_NAME" ]]; then
                log_error "Too many arguments: '$1'"
                show_help
                exit 1
            fi
            SITE_NAME="$1"
            shift
            ;;
    esac
done

require_docker

# Interactive mode if no site name given
if [[ -z "$SITE_NAME" ]]; then
    interactive_mode
fi

# =============================================================================
# VALIDATION
# =============================================================================

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

if ! docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${SITE_NAME}$"; then
    log_error "Container '$SITE_NAME' is not running"
    log_info "Start it with: cd sites/$SITE_NAME && sudo docker compose up -d"
    exit 1
fi

# =============================================================================
# SHELL
# =============================================================================

# Prod containers run from a baked image with no ./app bind mount: anything
# changed inside is lost when the container is recreated
MODE=$(manifest_get "$SITE_DIR" "mode" || true)
if [[ "${MODE:-dev}" == "prod" ]]; then
    log_warn "Site is in prod mode: the container filesystem is immutable - changes are lost on redeploy"
fi

log_info "Opening shell in '$SITE_NAME' (exit with 'exit' or Ctrl+D)..."

cd "$SITE_DIR" || exit 1
# Single exec invocation: probe for bash inside the container, fall back to
# sh (alpine images). exec keeps the shell's exit code as ours.
exec docker compose exec "$SITE_NAME" sh -c 'command -v bash >/dev/null 2>&1 && exec bash || exec sh'
