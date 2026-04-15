#!/usr/bin/env bash
#
# site-create.sh - Create a new site from a template
#
# Usage:
#   ./scripts/site-create.sh                     # Interactive mode
#   ./scripts/site-create.sh <name> <url> <tpl>  # Direct mode
#

# Load libraries
source "$(dirname "$0")/../lib/common.sh"
source "$(dirname "$0")/../lib/site.sh"
source "$(dirname "$0")/../lib/database.sh"
source "$(dirname "$0")/../lib/framework.sh"

# =============================================================================
# HELP
# =============================================================================

show_help() {
    echo "Usage: $0 [site-name] [site-url] [template-name] [options]"
    echo ""
    echo "Run without arguments for interactive mode."
    echo ""
    echo "Arguments (optional - will prompt if missing):"
    echo "  site-name     Site name (lowercase letters, numbers, hyphens)"
    echo "  site-url      Site URL (e.g., my-site.com or localhost:3000)"
    echo "  template-name Template to use"
    echo ""
    echo "Options:"
    echo "  --cpu <num>           CPU limit (e.g., 0.5, 1, 2). Default: 1"
    echo "  --memory <size>       Memory limit (e.g., 256M, 512M, 1G). Default: 512M"
    echo "  --php-version <ver>   PHP version (${PHP_VERSIONS[*]}). Default: $DEFAULT_PHP_VERSION"
    echo "  --node-version <ver>  Node.js version (${NODE_VERSIONS[*]}). Default: $DEFAULT_NODE_VERSION"
    echo "  --framework <name>    Framework to install (optional)"
    echo "  --with-db             Create database user for this site"
    echo "  --no-ssl              Use HTTP instead of HTTPS (for local development)"
    echo "  --no-autostart        Don't auto-start container when Docker starts"
    echo "  --no-start            Don't start container after creation"
    echo "  --aliases <domains>   Additional domains (comma-separated)"
    echo "  --redirect-aliases    Redirect aliases to main domain (301)"
    echo "  --help, -h            Show this help"
    echo ""
    echo "Domain aliases:"
    echo "  Use --aliases to add additional domains that serve the same content."
    echo "  Use --redirect-aliases to redirect all aliases to the main URL."
    echo ""
    echo "Examples:"
    echo "  $0                                                    # Interactive"
    echo "  $0 my-blog my-blog.com php-traefik                   # Direct"
    echo "  $0 my-app app.com php-traefik --with-db              # With database"
    echo "  $0 my-app app.com php-traefik --php-version 8.3      # PHP 8.3"
    echo "  $0 my-app app.com nodejs-traefik --node-version 22   # Node 22"
    echo "  $0 my-app app.com php-traefik --framework laravel --with-db"
    echo "  $0 my-app app.local php-traefik --no-ssl             # Local dev"
    echo ""
    echo "  # Multiple domains serving same content:"
    echo "  $0 my-site example.com php-traefik --aliases www.example.com"
    echo ""
    echo "  # Redirect www to non-www:"
    echo "  $0 my-site example.com php-traefik --aliases www.example.com --redirect-aliases"
}

# =============================================================================
# INTERACTIVE MODE
# =============================================================================

