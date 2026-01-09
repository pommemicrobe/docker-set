#!/usr/bin/env bash
#
# site-create.sh - Create a new site from a template
#
# Usage:
#   ./scripts/site-create.sh                     # Interactive mode
#   ./scripts/site-create.sh <name> <url> <tpl>  # Direct mode
#

# Load common library
source "$(dirname "$0")/../lib/common.sh"

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
    echo "  --cpu <num>       CPU limit (e.g., 0.5, 1, 2). Default: 1"
    echo "  --memory <size>   Memory limit (e.g., 256M, 512M, 1G). Default: 512M"
    echo "  --framework <name> Framework to install (optional)"
    echo "  --with-db         Create database user for this site"
    echo "  --no-start        Don't start container after creation"
    echo "  --help, -h        Show this help"
    echo ""
    echo "Examples:"
    echo "  $0                                           # Interactive"
    echo "  $0 my-blog my-blog.com php-traefik          # Direct"
    echo "  $0 my-app app.com php-traefik --with-db     # With database"
    echo "  $0 my-app app.com php-traefik --framework laravel --with-db"
}

# =============================================================================
# DYNAMIC LISTS
# =============================================================================

# Get available templates
get_templates() {
    local templates=()
    for dir in "$TEMPLATES_DIR"/*/; do
        if [[ -d "$dir" ]]; then
            templates+=("$(basename "$dir")")
        fi
    done
    echo "${templates[@]}"
}

# Get available frameworks
get_frameworks() {
    local frameworks=()
    for dir in "$FRAMEWORKS_DIR"/*/; do
        if [[ -d "$dir" && -n "$(ls -A "$dir" 2>/dev/null)" ]]; then
            frameworks+=("$(basename "$dir")")
        fi
    done
    echo "${frameworks[@]}"
}

# =============================================================================
# INTERACTIVE PROMPTS
# =============================================================================

