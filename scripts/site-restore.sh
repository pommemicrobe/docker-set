#!/usr/bin/env bash
#
# site-restore.sh - Restore a site from backup
#
# Usage: ./scripts/site-restore.sh <backup-file> [--force]
#

# Load libraries
source "$(dirname "$0")/../lib/common.sh"
source "$(dirname "$0")/../lib/database.sh"

# =============================================================================
# HELP
# =============================================================================

show_help() {
    echo "Usage: $0 <backup-file> [options]"
    echo ""
    echo "Restore a site from a backup archive."
    echo ""
    echo "Arguments:"
    echo "  backup-file   Path to the backup .tar.gz file"
    echo ""
    echo "Options:"
    echo "  --force, -f   Restore without asking for confirmation"
    echo "  --help, -h    Show this help"
    echo ""
    echo "Available backups:"
    if [[ -d "$BACKUPS_DIR" ]]; then
        ls -1 "$BACKUPS_DIR"/*.tar.gz 2>/dev/null | sed 's/^/  /' || echo "  (no backups)"
    else
        echo "  (no backups directory)"
    fi
}

# =============================================================================
# ARGUMENTS
# =============================================================================

FORCE=false

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

set -- "${POSITIONAL[@]+"${POSITIONAL[@]}"}"

if [[ $# -lt 1 ]]; then
    log_error "Missing argument: backup file"
    echo ""
    show_help
    exit 1
fi

BACKUP_FILE="$1"

# =============================================================================
# VALIDATION
# =============================================================================

if [[ ! -f "$BACKUP_FILE" ]]; then
    log_error "Backup file not found: $BACKUP_FILE"
    exit 1
fi

# Extract backup to temp dir to inspect
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

log_info "Inspecting backup..."
tar -xzf "$BACKUP_FILE" -C "$TEMP_DIR"

# Find the site directory inside the backup
BACKUP_CONTENT=$(find "$TEMP_DIR" -maxdepth 2 -name "site" -type d | head -1)
if [[ -z "$BACKUP_CONTENT" || ! -d "$BACKUP_CONTENT" ]]; then
    log_error "Invalid backup: no site directory found"
    exit 1
fi

# Determine site name from the backup's .env or site.yaml
if [[ -f "$BACKUP_CONTENT/.env" ]]; then
    SITE_NAME=$(grep "^SITE_NAME=" "$BACKUP_CONTENT/.env" | cut -d'=' -f2)
elif [[ -f "$BACKUP_CONTENT/site.yaml" ]]; then
    SITE_NAME=$(grep "^name:" "$BACKUP_CONTENT/site.yaml" | sed 's/name: *"\?\([^"]*\)"\?/\1/')
fi

if [[ -z "$SITE_NAME" ]]; then
    log_error "Cannot determine site name from backup"
    exit 1
fi

SITE_DIR="$SITES_DIR/$SITE_NAME"

# Check for database dump
BACKUP_PARENT=$(dirname "$BACKUP_CONTENT")
HAS_DB_DUMP=false
if [[ -f "$BACKUP_PARENT/database.sql" ]]; then
    HAS_DB_DUMP=true
fi

# =============================================================================
# CONFIRMATION
# =============================================================================

print_header "Restore site '$SITE_NAME'"

echo "  Backup file: $BACKUP_FILE"
echo "  Site name:   $SITE_NAME"
echo "  Destination: $SITE_DIR"
echo "  Database:    $([[ "$HAS_DB_DUMP" == true ]] && echo "yes (dump included)" || echo "no")"

if [[ -d "$SITE_DIR" ]]; then
    echo ""
    log_warn "Site '$SITE_NAME' already exists and will be OVERWRITTEN"
fi

echo ""

if [[ "$FORCE" != true ]]; then
    if ! confirm "Proceed with restore?"; then
        log_info "Operation cancelled"
        exit 0
    fi
fi

# =============================================================================
# RESTORE
# =============================================================================

# Stop existing container if running
if docker ps -a --format '{{.Names}}' 2>/dev/null | grep -q "^${SITE_NAME}$"; then
    log_info "Stopping existing container..."
    (cd "$SITE_DIR" && docker compose down 2>/dev/null) || true
fi

# Remove existing site directory
if [[ -d "$SITE_DIR" ]]; then
    log_info "Removing existing site..."
    rm -rf "$SITE_DIR"
fi

# Copy site files
log_info "Restoring site files..."
cp -r "$BACKUP_CONTENT" "$SITE_DIR"
log_ok "Site files restored"

# Restore database if dump exists
if [[ "$HAS_DB_DUMP" == true ]]; then
    log_info "Restoring database..."

    DB_NAME="${SITE_NAME//-/_}_db"

    if ! require_mysql; then
        log_warn "Skipping database restore"
    elif ! ROOT_PASSWORD=$(get_mysql_root_password); then
        log_warn "Skipping database restore (no MySQL credentials)"
    else
        # Create database if it doesn't exist
        docker exec mysql mysql -u root -p"$ROOT_PASSWORD" -e \
            "CREATE DATABASE IF NOT EXISTS \`$DB_NAME\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;" 2>/dev/null

        # Import dump
        if docker exec -i mysql mysql -u root -p"$ROOT_PASSWORD" "$DB_NAME" \
            < "$BACKUP_PARENT/database.sql" 2>/dev/null; then
            log_ok "Database '$DB_NAME' restored"
        else
            log_warn "Failed to restore database"
        fi
    fi
fi

# Start container
echo ""
if confirm "Start the restored site now?" "y"; then
    log_info "Starting container..."
    if (cd "$SITE_DIR" && docker compose up -d --build); then
        log_ok "Container started"
    else
        log_warn "Failed to start container. You may need to rebuild: cd $SITE_DIR && docker compose up -d --build"
    fi
fi

echo ""
log_ok "Site '$SITE_NAME' restored successfully"