# Simple numbered selection
simple_select() {
    local prompt="$1"
    shift
    local options=("$@")

    echo -e "\n${YELLOW}?${NC} $prompt"
    for i in "${!options[@]}"; do
        echo "  $((i + 1))) ${options[$i]}"
    done

    local choice
    while true; do
        read -p "  Enter number [1-${#options[@]}]: " choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && [[ $choice -ge 1 ]] && [[ $choice -le ${#options[@]} ]]; then
            echo "${options[$((choice - 1))]}"
            return
        fi
        echo "  Invalid choice, try again."
    done
}

interactive_mode() {
    print_header "Create New Site"

    # Site name
    while true; do
        SITE_NAME=$(prompt_value "Site name (e.g., my-blog)")
        if validate_site_name "$SITE_NAME" 2>/dev/null; then
            if [[ -d "$SITES_DIR/$SITE_NAME" ]]; then
                log_error "Site '$SITE_NAME' already exists"
            else
                break
            fi
        else
            log_error "Invalid name. Use lowercase letters, numbers, hyphens."
        fi
    done

    # Site URL
    while true; do
        SITE_URL=$(prompt_value "Site URL (e.g., my-blog.com)")
        if validate_url "$SITE_URL" 2>/dev/null; then
            break
        else
            log_error "Invalid URL format"
        fi
    done

    # Template selection
    local templates=($(get_templates))
    if [[ ${#templates[@]} -eq 0 ]]; then
        log_error "No templates found in $TEMPLATES_DIR"
        exit 1
    fi

    echo ""
    log_info "Available templates:"
    for i in "${!templates[@]}"; do
        echo "  $((i + 1))) ${templates[$i]}"
    done

    while true; do
        local choice
        read -p "$(echo -e "${YELLOW}?${NC} Select template [1-${#templates[@]}]: ")" choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && [[ $choice -ge 1 ]] && [[ $choice -le ${#templates[@]} ]]; then
            TEMPLATE_NAME="${templates[$((choice - 1))]}"
            break
        fi
        echo "  Invalid choice."
    done
    log_ok "Template: $TEMPLATE_NAME"

    # Runtime version selection
    local runtime
    runtime=$(get_template_runtime "$TEMPLATE_NAME")

    case "$runtime" in
        php)
            echo ""
            log_info "Available PHP versions:"
            for i in "${!PHP_VERSIONS[@]}"; do
                local marker=""
                [[ "${PHP_VERSIONS[$i]}" == "$DEFAULT_PHP_VERSION" ]] && marker=" (default)"
                echo "  $((i + 1))) ${PHP_VERSIONS[$i]}$marker"
            done
            read -p "$(echo -e "${YELLOW}?${NC} Select PHP version [1-${#PHP_VERSIONS[@]}] (default: 1): ")" choice
            if [[ "$choice" =~ ^[0-9]+$ ]] && [[ $choice -ge 1 ]] && [[ $choice -le ${#PHP_VERSIONS[@]} ]]; then
                RUNTIME_VERSION="${PHP_VERSIONS[$((choice - 1))]}"
            else
                RUNTIME_VERSION="$DEFAULT_PHP_VERSION"
            fi
            log_ok "PHP version: $RUNTIME_VERSION"
            ;;
        nodejs)
            echo ""
            log_info "Available Node.js versions:"
            for i in "${!NODE_VERSIONS[@]}"; do
                local marker=""
                [[ "${NODE_VERSIONS[$i]}" == "$DEFAULT_NODE_VERSION" ]] && marker=" (default)"
                echo "  $((i + 1))) ${NODE_VERSIONS[$i]}$marker"
            done
            read -p "$(echo -e "${YELLOW}?${NC} Select Node.js version [1-${#NODE_VERSIONS[@]}] (default: 1): ")" choice
            if [[ "$choice" =~ ^[0-9]+$ ]] && [[ $choice -ge 1 ]] && [[ $choice -le ${#NODE_VERSIONS[@]} ]]; then
                RUNTIME_VERSION="${NODE_VERSIONS[$((choice - 1))]}"
            else
                RUNTIME_VERSION="$DEFAULT_NODE_VERSION"
            fi
            log_ok "Node.js version: $RUNTIME_VERSION"
            ;;
    esac

    # Framework selection
    FRAMEWORK_NAME=""
    local frameworks=($(get_frameworks))
    if [[ ${#frameworks[@]} -gt 0 ]]; then
        echo ""
        log_info "Available frameworks (optional):"
        echo "  0) None"
        for i in "${!frameworks[@]}"; do
            echo "  $((i + 1))) ${frameworks[$i]}"
        done

        read -p "$(echo -e "${YELLOW}?${NC} Select framework [0-${#frameworks[@]}]: ")" choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && [[ $choice -ge 1 ]] && [[ $choice -le ${#frameworks[@]} ]]; then
            FRAMEWORK_NAME="${frameworks[$((choice - 1))]}"
            log_ok "Framework: $FRAMEWORK_NAME"
        else
            log_info "No framework selected"
        fi
    fi

    # Resource limits
    echo ""
    read -p "$(echo -e "${YELLOW}?${NC} CPU limit [1]: ")" input
    CPU_LIMIT="${input:-1}"

    read -p "$(echo -e "${YELLOW}?${NC} Memory limit [512M]: ")" input
    MEMORY_LIMIT="${input:-512M}"

    # SSL option (only for traefik templates)
    if is_traefik_template "$TEMPLATE_NAME"; then
        echo ""
        if confirm "Use HTTPS with Let's Encrypt? (No for local dev)" "y"; then
            NO_SSL=false
        else
            NO_SSL=true
        fi

        # Domain aliases
        echo ""
        read -p "$(echo -e "${YELLOW}?${NC} Additional domains (comma-separated, or empty): ")" ALIASES
        if [[ -n "$ALIASES" ]]; then
            if confirm "Redirect aliases to main domain ($SITE_URL)?" "y"; then
                REDIRECT_ALIASES=true
            else
                REDIRECT_ALIASES=false
            fi
        fi
    fi

    # Database
    echo ""
    if confirm "Create database user for this site?" "y"; then
        CREATE_DB=true
    else
        CREATE_DB=false
    fi

    # Autostart with Docker
    if confirm "Auto-start container when Docker starts?" "y"; then
        NO_AUTOSTART=false
    else
        NO_AUTOSTART=true
    fi

    # Start container
    if confirm "Start container after creation?" "y"; then
        NO_START=false
    else
        NO_START=true
    fi

    # Summary
    echo ""
    print_header "Summary"
    echo "  Site name:  $SITE_NAME"
    echo "  URL:        $SITE_URL"
    echo "  Template:   $TEMPLATE_NAME"
    echo "  Version:    $RUNTIME_VERSION"
    [[ -n "$FRAMEWORK_NAME" ]] && echo "  Framework:  $FRAMEWORK_NAME"
    echo "  CPU:        $CPU_LIMIT"
    echo "  Memory:     $MEMORY_LIMIT"
    if is_traefik_template "$TEMPLATE_NAME"; then
        echo "  SSL:        $([[ "$NO_SSL" == false ]] && echo "yes (HTTPS)" || echo "no (HTTP)")"
    fi
    if [[ -n "$ALIASES" ]]; then
        echo "  Aliases:    $ALIASES"
        echo "  Redirect:   $([[ "$REDIRECT_ALIASES" == true ]] && echo "yes (301 to $SITE_URL)" || echo "no (same content)")"
    fi
    echo "  Database:   $CREATE_DB"
    echo "  Autostart:  $([[ "$NO_AUTOSTART" == false ]] && echo "yes (starts with Docker)" || echo "no (manual start only)")"
    echo "  Start now:  $([[ "$NO_START" == false ]] && echo "yes" || echo "no")"
    echo ""

    if ! confirm "Proceed with creation?" "y"; then
        log_info "Cancelled"
        exit 0
    fi
}

# =============================================================================
# ARGUMENTS
# =============================================================================

NO_START=false
NO_SSL=false
NO_AUTOSTART=false
CPU_LIMIT="1"
MEMORY_LIMIT="512M"
FRAMEWORK_NAME=""
CREATE_DB=false
INTERACTIVE=false
ALIASES=""
REDIRECT_ALIASES=false
RUNTIME_VERSION=""

# Parse arguments
POSITIONAL=()
while [[ $# -gt 0 ]]; do
    case $1 in
        --no-start)
            NO_START=true
            shift
            ;;
        --no-autostart)
            NO_AUTOSTART=true
            shift
            ;;
        --cpu)
            CPU_LIMIT="$2"
            shift 2
            ;;
        --memory)
            MEMORY_LIMIT="$2"
            shift 2
            ;;
        --php-version)
            RUNTIME_VERSION="$2"
            shift 2
            ;;
        --node-version)
            RUNTIME_VERSION="$2"
            shift 2
            ;;
        --framework)
            FRAMEWORK_NAME="$2"
            shift 2
            ;;
        --with-db)
            CREATE_DB=true
            shift
            ;;
        --no-ssl)
            NO_SSL=true
            shift
            ;;
        --aliases)
            ALIASES="$2"
            shift 2
            ;;
        --redirect-aliases)
            REDIRECT_ALIASES=true
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

# Decide mode: interactive or direct
if [[ $# -lt 3 ]]; then
    INTERACTIVE=true
    interactive_mode
else
    SITE_NAME="$1"
    SITE_URL="$2"
    TEMPLATE_NAME="$3"
fi

# =============================================================================
# RESOLVE DEFAULTS
# =============================================================================

RUNTIME=$(get_template_runtime "$TEMPLATE_NAME")

# Set default version if not specified
if [[ -z "$RUNTIME_VERSION" ]]; then
    case "$RUNTIME" in
        php)    RUNTIME_VERSION="$DEFAULT_PHP_VERSION" ;;
        nodejs) RUNTIME_VERSION="$DEFAULT_NODE_VERSION" ;;
    esac
fi

# =============================================================================
# VALIDATION
# =============================================================================

log_info "Validating parameters..."

if ! validate_site_params "$SITE_NAME" "$SITE_URL" "$TEMPLATE_NAME" "$CPU_LIMIT" "$MEMORY_LIMIT"; then
    exit 1
fi

# Validate runtime version
if ! validate_version "$RUNTIME" "$RUNTIME_VERSION"; then
    exit 1
fi

# Validate aliases
if [[ -n "$ALIASES" ]]; then
    if ! validate_aliases "$ALIASES" "$SITE_URL"; then
        exit 1
    fi
fi

# Validate framework if specified
if [[ -n "$FRAMEWORK_NAME" ]]; then
    if [[ ! -d "$FRAMEWORKS_DIR/$FRAMEWORK_NAME" ]]; then
        log_error "Framework '$FRAMEWORK_NAME' not found"
        exit 1
    fi
    if [[ -z "$(ls -A "$FRAMEWORKS_DIR/$FRAMEWORK_NAME" 2>/dev/null)" ]]; then
        log_error "Framework '$FRAMEWORK_NAME' is empty"
        exit 1
    fi
fi

# Ensure Docker network exists for traefik templates
if is_traefik_template "$TEMPLATE_NAME"; then
    require_docker
    ensure_web_network
fi

# Check port conflicts for standalone templates (early exit)
if [[ "$NO_START" == false ]]; then
    COMPOSE_TEMPLATE="$TEMPLATES_DIR/$TEMPLATE_NAME/compose.yaml"
    if ! check_standalone_ports "$TEMPLATE_NAME" "$COMPOSE_TEMPLATE"; then
        log_error "Required ports are already in use"
        log_info "Use --no-start to create the site without starting it"
        log_info "Or free the ports and try again"
        exit 1
    fi
fi

log_ok "Parameters validated"

# =============================================================================
# CREATION
# =============================================================================

print_header "Creating site '$SITE_NAME'"

NEW_SITE_DIR="$SITES_DIR/$SITE_NAME"

# Setup cleanup on error
set_cleanup_dir "$NEW_SITE_DIR"

# Copy template + shared Dockerfile
log_info "Copying template '$TEMPLATE_NAME'..."
copy_template "$TEMPLATE_NAME" "$NEW_SITE_DIR" "$RUNTIME_VERSION"

# Configure .env
log_info "Configuring environment..."
configure_env "$NEW_SITE_DIR" "$SITE_NAME" "$SITE_URL" "$RUNTIME" "$RUNTIME_VERSION"

# Configure compose.yaml
COMPOSE_FILE="$NEW_SITE_DIR/compose.yaml"
log_info "Configuring Docker service..."
configure_compose "$COMPOSE_FILE" "$SITE_NAME" "$CPU_LIMIT" "$MEMORY_LIMIT" "$NO_SSL" "$NO_AUTOSTART"

# Configure aliases
if is_traefik_template "$TEMPLATE_NAME" && [[ -n "$ALIASES" ]]; then
    configure_aliases "$COMPOSE_FILE" "$ALIASES" "$REDIRECT_ALIASES" "$NO_SSL"
fi

# Validate generated compose.yaml
validate_compose "$NEW_SITE_DIR"

# Install framework if specified
if [[ -n "$FRAMEWORK_NAME" ]]; then
    install_framework "$FRAMEWORK_NAME" "$NEW_SITE_DIR/app" "$SITE_NAME" "$SITE_URL" "$RUNTIME_VERSION"
fi

# Generate site manifest
generate_site_manifest "$NEW_SITE_DIR" "$SITE_NAME" "$SITE_URL" "$TEMPLATE_NAME" \
    "$RUNTIME_VERSION" "$CPU_LIMIT" "$MEMORY_LIMIT" "$NO_SSL" \
    "$FRAMEWORK_NAME" "$ALIASES" "$REDIRECT_ALIASES" "$NO_AUTOSTART"

# Disable cleanup (success)
clear_cleanup_dir

log_ok "Site '$SITE_NAME' created successfully"

# =============================================================================
# DATABASE
# =============================================================================

DB_RESULT_PASSWORD=""
if [[ "$CREATE_DB" == true ]]; then
    echo ""
    print_header "Creating database"
    create_site_database "$SITE_NAME" || true
fi

# =============================================================================
# START & SUMMARY
# =============================================================================

echo ""
print_header "Summary"
echo "  Location:  $NEW_SITE_DIR"
echo "  URL:       $SITE_URL"
echo "  Template:  $TEMPLATE_NAME"
echo "  Version:   $RUNTIME_VERSION ($RUNTIME)"
[[ -n "$FRAMEWORK_NAME" ]] && echo "  Framework: $FRAMEWORK_NAME"
echo "  Resources: CPU=$CPU_LIMIT, Memory=$MEMORY_LIMIT"

if [[ -n "$DB_RESULT_PASSWORD" ]]; then
    echo ""
    echo "  Database credentials:"
    echo "    Host:     mysql"
    echo "    Port:     3306"
    echo "    Database: $DB_RESULT_NAME"
    echo "    User:     $DB_RESULT_USER"
    echo "    Password: $DB_RESULT_PASSWORD"
    echo ""
    log_warn "Save these credentials! The password won't be shown again."
fi

if [[ "$NO_START" == true ]]; then
    echo ""
    log_info "To start the site:"
    echo "  cd $NEW_SITE_DIR && sudo docker compose up -d"
else
    echo ""
    log_info "Starting container..."
    if (cd "$NEW_SITE_DIR" && docker compose up -d --pull always --build); then
        log_ok "Container started"

        sleep 2
        echo ""
        log_info "Container status:"
        docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep -E "$SITE_NAME|NAMES"
    else
        log_error "Failed to start container"
        log_info "Check logs with: cd $NEW_SITE_DIR && docker compose logs"
        exit 1
    fi
fi

echo ""
log_info "Application files in: $NEW_SITE_DIR/app/"
