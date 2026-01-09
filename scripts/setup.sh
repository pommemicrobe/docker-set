#!/usr/bin/env bash
#
# setup.sh - Initialize docker-set infrastructure
#
# Usage: ./scripts/setup.sh
#

# Load common library
source "$(dirname "$0")/../lib/common.sh"

# =============================================================================
# FUNCTIONS
# =============================================================================

setup_traefik() {
    print_header "Traefik Configuration"

    local traefik_dir="$CONFIG_DIR/traefik"

    # Check if already configured
    if [[ -f "$traefik_dir/traefik.yaml" && -f "$traefik_dir/acme.json" ]]; then
        log_warn "Traefik appears to be already configured"
        if ! confirm "Reconfigure Traefik?"; then
            return 0
        fi
    fi

    # Copy traefik.yaml.dist
    if [[ ! -f "$traefik_dir/traefik.yaml" ]]; then
        cp "$traefik_dir/traefik.yaml.dist" "$traefik_dir/traefik.yaml"
        log_ok "traefik.yaml created"
    fi

    # Ask for Let's Encrypt email
    local current_email
    current_email=$(grep -oP 'email:\s*"\K[^"]+' "$traefik_dir/traefik.yaml" 2>/dev/null || echo "ACME_EMAIL")

    if [[ "$current_email" == "ACME_EMAIL" ]]; then
        local email
        email=$(prompt_value "Email for SSL certificates (Let's Encrypt)")

        if [[ -z "$email" ]]; then
            log_error "Email required for Let's Encrypt"
            exit 1
        fi

        sed_inplace "s|ACME_EMAIL|$email|g" "$traefik_dir/traefik.yaml"
        log_ok "Email configured: $email"
    else
        log_info "Current email: $current_email"
    fi

    # Create acme.json with proper permissions
    if [[ ! -f "$traefik_dir/acme.json" ]]; then
        cp "$traefik_dir/acme.json.dist" "$traefik_dir/acme.json"
    fi
    chmod 600 "$traefik_dir/acme.json"
    log_ok "acme.json configured (permissions 600)"

    # Create logs directory
    mkdir -p "$traefik_dir/logs"
    log_ok "Logs directory created"
}

setup_mysql() {
    print_header "MySQL Configuration"

    local mysql_dir="$CONFIG_DIR/mysql"

    # Check if already configured
    if [[ -f "$mysql_dir/.env" ]]; then
        log_warn "MySQL appears to be already configured"
        if ! confirm "Reconfigure MySQL?"; then
            return 0
        fi
    fi

    # Copy .env.dist
    cp "$mysql_dir/.env.dist" "$mysql_dir/.env"

    # Generate or ask for password
    local password
    if confirm "Generate a secure password automatically?" "y"; then
        password=$(generate_password 32)
        log_ok "Password generated (32 characters)"
    else
        password=$(prompt_value "MySQL root password")
        if [[ -z "$password" ]]; then
            log_error "Password required"
            exit 1
        fi
    fi

    sed_inplace "s|GENERATED_PASSWORD|$password|g" "$mysql_dir/.env"
    log_ok "Password configured in .env"

    # Create data directory
    mkdir -p "$mysql_dir/data"
    log_ok "Data directory created"

    # Display password
    echo ""
    log_warn "IMPORTANT: Save this password, it will not be shown again"
    echo "  MYSQL_ROOT_PASSWORD=$password"
    echo ""
}

start_infrastructure() {
    print_header "Starting Infrastructure"

    # Start Traefik
    log_info "Starting Traefik..."
    (cd "$CONFIG_DIR/traefik" && docker compose up -d)
    log_ok "Traefik started"

    # Start MySQL
    log_info "Starting MySQL..."
    (cd "$CONFIG_DIR/mysql" && docker compose up -d)
    log_ok "MySQL started"

    # Wait a bit and check status
    sleep 3
    echo ""
    log_info "Container status:"
    docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep -E "traefik|mysql|NAMES"
}

# =============================================================================
# MAIN
# =============================================================================

main() {
    print_header "Setup docker-set"

    # Prerequisites check
    log_info "Checking prerequisites..."
    require_docker
    log_ok "Docker available"

    # Create web network if needed
    ensure_web_network

    # Create required directories
    mkdir -p "$SITES_DIR" "$BACKUPS_DIR"

    # Configure Traefik
    setup_traefik

    # Configure MySQL
    setup_mysql

    # Start?
    echo ""
    if confirm "Start infrastructure now?" "y"; then
        start_infrastructure
    else
        log_info "To start later:"
        echo "  cd $CONFIG_DIR/traefik && sudo docker compose up -d"
        echo "  cd $CONFIG_DIR/mysql && sudo docker compose up -d"
    fi

    # Summary
    print_header "Setup Complete"
    log_ok "Infrastructure configured successfully"
    echo ""
    log_info "Next steps:"
    echo "  1. Create a site: ./scripts/site-create.sh <name> <url> <template>"
    echo "  2. Available templates:"
    ls -1 "$TEMPLATES_DIR" 2>/dev/null | sed 's/^/     - /' || echo "     (no templates)"
    echo ""
}

main "$@"
