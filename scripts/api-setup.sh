#!/usr/bin/env bash
#
# api-setup.sh - Set up the docker-set control plane API (config/api)
#
# Creates config/api/.env from .env.dist if absent (DOCKER_SET_ROOT filled
# with the repository path, API_TOKEN and WEBHOOK_SECRET generated), then
# builds and starts the API container and waits for /health.
# The API binds to 127.0.0.1:9000 only — reach /api through SSH or a tunnel.
#
# Usage:
#   ./scripts/api-setup.sh              # Create .env if absent, build, start
#   ./scripts/api-setup.sh --no-start   # Prepare config/api/.env only
#   ./scripts/api-setup.sh --force      # Regenerate .env (backup to .env.bak)
#

# Load common library
source "$(dirname "$0")/../lib/common.sh"

API_DIR="$CONFIG_DIR/api"
API_URL="http://127.0.0.1:9000"
HEALTH_RETRIES=30

# Options
FORCE=false
NO_START=false

# Token generated during this run (printed once in the summary, empty when
# an existing .env was kept)
GENERATED_TOKEN=""

# =============================================================================
# HELP
# =============================================================================

show_help() {
    cat <<EOF
Usage: $0 [options]

Set up the docker-set control plane API (config/api).

Creates config/api/.env from .env.dist if absent — DOCKER_SET_ROOT set to
this repository, API_TOKEN and WEBHOOK_SECRET generated (openssl rand),
permissions 600 — then builds and starts the API container and waits for
$API_URL/health. An existing .env is never overwritten without --force.

Options:
  --no-start     Prepare config/api/.env only (no build, no start)
  --force        Regenerate .env even if it exists (old file saved to .env.bak)
  --help, -h     Show this help

The API listens on $API_URL (localhost only). Secrets live in
config/api/.env (chmod 600, gitignored).
EOF
}

# =============================================================================
# HELPERS
# =============================================================================

# Generate a 64-hex-char (32-byte) secret. openssl preferred; /dev/urandom
# with xxd or od as fallbacks. The server refuses secrets shorter than 32.
generate_secret() {
    local secret=""
    if command -v openssl >/dev/null 2>&1; then
        secret=$(openssl rand -hex 32)
    elif command -v xxd >/dev/null 2>&1; then
        secret=$(head -c 32 /dev/urandom | xxd -p | tr -d '[:space:]')
    elif command -v od >/dev/null 2>&1; then
        secret=$(head -c 32 /dev/urandom | od -An -tx1 | tr -d '[:space:]')
    fi

    if [[ ${#secret} -lt 32 ]]; then
        log_error "Secret generation failed (need openssl, xxd or od)"
        exit 1
    fi
    printf '%s' "$secret"
}

# =============================================================================
# STEPS
# =============================================================================

# Create config/api/.env from .env.dist: fill DOCKER_SET_ROOT, generate both
# secrets, chmod 600. Refuses to overwrite an existing .env without --force
# (--force backs it up to .env.bak first).
ensure_env() {
    local env_file="$API_DIR/.env"

    if [[ ! -f "$API_DIR/.env.dist" ]]; then
        log_error "Missing $API_DIR/.env.dist"
        exit 1
    fi

    if [[ -f "$env_file" ]]; then
        if [[ "$FORCE" != true ]]; then
            log_warn "config/api/.env already exists — keeping it (use --force to regenerate)"
            return 0
        fi
        cp "$env_file" "$env_file.bak"
        chmod 600 "$env_file.bak"
        log_warn "Existing config/api/.env backed up to config/api/.env.bak"
    fi

    log_info "Creating config/api/.env from .env.dist..."
    cp "$API_DIR/.env.dist" "$env_file"
    chmod 600 "$env_file"

    local webhook_secret
    GENERATED_TOKEN=$(generate_secret)
    webhook_secret=$(generate_secret)

    sed_inplace "s|^DOCKER_SET_ROOT=.*|DOCKER_SET_ROOT=$(sed_escape "$PROJECT_ROOT")|" "$env_file"
    sed_inplace "s|^API_TOKEN=.*|API_TOKEN=$(sed_escape "$GENERATED_TOKEN")|" "$env_file"
    sed_inplace "s|^WEBHOOK_SECRET=.*|WEBHOOK_SECRET=$(sed_escape "$webhook_secret")|" "$env_file"

    log_ok "config/api/.env created (permissions 600)"
    log_ok "DOCKER_SET_ROOT=$PROJECT_ROOT"
}

# Build the image (gofmt/go vet run inside the build) and (re)create the
# container.
build_and_start() {
    log_info "Building and starting the control plane API..."
    if (cd "$API_DIR" && docker compose up -d --build); then
        log_ok "Container docker-set-api started"
    else
        log_error "Failed to build/start the API container"
        exit 1
    fi
}

# Poll the unauthenticated /health endpoint until it answers (bounded).
wait_for_health() {
    if ! command -v curl >/dev/null 2>&1; then
        log_warn "curl not found on host — skipping the health check"
        log_info "Check manually: cd config/api && docker compose logs"
        return 0
    fi

    log_info "Waiting for the API to become healthy..."
    local i
    for ((i = 0; i < HEALTH_RETRIES; i++)); do
        if curl -fsS "$API_URL/health" >/dev/null 2>&1; then
            log_ok "API healthy ($API_URL/health)"
            return 0
        fi
        sleep 1
    done

    log_error "API did not answer on $API_URL/health within ${HEALTH_RETRIES}s"
    log_info "Inspect the logs: cd config/api && docker compose logs"
    exit 1
}

# Print the API token exactly once, right after generation. On repeat runs
# (existing .env kept) the token is not re-read or echoed.
print_token_notice() {
    if [[ -n "$GENERATED_TOKEN" ]]; then
        log_warn "IMPORTANT: Save this API token — it will not be shown again"
        echo "  API_TOKEN=$GENERATED_TOKEN"
    else
        log_info "API token unchanged (stored in config/api/.env)"
    fi
    echo ""
}

print_summary() {
    print_header "Control Plane API Ready"

    log_info "API URL: $API_URL (localhost only — reach /api via SSH or a tunnel)"
    echo ""

    print_token_notice

    log_info "Try it:"
    echo "  curl -H \"Authorization: Bearer \$API_TOKEN\" $API_URL/api/sites"
    echo ""

    log_info "GitHub webhook (auto-deploy on push):"
    echo "  Payload URL:  https://<your-host>/hooks/github/<site-name>"
    echo "  Content type: application/json"
    echo "  Secret:       the WEBHOOK_SECRET value in config/api/.env"
    echo "  Events:       Just the push event"
    echo ""
    echo "  Public exposure: uncomment the Traefik labels block in"
    echo "  config/api/compose.yaml (routes /hooks/ only — /api stays private)."
}

# =============================================================================
# MAIN
# =============================================================================

main() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --no-start)
                NO_START=true
                shift
                ;;
            --force)
                FORCE=true
                shift
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                echo ""
                show_help
                exit 1
                ;;
        esac
    done

    print_header "Control Plane API Setup"

    ensure_env

    if [[ "$NO_START" == true ]]; then
        echo ""
        print_token_notice
        log_info "Start it later: ./scripts/api-setup.sh"
        exit 0
    fi

    require_docker
    build_and_start
    wait_for_health
    print_summary
}

main "$@"
