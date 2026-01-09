#!/usr/bin/env bash
#
# site-delete.sh - Delete an existing site
#
# Usage: ./scripts/site-delete.sh <site-name> [--force]
#

# Load common library
source "$(dirname "$0")/../lib/common.sh"

# =============================================================================
# HELP
# =============================================================================

show_help() {
    echo "Usage: $0 <site-name> [options]"
    echo ""
    echo "Arguments:"
    echo "  site-name     Name of the site to delete"
    echo ""
    echo "Options:"
    echo "  --force, -f   Delete without asking for confirmation"
    echo "  --help, -h    Show this help"
    echo ""
    echo "Existing sites:"
    list_sites
}

# =============================================================================
# ARGUMENTS
# =============================================================================

FORCE=false

# Parse arguments
POSITIONAL=()
while [[ $# -gt 0 ]]; do
    case $1 in
        --force|-f)
            FORCE=true
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

# Restore positional arguments
set -- "${POSITIONAL[@]+"${POSITIONAL[@]}"}"

# Check argument count
if [[ $# -lt 1 ]]; then
    log_error "Missing argument: site name"
    echo ""
    show_help
    exit 1
fi

SITE_NAME="$1"
SITE_DIR="$SITES_DIR/$SITE_NAME"

# =============================================================================
# VALIDATION
# =============================================================================

# Validate name (protection against injection)
if ! validate_site_name "$SITE_NAME"; then
    exit 1
fi

# Check that site exists
if [[ ! -d "$SITE_DIR" ]]; then
    log_error "Site '$SITE_NAME' does not exist"
    echo ""
    list_sites
    exit 1
fi

# =============================================================================
# CONFIRMATION
# =============================================================================

print_header "Deleting site '$SITE_NAME'"

# Display site info
log_info "Location: $SITE_DIR"

# Check if container is running
if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${SITE_NAME}$"; then
    log_warn "Container '$SITE_NAME' is currently running"
fi

# List files
log_info "Site contents:"
ls -la "$SITE_DIR" 2>/dev/null | head -10 | sed 's/^/  /'

echo ""

# Ask for confirmation unless --force
if [[ "$FORCE" != true ]]; then
    log_warn "This action is IRREVERSIBLE"
    if ! confirm "Are you sure you want to delete '$SITE_NAME'?"; then
        log_info "Operation cancelled"
        exit 0
    fi
fi

# =============================================================================
# DELETION
# =============================================================================

# Stop container if needed
if docker ps -a --format '{{.Names}}' 2>/dev/null | grep -q "^${SITE_NAME}$"; then
    log_info "Stopping and removing container..."
    (cd "$SITE_DIR" && docker compose down --volumes --remove-orphans 2>/dev/null) || true
    log_ok "Container stopped"
fi

# Delete directory
log_info "Deleting files..."
rm -rf "$SITE_DIR"
log_ok "Directory deleted"

echo ""
log_ok "Site '$SITE_NAME' deleted successfully"
