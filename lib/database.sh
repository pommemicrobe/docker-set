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
# Returns: password on stdout, 1 on failure (empty file, missing key, or empty value)
get_mysql_root_password() {
    local mysql_env="$CONFIG_DIR/mysql/.env"
    if [[ ! -f "$mysql_env" ]]; then
        log_warn "MySQL .env not found"
        return 1
    fi
    local password
    password=$(grep "^MYSQL_ROOT_PASSWORD=" "$mysql_env" | cut -d'=' -f2-)
    if [[ -z "$password" ]]; then
        log_warn "MYSQL_ROOT_PASSWORD not set in $mysql_env"
        return 1
    fi
    printf '%s' "$password"
}

# Check if a database exists
# Usage: database_exists <db_name> <root_password>
# Returns: 0 if exists, 1 if not
# Uses MYSQL_PWD env var to avoid exposing password in process list.
database_exists() {
    local db_name="$1"
    local root_password="$2"
    docker exec -e MYSQL_PWD="$root_password" mysql mysql -u root -e "USE \`$db_name\`" 2>/dev/null
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
    # MYSQL_PWD env var avoids exposing the password in the process list (ps aux).
    # DB_RESULT_PASSWORD is generated from [A-Za-z0-9] only, so no SQL escaping is
    # required for the IDENTIFIED BY clause.
    if docker exec -e MYSQL_PWD="$root_password" mysql mysql -u root -e "
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

# =============================================================================
# CREDENTIAL INJECTION
# =============================================================================

# Inject DB credentials into a site's config files after database creation.
# Usage: inject_db_credentials <site_dir> <db_name> <db_user> <db_password> [framework]
#
# - Uncomments and sets the DB_* block in the site's .env (works for all runtimes).
# - For laravel: patches DB_PASSWORD in app/.env (other DB_* fields are set by
#   the framework installer from the site name, which matches what we created).
# - For wordpress: no extra work needed — wp-config.php reads via getenv() and
#   the PHP template's compose.yaml forwards DB_* from the site .env to the container.
inject_db_credentials() {
    local site_dir="$1"
    local db_name="$2"
    local db_user="$3"
    local db_password="$4"
    local framework="${5:-}"

    local env_file="$site_dir/.env"
    if [[ -f "$env_file" ]]; then
        local escaped_name escaped_user escaped_password
        escaped_name=$(sed_escape "$db_name")
        escaped_user=$(sed_escape "$db_user")
        escaped_password=$(sed_escape "$db_password")

        sed_inplace "s|^# DB_HOST=.*|DB_HOST=mysql|" "$env_file"
        sed_inplace "s|^# DB_PORT=.*|DB_PORT=3306|" "$env_file"
        sed_inplace "s|^# DB_DATABASE=.*|DB_DATABASE=$escaped_name|" "$env_file"
        sed_inplace "s|^# DB_USERNAME=.*|DB_USERNAME=$escaped_user|" "$env_file"
        sed_inplace "s|^# DB_PASSWORD=.*|DB_PASSWORD=$escaped_password|" "$env_file"
        log_ok "DB credentials written to site .env"
    fi

    # Laravel: the installer uncomments DB_PASSWORD but leaves it empty.
    if [[ "$framework" == "laravel" && -f "$site_dir/app/.env" ]]; then
        local escaped_password
        escaped_password=$(sed_escape "$db_password")
        sed_inplace "s|^DB_PASSWORD=.*|DB_PASSWORD=$escaped_password|" "$site_dir/app/.env"
        log_ok "DB password written to Laravel .env"
    fi
}
