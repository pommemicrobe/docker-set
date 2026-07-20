#!/usr/bin/env bash
#
# site-delete.sh - Delete an existing site
#
# Usage: ./scripts/site-delete.sh <site-name> [--force]
#

# Load libraries
source "$(dirname "$0")/../lib/common.sh"
source "$(dirname "$0")/../lib/site.sh"
source "$(dirname "$0")/../lib/database.sh"

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
    echo "  --with-db     Also delete the site's MySQL database and user"
    echo "                (a safety dump is saved in backups/ first)"
    echo "  --force, -f   Delete without asking for confirmation"
    echo "  --help, -h    Show this help"
    echo ""
    echo "Without --with-db, interactive mode offers to delete the database"
    echo "if one exists; --force alone never touches the database."
    echo ""
    echo "Existing sites:"
    list_sites
}

# =============================================================================
# ARGUMENTS
# =============================================================================

FORCE=false
WITH_DB=false

# Parse arguments
POSITIONAL=()
while [[ $# -gt 0 ]]; do
    case $1 in
        --force|-f)
            FORCE=true
            shift
            ;;
        --with-db)
            WITH_DB=true
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

# Decide what to do with the site's database:
# - --with-db: always attempt deletion
# - interactive: offer deletion only if the database actually exists
# - --force alone: never touch the database
DELETE_DB=false
DB_NAME=$(site_db_name "$SITE_NAME")
if [[ "$WITH_DB" == true ]]; then
    DELETE_DB=true
elif [[ "$FORCE" != true ]]; then
    if docker ps --format '{{.Names}}' 2>/dev/null | grep -q '^mysql$' \
        && ROOT_PASSWORD=$(get_mysql_root_password 2>/dev/null) \
        && database_exists "$DB_NAME" "$ROOT_PASSWORD"; then
        if confirm "Also delete database '$DB_NAME' and its user? (a dump will be saved first)"; then
            DELETE_DB=true
        fi
    fi
fi

# =============================================================================
# DELETION
# =============================================================================

# Capture the site's domains before deleting the manifest (for ACME cleanup)
SITE_DOMAINS=()
while IFS= read -r _domain; do
    [[ -n "$_domain" ]] && SITE_DOMAINS+=("$_domain")
done < <(get_site_domains "$SITE_DIR")

# Stop container and remove the built image (down also cleans up when only the
# image exists, e.g. sites created with --no-start after a framework install)
if [[ -f "$SITE_DIR/compose.yaml" ]]; then
    log_info "Stopping container and removing built image..."
    (cd "$SITE_DIR" && docker compose down --volumes --remove-orphans --rmi local 2>/dev/null) || true
    log_ok "Container and image removed"
fi

# Delete the database (with a safety dump first)
if [[ "$DELETE_DB" == true ]]; then
    echo ""
    log_info "Deleting database '$DB_NAME'..."
    if ! require_mysql; then
        log_warn "MySQL not available - database not deleted"
    elif ! ROOT_PASSWORD=$(get_mysql_root_password); then
        log_warn "No MySQL credentials - database not deleted"
    elif ! database_exists "$DB_NAME" "$ROOT_PASSWORD"; then
        log_info "Database '$DB_NAME' does not exist, nothing to delete"
    else
        mkdir -p "$BACKUPS_DIR"
        DUMP_FILE="$BACKUPS_DIR/${SITE_NAME}_db_$(date +%Y%m%d_%H%M%S).sql.gz"
        if dump_database "$DB_NAME" "$DUMP_FILE" "$ROOT_PASSWORD"; then
            log_ok "Safety dump saved: $DUMP_FILE"
        else
            log_warn "Failed to dump database before deletion"
            if [[ "$FORCE" != true ]] && ! confirm "Drop database anyway (no dump)?"; then
                log_info "Database kept"
                DELETE_DB=false
            fi
        fi
        if [[ "$DELETE_DB" == true ]]; then
            if drop_site_database "$SITE_NAME" "$ROOT_PASSWORD"; then
                log_ok "Database '$DB_NAME' and user '$(site_db_user "$SITE_NAME")' deleted"
            else
                log_warn "Failed to delete database"
            fi
        fi
    fi
fi

# Delete directory
echo ""
log_info "Deleting files..."
rm -rf "$SITE_DIR"
log_ok "Directory deleted"

# Remove the site's certificates from Traefik's ACME storage so it stops
# trying to renew them forever
if [[ ${#SITE_DOMAINS[@]} -gt 0 ]]; then
    purge_acme_certificates "${SITE_DOMAINS[@]}"
fi

echo ""
log_ok "Site '$SITE_NAME' deleted successfully"
