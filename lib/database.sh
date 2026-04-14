#!/usr/bin/env bash
#
# database.sh - Database operations for docker-set
#
# Usage: source "$(dirname "$0")/../lib/database.sh"
# Requires: common.sh to be sourced first
#

# =============================================================================
# CONFIGURATION
# =============================================================================

# Default timeout for MySQL wait (can be overridden via MYSQL_WAIT_TIMEOUT env var)
MYSQL_WAIT_TIMEOUT="${MYSQL_WAIT_TIMEOUT:-30}"

# =============================================================================
# MYSQL HEALTH CHECK
# =============================================================================

# Wait for MySQL container to be healthy
# Usage: wait_for_mysql [max_seconds]
wait_for_mysql() {
    local max_wait="${1:-$MYSQL_WAIT_TIMEOUT}"
    local elapsed=0

    while [[ $elapsed -lt $max_wait ]]; do
        local status
        status=$(docker inspect --format='{{.State.Health.Status}}' mysql 2>/dev/null || echo "unknown")
        if [[ "$status" == "healthy" ]]; then
            return 0
        fi
        sleep 1
        ((elapsed++))
    done

    return 1
}

# =============================================================================
# MYSQL CREDENTIALS
# =============================================================================

# Get MySQL root password from config
# Usage: get_mysql_root_password
# Returns: password on stdout, 1 on failure
get_mysql_root_password() {
    local mysql_env="$CONFIG_DIR/mysql/.env"
    if [[ ! -f "$mysql_env" ]]; then
        log_warn "MySQL .env not found"
        return 1
    fi
    grep "^MYSQL_ROOT_PASSWORD=" "$mysql_env" | cut -d'=' -f2
}

# Check if a database exists
# Usage: database_exists <db_name> <root_password>
# Returns: 0 if exists, 1 if not
database_exists() {
    local db_name="$1"
    local root_password="$2"
    docker exec mysql mysql -u root -p"$root_password" -e "USE \`$db_name\`" 2>/dev/null
}

# Require MySQL to be running and healthy
# Usage: require_mysql [timeout]
# Returns: 0 on success, 1 on failure (with log messages)
require_mysql() {
    local timeout="${1:-$MYSQL_WAIT_TIMEOUT}"

    if ! docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^mysql$"; then
        log_warn "MySQL container not running"
        return 1
    fi

    log_info "Waiting for MySQL to be ready..."
    if ! wait_for_mysql "$timeout"; then
        log_warn "MySQL not ready after ${timeout}s"
        return 1
    fi

    return 0
}

# =============================================================================
# DATABASE CREATION
# =============================================================================

# Create a database and user for a site
# Sets global variables: DB_RESULT_NAME, DB_RESULT_USER, DB_RESULT_PASSWORD
# Usage: create_site_database <site_name>
# Returns: 0 on success, 1 on failure
create_site_database() {
    local site_name="$1"

    DB_RESULT_NAME="${site_name//-/_}_db"
    DB_RESULT_USER="${site_name//-/_}"
    DB_RESULT_PASSWORD=""

    # Ensure MySQL is running and healthy
    if ! require_mysql; then
        log_warn "Skipping database creation"
        return 1
    fi

    # Get MySQL root password
    local root_password
    if ! root_password=$(get_mysql_root_password); then
        log_warn "Skipping database creation"
        return 1
    fi

    # Generate password for the new user
    DB_RESULT_PASSWORD=$(generate_password 24)

    # Create database and user
    if docker exec mysql mysql -u root -p"$root_password" -e "
        CREATE DATABASE IF NOT EXISTS \`$DB_RESULT_NAME\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
        CREATE USER IF NOT EXISTS '$DB_RESULT_USER'@'%' IDENTIFIED BY '$DB_RESULT_PASSWORD';
        GRANT ALL PRIVILEGES ON \`$DB_RESULT_NAME\`.* TO '$DB_RESULT_USER'@'%';
        FLUSH PRIVILEGES;
    " 2>/dev/null; then
        log_ok "Database '$DB_RESULT_NAME' created"
        log_ok "User '$DB_RESULT_USER' created"
        return 0
    else
        log_warn "Failed to create database (MySQL error)"
        DB_RESULT_PASSWORD=""
        return 1
    fi
}