# Select from a list
select_option() {
    local prompt="$1"
    shift
    local options=("$@")
    local selected=0
    local key=""

    # Hide cursor
    tput civis 2>/dev/null || true

    while true; do
        # Clear and redraw
        echo -e "\n${YELLOW}?${NC} $prompt"
        for i in "${!options[@]}"; do
            if [[ $i -eq $selected ]]; then
                echo -e "  ${GREEN}› ${options[$i]}${NC}"
            else
                echo "    ${options[$i]}"
            fi
        done

        # Read single key
        read -rsn1 key

        case "$key" in
            A) # Up arrow
                ((selected--))
                [[ $selected -lt 0 ]] && selected=$((${#options[@]} - 1))
                ;;
            B) # Down arrow
                ((selected++))
                [[ $selected -ge ${#options[@]} ]] && selected=0
                ;;
            "") # Enter
                break
                ;;
        esac

        # Move cursor up to redraw
        tput cuu $((${#options[@]} + 2)) 2>/dev/null || true
        tput ed 2>/dev/null || true
    done

    # Show cursor
    tput cnorm 2>/dev/null || true

    echo "${options[$selected]}"
}

# Simple select for terminals without cursor control
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

# Interactive mode
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

    # Framework selection (only for PHP templates)
    FRAMEWORK_NAME=""
    if [[ "$TEMPLATE_NAME" == php-* ]]; then
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
    fi

    # Resource limits
    echo ""
    read -p "$(echo -e "${YELLOW}?${NC} CPU limit [1]: ")" input
    CPU_LIMIT="${input:-1}"

    read -p "$(echo -e "${YELLOW}?${NC} Memory limit [512M]: ")" input
    MEMORY_LIMIT="${input:-512M}"

    # Database
    echo ""
    if confirm "Create database user for this site?" "y"; then
        CREATE_DB=true
    else
        CREATE_DB=false
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
    [[ -n "$FRAMEWORK_NAME" ]] && echo "  Framework:  $FRAMEWORK_NAME"
    echo "  CPU:        $CPU_LIMIT"
    echo "  Memory:     $MEMORY_LIMIT"
    echo "  Database:   $CREATE_DB"
    echo "  Auto-start: $([[ "$NO_START" == false ]] && echo "yes" || echo "no")"
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
CPU_LIMIT="1"
MEMORY_LIMIT="512M"
FRAMEWORK_NAME=""
CREATE_DB=false
INTERACTIVE=false

# Parse arguments
POSITIONAL=()
while [[ $# -gt 0 ]]; do
    case $1 in
        --no-start)
            NO_START=true
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
        --framework)
            FRAMEWORK_NAME="$2"
            shift 2
            ;;
        --with-db)
            CREATE_DB=true
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
# VALIDATION
# =============================================================================

log_info "Validating parameters..."

# Validate site name
if ! validate_site_name "$SITE_NAME"; then
    exit 1
fi

# Validate URL
if ! validate_url "$SITE_URL"; then
    exit 1
fi

# Validate template
if ! validate_template_name "$TEMPLATE_NAME"; then
    exit 1
fi

# Validate CPU limit
if [[ ! "$CPU_LIMIT" =~ ^[0-9]+\.?[0-9]*$ ]]; then
    log_error "Invalid CPU limit: $CPU_LIMIT"
    log_error "Use a number like: 0.5, 1, 2"
    exit 1
fi

# Validate memory limit
if [[ ! "$MEMORY_LIMIT" =~ ^[0-9]+[MG]$ ]]; then
    log_error "Invalid memory limit: $MEMORY_LIMIT"
    log_error "Use format like: 256M, 512M, 1G"
    exit 1
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

# Check site doesn't already exist
if [[ -d "$SITES_DIR/$SITE_NAME" ]]; then
    log_error "Site '$SITE_NAME' already exists"
    log_info "To delete it: ./scripts/site-delete.sh $SITE_NAME"
    exit 1
fi

log_ok "Parameters validated"

# =============================================================================
# CREATION
# =============================================================================

print_header "Creating site '$SITE_NAME'"

TEMPLATE_DIR="$TEMPLATES_DIR/$TEMPLATE_NAME"
NEW_SITE_DIR="$SITES_DIR/$SITE_NAME"

# Setup cleanup on error
set_cleanup_dir "$NEW_SITE_DIR"

# Copy template
log_info "Copying template '$TEMPLATE_NAME'..."
cp -r "$TEMPLATE_DIR" "$NEW_SITE_DIR"
log_ok "Template copied"

# Rename .env.dist to .env
if [[ -f "$NEW_SITE_DIR/.env.dist" ]]; then
    mv "$NEW_SITE_DIR/.env.dist" "$NEW_SITE_DIR/.env"
    log_ok ".env file created"
fi

# Replace placeholders in .env
ENV_FILE="$NEW_SITE_DIR/.env"
if [[ -f "$ENV_FILE" ]]; then
    log_info "Configuring .env file..."
    sed_inplace "s|SITE_NAME=SITE_NAME|SITE_NAME=$SITE_NAME|g" "$ENV_FILE"
    sed_inplace "s|SITE_URL=SITE_URL|SITE_URL=$SITE_URL|g" "$ENV_FILE"
    log_ok "Environment variables configured"
fi

# Replace placeholders in compose.yaml
COMPOSE_FILE="$NEW_SITE_DIR/compose.yaml"
if [[ -f "$COMPOSE_FILE" ]]; then
    log_info "Configuring compose.yaml..."
    sed_inplace "s|SERVICE_NAME|$SITE_NAME|g" "$COMPOSE_FILE"
    sed_inplace "s|CPU_LIMIT|$CPU_LIMIT|g" "$COMPOSE_FILE"
    sed_inplace "s|MEMORY_LIMIT|$MEMORY_LIMIT|g" "$COMPOSE_FILE"
    log_ok "Docker service configured (CPU: $CPU_LIMIT, Memory: $MEMORY_LIMIT)"
fi

# Install framework if specified
if [[ -n "$FRAMEWORK_NAME" ]]; then
    log_info "Installing framework '$FRAMEWORK_NAME'..."
    APP_DIR="$NEW_SITE_DIR/app"
    mkdir -p "$APP_DIR"

    FRAMEWORK_DIR="$FRAMEWORKS_DIR/$FRAMEWORK_NAME"
    INSTALL_SCRIPT="$FRAMEWORK_DIR/install.sh"

    # Check for install.sh script
    if [[ -x "$INSTALL_SCRIPT" ]]; then
        # Execute framework's install script
        "$INSTALL_SCRIPT" "$APP_DIR" "$SITE_NAME" "$SITE_URL"
    else
        # Fallback: simple file copy
        cp -r "$FRAMEWORK_DIR"/* "$APP_DIR/"

        # Replace placeholders in framework files
        find "$APP_DIR" -type f \( -name "*.php" -o -name "*.js" -o -name "*.json" -o -name "*.env*" -o -name "*.yaml" -o -name "*.yml" -o -name ".htaccess" \) 2>/dev/null | while read -r file; do
            if grep -q "SITE_NAME\|SITE_URL" "$file" 2>/dev/null; then
                sed_inplace "s|SITE_NAME|$SITE_NAME|g; s|SITE_URL|$SITE_URL|g" "$file"
            fi
        done
    fi

    log_ok "Framework installed"
fi

# Disable cleanup (success)
clear_cleanup_dir

log_ok "Site '$SITE_NAME' created successfully"

# =============================================================================
# DATABASE
# =============================================================================

DB_PASSWORD=""
if [[ "$CREATE_DB" == true ]]; then
    echo ""
    print_header "Creating database"

    # Check MySQL is running
    if docker ps --format '{{.Names}}' | grep -q "^mysql$"; then
        # Get MySQL root password
        MYSQL_ENV_FILE="$CONFIG_DIR/mysql/.env"
        if [[ -f "$MYSQL_ENV_FILE" ]]; then
            MYSQL_ROOT_PASSWORD=$(grep "^MYSQL_ROOT_PASSWORD=" "$MYSQL_ENV_FILE" | cut -d'=' -f2)

            DB_NAME="${SITE_NAME//-/_}_db"
            DB_USER="${SITE_NAME//-/_}"
            DB_PASSWORD=$(generate_password 24)

            # Create database and user
            docker exec mysql mysql -u root -p"$MYSQL_ROOT_PASSWORD" -e "
                CREATE DATABASE IF NOT EXISTS \`$DB_NAME\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
                CREATE USER IF NOT EXISTS '$DB_USER'@'%' IDENTIFIED BY '$DB_PASSWORD';
                GRANT ALL PRIVILEGES ON \`$DB_NAME\`.* TO '$DB_USER'@'%';
                FLUSH PRIVILEGES;
            " 2>/dev/null

            if [[ $? -eq 0 ]]; then
                log_ok "Database '$DB_NAME' created"
                log_ok "User '$DB_USER' created"
            else
                log_warn "Failed to create database (MySQL error)"
            fi
        else
            log_warn "MySQL .env not found, skipping database creation"
        fi
    else
        log_warn "MySQL container not running, skipping database creation"
    fi
fi

# =============================================================================
# START
# =============================================================================

echo ""
print_header "Summary"
echo "  Location:  $NEW_SITE_DIR"
echo "  URL:       $SITE_URL"
echo "  Template:  $TEMPLATE_NAME"
[[ -n "$FRAMEWORK_NAME" ]] && echo "  Framework: $FRAMEWORK_NAME"
echo "  Resources: CPU=$CPU_LIMIT, Memory=$MEMORY_LIMIT"

if [[ -n "$DB_PASSWORD" ]]; then
    echo ""
    echo "  Database credentials:"
    echo "    Host:     mysql"
    echo "    Port:     3306"
    echo "    Database: ${SITE_NAME//-/_}_db"
    echo "    User:     ${SITE_NAME//-/_}"
    echo "    Password: $DB_PASSWORD"
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
    (cd "$NEW_SITE_DIR" && docker compose up -d)
    log_ok "Container started"

    # Show status
    sleep 2
    echo ""
    log_info "Container status:"
    docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep -E "$SITE_NAME|NAMES"
fi

echo ""
log_info "Application files in: $NEW_SITE_DIR/app/"
