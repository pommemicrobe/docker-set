#!/usr/bin/env bash
#
# default-site.sh - Configure default response for direct IP access
#
# Usage:
#   ./scripts/default-site.sh                    # Interactive mode
#   ./scripts/default-site.sh --mode <mode>      # Direct mode
#

# Load common library
source "$(dirname "$0")/../lib/common.sh"

# =============================================================================
# HELP
# =============================================================================

show_help() {
    echo "Usage: $0 [options]"
    echo ""
    echo "Configure what happens when someone accesses the server by IP address."
    echo ""
    echo "Options:"
    echo "  --mode <mode>     Response mode: 'page', 'redirect', '404', 'disable'"
    echo "  --redirect-url <url>  URL to redirect to (required for 'redirect' mode)"
    echo "  --page-title <title>  Title for default page (optional for 'page' mode)"
    echo "  --page-message <msg>  Message for default page (optional for 'page' mode)"
    echo "  --no-ssl          Use HTTP instead of HTTPS"
    echo "  --help, -h        Show this help"
    echo ""
    echo "Modes:"
    echo "  page      Show a static page (default)"
    echo "  redirect  Redirect to a specific URL"
    echo "  404       Return 404 Not Found"
    echo "  disable   Remove default site configuration"
    echo ""
    echo "Examples:"
    echo "  $0                                              # Interactive"
    echo "  $0 --mode page                                  # Default page (HTTPS)"
    echo "  $0 --mode page --no-ssl                         # Default page (HTTP)"
    echo "  $0 --mode redirect --redirect-url https://example.com"
    echo "  $0 --mode 404                                   # Return 404"
    echo "  $0 --mode disable                               # Remove config"
}

# =============================================================================
# CONFIGURATION
# =============================================================================

DEFAULT_SITE_DIR="$CONFIG_DIR/default-site"
DEFAULT_SITE_COMPOSE="$DEFAULT_SITE_DIR/compose.yaml"

# =============================================================================
# FUNCTIONS
# =============================================================================

create_default_page() {
    local title="${1:-Welcome}"
    local message="${2:-This server is running.}"

    mkdir -p "$DEFAULT_SITE_DIR/html"

    cat > "$DEFAULT_SITE_DIR/html/index.html" << EOF
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>$title</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            min-height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
        }
        .container {
            text-align: center;
            padding: 2rem;
        }
        h1 { font-size: 3rem; margin-bottom: 1rem; }
        p { font-size: 1.25rem; opacity: 0.9; }
    </style>
</head>
<body>
    <div class="container">
        <h1>$title</h1>
        <p>$message</p>
    </div>
</body>
</html>
EOF
}

create_compose_page() {
    local entrypoint="websecure"
    if [[ "$NO_SSL" == true ]]; then
        entrypoint="web"
    fi

    cat > "$DEFAULT_SITE_COMPOSE" << EOF
services:
  default-site:
    image: nginx:alpine
    container_name: default-site
    restart: always
    volumes:
      - ./html:/usr/share/nginx/html:ro
    labels:
      - "traefik.enable=true"
      # Catch-all rule with lowest priority
      - "traefik.http.routers.default-site.rule=PathPrefix(\`/\`)"
      - "traefik.http.routers.default-site.priority=1"
      - "traefik.http.routers.default-site.entrypoints=$entrypoint"
      - "traefik.http.services.default-site.loadbalancer.server.port=80"
    networks:
      - web

networks:
  web:
    external: true
EOF
}

create_compose_redirect() {
    local redirect_url="$1"
    local entrypoint="websecure"
    if [[ "$NO_SSL" == true ]]; then
        entrypoint="web"
    fi

    cat > "$DEFAULT_SITE_COMPOSE" << EOF
services:
  default-site:
    image: traefik/whoami
    container_name: default-site
    restart: always
    labels:
      - "traefik.enable=true"
      # Catch-all rule with lowest priority
      - "traefik.http.routers.default-site.rule=PathPrefix(\`/\`)"
      - "traefik.http.routers.default-site.priority=1"
      - "traefik.http.routers.default-site.entrypoints=$entrypoint"
      - "traefik.http.routers.default-site.middlewares=default-redirect"
      - "traefik.http.middlewares.default-redirect.redirectregex.regex=^https?://.*"
      - "traefik.http.middlewares.default-redirect.redirectregex.replacement=$redirect_url"
      - "traefik.http.middlewares.default-redirect.redirectregex.permanent=false"
      - "traefik.http.services.default-site.loadbalancer.server.port=80"
    networks:
      - web

networks:
  web:
    external: true
EOF
}

create_compose_404() {
    mkdir -p "$DEFAULT_SITE_DIR/html"

    local entrypoint="websecure"
    if [[ "$NO_SSL" == true ]]; then
        entrypoint="web"
    fi

    cat > "$DEFAULT_SITE_DIR/html/index.html" << 'EOF'
<!DOCTYPE html>
<html>
<head><title>404 Not Found</title></head>
<body><h1>404 Not Found</h1></body>
</html>
EOF

    cat > "$DEFAULT_SITE_DIR/nginx.conf" << 'EOF'
server {
    listen 80;
    location / {
        return 404;
    }
}
EOF

    cat > "$DEFAULT_SITE_COMPOSE" << EOF
services:
  default-site:
    image: nginx:alpine
    container_name: default-site
    restart: always
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
      - ./html:/usr/share/nginx/html:ro
    labels:
      - "traefik.enable=true"
      # Catch-all rule with lowest priority
      - "traefik.http.routers.default-site.rule=PathPrefix(\`/\`)"
      - "traefik.http.routers.default-site.priority=1"
      - "traefik.http.routers.default-site.entrypoints=$entrypoint"
      - "traefik.http.services.default-site.loadbalancer.server.port=80"
    networks:
      - web

networks:
  web:
    external: true
EOF
}

