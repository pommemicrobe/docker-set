#!/usr/bin/env bash
#
# site-run.sh - Run a one-off command inside a site's container
#
# Runs the command through docker compose exec so runtimes and their tooling
# (composer, npm, bun, go...) never need to be installed on the host.
# The command's exit code is preserved as this script's exit code.
#
# Usage:
#   ./scripts/site-run.sh <name> <command...>
#   ./scripts/site-run.sh <name> -- <command with flags...>
#

# Load libraries
source "$(dirname "$0")/../lib/common.sh"
source "$(dirname "$0")/../lib/site.sh"

# =============================================================================
# HELP
# =============================================================================

show_help() {
    echo "Usage: $0 <site-name> [--] <command...>"
    echo ""
    echo "Run a one-off command inside a site's running container."
    echo "Everything after the site name is executed through 'sh -lc' in the"
    echo "container's working directory. The command's exit code is preserved."
    echo ""
    echo "Use '--' after the site name to pass flags to the command untouched."
    echo ""
    echo "Options:"
    echo "  --help, -h   Show this help"
    echo ""
    echo "Examples:"
    echo "  $0 my-blog composer install"
    echo "  $0 my-app npm run build"
    echo "  $0 my-api bun test"
    echo "  $0 my-app -- npm run build --verbose"
    echo "  $0 my-blog 'php -v && composer --version'"
    echo ""
    echo "Existing sites:"
    list_sites
}

# =============================================================================
# ARGUMENTS
# =============================================================================

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    show_help
    exit 0
fi

if [[ $# -lt 1 ]]; then
    log_error "Missing site name"
    echo ""
    show_help
    exit 1
fi

SITE_NAME="$1"
shift

# Optional -- separator: everything after it goes to the command untouched
[[ "${1:-}" == "--" ]] && shift

if [[ $# -lt 1 ]]; then
    log_error "Missing command to run"
    log_info "Example: $0 $SITE_NAME npm run build"
    exit 1
fi

COMMAND="$*"

require_docker

# =============================================================================
# VALIDATION
# =============================================================================

if ! validate_site_name "$SITE_NAME"; then
    exit 1
fi

SITE_DIR="$SITES_DIR/$SITE_NAME"
if [[ ! -d "$SITE_DIR" ]]; then
    log_error "Site '$SITE_NAME' does not exist"
    echo ""
    list_sites
    exit 1
fi
if [[ ! -f "$SITE_DIR/compose.yaml" ]]; then
    log_error "Site '$SITE_NAME' has no compose.yaml"
    exit 1
fi

if ! docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${SITE_NAME}$"; then
    log_error "Container '$SITE_NAME' is not running"
    log_info "Start it with: cd sites/$SITE_NAME && sudo docker compose up -d"
    exit 1
fi

# =============================================================================
# RUN
# =============================================================================

# Prod containers run from a baked image with no ./app bind mount: anything
# changed inside is lost when the container is recreated. Warn on stderr so
# the command's stdout stays clean for pipes.
MODE=$(manifest_get "$SITE_DIR" "mode" || true)
if [[ "${MODE:-dev}" == "prod" ]]; then
    log_warn "Site is in prod mode: the container filesystem is immutable - changes are lost on redeploy" >&2
fi

cd "$SITE_DIR" || exit 1
# -T: no TTY allocation, keeps stdin/stdout usable in pipes and scripts.
# exec preserves the command's exit code as ours.
exec docker compose exec -T "$SITE_NAME" sh -lc "$COMMAND"
