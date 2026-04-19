#!/usr/bin/env bash
#
# site-backup.sh - Backup a site (files + optional database)
#
# Usage:
#   ./scripts/site-backup.sh <site-name>              # Backup files only
#   ./scripts/site-backup.sh <site-name> --with-db     # Backup files + database
#

# Load libraries
source "$(dirname "$0")/../lib/common.sh"
source "$(dirname "$0")/../lib/database.sh"

# =============================================================================
# HELP
# =============================================================================

show_help() {
    echo "Usage: $0 <site-name> [options]"
    echo ""
    echo "Create a backup of a site (files and optionally its database)."
    echo ""
    echo "Arguments:"
    echo "  site-name     Name of the site to backup"
    echo ""
    echo "Options:"
    echo "  --with-db     Include database dump in backup"
    echo "  --help, -h    Show this help"
    echo ""
    echo "Backups are stored in: $BACKUPS_DIR"
    echo ""
    echo "Existing sites:"
    list_sites
}

# =============================================================================
# ARGUMENTS
# =============================================================================

WITH_DB=false

POSITIONAL=()
while [[ $# -gt 0 ]]; do
    case $1 in
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

set -- "${POSITIONAL[@]+"${POSITIONAL[@]}"}"

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

if ! validate_site_name "$SITE_NAME"; then
    exit 1
fi

if [[ ! -d "$SITE_DIR" ]]; then
    log_error "Site '$SITE_NAME' does not exist"
    echo ""
    list_sites
    exit 1
fi

# =============================================================================
# BACKUP
# =============================================================================

print_header "Backing up site '$SITE_NAME'"

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_NAME="${SITE_NAME}_${TIMESTAMP}"
BACKUP_DIR="$BACKUPS_DIR/$BACKUP_NAME"
BACKUP_FILE="$BACKUPS_DIR/${BACKUP_NAME}.tar.gz"

mkdir -p "$BACKUP_DIR"

# Backup site files
log_info "Backing up site files..."
cp -r "$SITE_DIR" "$BACKUP_DIR/site"
log_ok "Site files backed up"

# Backup database if requested
if [[ "$WITH_DB" == true ]]; then
    log_info "Backing up database..."

    DB_NAME="${SITE_NAME//-/_}_db"

    if ! require_mysql; then
        log_warn "Skipping database backup"
    elif ! ROOT_PASSWORD=$(get_mysql_root_password); then
        log_warn "Skipping database backup (no MySQL credentials)"
    elif ! database_exists "$DB_NAME" "$ROOT_PASSWORD"; then
        log_warn "Database '$DB_NAME' does not exist, skipping"
    elif docker exec -e MYSQL_PWD="$ROOT_PASSWORD" mysql mysqldump -u root \
        --single-transaction "$DB_NAME" > "$BACKUP_DIR/database.sql" 2>/dev/null; then
        log_ok "Database '$DB_NAME' backed up"
    else
        log_warn "Failed to dump database"
    fi
fi

# Create tar.gz archive
log_info "Creating archive..."
(cd "$BACKUPS_DIR" && tar -czf "${BACKUP_NAME}.tar.gz" "$BACKUP_NAME")
rm -rf "$BACKUP_DIR"

# Backups contain secrets (.env with DB password, API keys, etc.) — restrict access.
chmod 600 "$BACKUP_FILE"

log_ok "Backup created: $BACKUP_FILE"

# Show size
BACKUP_SIZE=$(du -h "$BACKUP_FILE" | cut -f1)
echo ""
echo "  File: $BACKUP_FILE"
echo "  Size: $BACKUP_SIZE"
echo ""
log_warn "Backup contains site secrets (.env, keys). Keep it secure."
log_info "To restore: ./scripts/site-restore.sh $BACKUP_FILE"