disable_default_site() {
    if [[ -d "$DEFAULT_SITE_DIR" ]]; then
        # Stop container if running
        if docker ps --format '{{.Names}}' | grep -q "^default-site$"; then
            log_info "Stopping default-site container..."
            (cd "$DEFAULT_SITE_DIR" && docker compose down 2>/dev/null)
        fi

        # Remove directory
        rm -rf "$DEFAULT_SITE_DIR"
        log_ok "Default site configuration removed"
    else
        log_info "Default site is not configured"
    fi
}

# =============================================================================
# INTERACTIVE MODE
# =============================================================================

interactive_mode() {
    print_header "Configure Default Site"

    echo ""
    log_info "What should happen when someone accesses the server by IP?"
    echo "  1) Show a static page"
    echo "  2) Redirect to a URL"
    echo "  3) Return 404 Not Found"
    echo "  4) Disable (remove configuration)"

    local choice
    while true; do
        read -p "$(echo -e "${YELLOW}?${NC} Select option [1-4]: ")" choice
        case "$choice" in
            1) MODE="page"; break ;;
            2) MODE="redirect"; break ;;
            3) MODE="404"; break ;;
            4) MODE="disable"; break ;;
            *) echo "  Invalid choice." ;;
        esac
    done

    if [[ "$MODE" == "page" ]]; then
        echo ""
        read -p "$(echo -e "${YELLOW}?${NC} Page title [Welcome]: ")" PAGE_TITLE
        PAGE_TITLE="${PAGE_TITLE:-Welcome}"

        read -p "$(echo -e "${YELLOW}?${NC} Page message [This server is running.]: ")" PAGE_MESSAGE
        PAGE_MESSAGE="${PAGE_MESSAGE:-This server is running.}"
    fi

    if [[ "$MODE" == "redirect" ]]; then
        echo ""
        while true; do
            read -p "$(echo -e "${YELLOW}?${NC} Redirect URL: ")" REDIRECT_URL
            if [[ -n "$REDIRECT_URL" ]]; then
                break
            fi
            log_error "URL is required"
        done
    fi

    # SSL option (only for non-disable modes)
    if [[ "$MODE" != "disable" ]]; then
        echo ""
        if confirm "Use HTTPS? (No for local development)" "y"; then
            NO_SSL=false
        else
            NO_SSL=true
        fi
    fi
}

# =============================================================================
# ARGUMENTS
# =============================================================================

MODE=""
REDIRECT_URL=""
PAGE_TITLE="Welcome"
PAGE_MESSAGE="This server is running."
NO_SSL=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --mode)
            MODE="$2"
            shift 2
            ;;
        --redirect-url)
            REDIRECT_URL="$2"
            shift 2
            ;;
        --page-title)
            PAGE_TITLE="$2"
            shift 2
            ;;
        --page-message)
            PAGE_MESSAGE="$2"
            shift 2
            ;;
        --no-ssl)
            NO_SSL=true
            shift
            ;;
        --help|-h)
            show_help
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Interactive mode if no mode specified
if [[ -z "$MODE" ]]; then
    interactive_mode
fi

# Validate mode
case "$MODE" in
    page|redirect|404|disable) ;;
    *)
        log_error "Invalid mode: $MODE"
        log_error "Use: page, redirect, 404, or disable"
        exit 1
        ;;
esac

# Validate redirect URL
if [[ "$MODE" == "redirect" ]] && [[ -z "$REDIRECT_URL" ]]; then
    log_error "Redirect URL is required for redirect mode"
    log_error "Use: --redirect-url <url>"
    exit 1
fi

# =============================================================================
# EXECUTION
# =============================================================================

print_header "Configuring default site"

# Disable first if reconfiguring
if [[ "$MODE" != "disable" ]] && [[ -d "$DEFAULT_SITE_DIR" ]]; then
    log_info "Removing existing configuration..."
    disable_default_site
fi

case "$MODE" in
    page)
        log_info "Creating default page..."
        mkdir -p "$DEFAULT_SITE_DIR"
        create_default_page "$PAGE_TITLE" "$PAGE_MESSAGE"
        create_compose_page
        log_ok "Default page created"
        ;;

    redirect)
        log_info "Configuring redirect to $REDIRECT_URL..."
        mkdir -p "$DEFAULT_SITE_DIR"
        create_compose_redirect "$REDIRECT_URL"
        log_ok "Redirect configured"
        ;;

    404)
        log_info "Configuring 404 response..."
        mkdir -p "$DEFAULT_SITE_DIR"
        create_compose_404
        log_ok "404 response configured"
        ;;

    disable)
        disable_default_site
        exit 0
        ;;
esac

# Start container
log_info "Starting default-site container..."
if (cd "$DEFAULT_SITE_DIR" && docker compose up -d); then
    log_ok "Default site is now active"
    echo ""
    log_info "Configuration: $DEFAULT_SITE_DIR"
    log_info "To modify: edit files and run 'docker compose restart'"
    log_info "To disable: $0 --mode disable"
else
    log_error "Failed to start container"
    exit 1
fi
