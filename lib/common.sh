#!/usr/bin/env bash
#
# common.sh - Shared library for docker-set scripts
#
# Usage: source "$(dirname "$0")/../lib/common.sh"
#

set -euo pipefail

# =============================================================================
# COLORS
# =============================================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# =============================================================================
# PATHS
# =============================================================================
# Determine project root
if [[ -n "${PROJECT_ROOT:-}" ]]; then
    : # Already defined
elif [[ -n "${BASH_SOURCE[0]:-}" ]]; then
    _LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    PROJECT_ROOT="$(dirname "$_LIB_DIR")"
else
    PROJECT_ROOT="$(pwd)"
fi

TEMPLATES_DIR="$PROJECT_ROOT/templates"
FRAMEWORKS_DIR="$PROJECT_ROOT/frameworks"
SITES_DIR="$PROJECT_ROOT/sites"
CONFIG_DIR="$PROJECT_ROOT/config"
BACKUPS_DIR="$PROJECT_ROOT/backups"

# =============================================================================
# LOGGING
# =============================================================================
log_info()  { echo -e "${BLUE}i${NC}  $1"; }
log_ok()    { echo -e "${GREEN}✓${NC}  $1"; }
log_warn()  { echo -e "${YELLOW}!${NC}  $1"; }
log_error() { echo -e "${RED}✗${NC}  $1" >&2; }

# =============================================================================
# UTILITIES
# =============================================================================

# Cross-platform sed in-place (macOS vs Linux)
sed_inplace() {
    if [[ "$OSTYPE" == "darwin"* ]]; then
        sed -i '' "$@"
    else
        sed -i "$@"
    fi
}

# Generate random password using /dev/urandom
generate_password() {
    local length="${1:-32}"
    LC_ALL=C tr -dc 'A-Za-z0-9' < /dev/urandom | head -c "$length"
}

# =============================================================================
# VALIDATION
# =============================================================================

# Validate site name (alphanumeric + hyphens, must start/end with alphanumeric)
validate_site_name() {
    local name="$1"

    # Check allowed characters
    if [[ ! "$name" =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?$ ]]; then
        log_error "Invalid name: '$name'"
        log_error "Use only: lowercase letters, numbers, hyphens"
        log_error "Must start and end with a letter or number"
        return 1
    fi

    # Max length 63 (DNS/Docker limit)
    if [[ ${#name} -gt 63 ]]; then
        log_error "Name too long: ${#name} characters (max 63)"
        return 1
    fi

    # Min length 2
    if [[ ${#name} -lt 2 ]]; then
        log_error "Name too short: ${#name} character (min 2)"
        return 1
    fi

    return 0
}

# Validate URL/domain
validate_url() {
    local url="$1"

    # Accepts: domain.tld, sub.domain.tld, localhost, localhost:port
    if [[ ! "$url" =~ ^[a-zA-Z0-9]([a-zA-Z0-9.-]*[a-zA-Z0-9])?(:[0-9]+)?$ ]]; then
        log_error "Invalid URL: '$url'"
        log_error "Expected format: domain.com, sub.domain.com or localhost:3000"
        return 1
    fi

    return 0
}

# Validate template name
validate_template_name() {
    local name="$1"

    if [[ ! -d "$TEMPLATES_DIR/$name" ]]; then
        log_error "Template not found: '$name'"
        log_info "Available templates:"
        ls -1 "$TEMPLATES_DIR" 2>/dev/null | sed 's/^/  - /'
        return 1
    fi

    return 0
}

# =============================================================================
# USER INTERACTIONS
# =============================================================================

# Interactive confirmation prompt
confirm() {
    local message="${1:-Continue?}"
    local default="${2:-n}"  # n = no by default

    local prompt
    if [[ "$default" == "y" ]]; then
        prompt="[Y/n]"
    else
        prompt="[y/N]"
    fi

    read -p "$(echo -e "${YELLOW}?${NC}  $message $prompt ")" -n 1 -r
    echo

    if [[ -z "$REPLY" ]]; then
        [[ "$default" == "y" ]]
    else
        [[ $REPLY =~ ^[Yy]$ ]]
    fi
}

# Prompt user for a value
prompt_value() {
    local message="$1"
    local default="${2:-}"
    local result

    if [[ -n "$default" ]]; then
        read -p "$(echo -e "${YELLOW}?${NC}  $message [$default]: ")" result
        echo "${result:-$default}"
    else
        read -p "$(echo -e "${YELLOW}?${NC}  $message: ")" result
        echo "$result"
    fi
}

# =============================================================================
# DOCKER CHECKS
# =============================================================================

# Check that Docker is installed and accessible
require_docker() {
    if ! command -v docker &> /dev/null; then
        log_error "Docker is not installed"
        log_info "Install Docker: https://docs.docker.com/get-docker/"
        exit 1
    fi

    if ! docker info &> /dev/null; then
        log_error "Docker daemon is not accessible"
        log_info "Try with sudo or check that Docker is running"
        exit 1
    fi
}

# Check that the 'web' network exists
require_web_network() {
    if ! docker network ls --format '{{.Name}}' | grep -q "^web$"; then
        log_error "Docker network 'web' does not exist"
        log_info "Create it with: sudo docker network create web"
        exit 1
    fi
}

# Create the 'web' network if it doesn't exist
ensure_web_network() {
    if ! docker network ls --format '{{.Name}}' | grep -q "^web$"; then
        log_info "Creating Docker network 'web'..."
        docker network create web
        log_ok "Network 'web' created"
    fi
}

# =============================================================================
# ERROR HANDLING
# =============================================================================

# Variable to store the directory to clean up on error
_CLEANUP_DIR=""

# Cleanup function called on error
_cleanup_on_error() {
    local exit_code=$?
    if [[ $exit_code -ne 0 && -n "$_CLEANUP_DIR" && -d "$_CLEANUP_DIR" ]]; then
        log_warn "Cleaning up after error..."
        rm -rf "$_CLEANUP_DIR"
    fi
    exit $exit_code
}

# Enable automatic cleanup for a directory
set_cleanup_dir() {
    _CLEANUP_DIR="$1"
    trap _cleanup_on_error EXIT
}

# Disable cleanup (call after success)
clear_cleanup_dir() {
    _CLEANUP_DIR=""
    trap - EXIT
}

# =============================================================================
# DISPLAY
# =============================================================================

# Print a section header
print_header() {
    local title="$1"
    echo ""
    echo -e "${BLUE}=== $title ===${NC}"
    echo ""
}

# List available templates
list_templates() {
    log_info "Available templates:"
    for template in "$TEMPLATES_DIR"/*/; do
        if [[ -d "$template" ]]; then
            echo "  - $(basename "$template")"
        fi
    done
}

# List existing sites
list_sites() {
    log_info "Existing sites:"
    local count=0
    for site in "$SITES_DIR"/*/; do
        if [[ -d "$site" && "$(basename "$site")" != ".gitkeep" ]]; then
            echo "  - $(basename "$site")"
            ((count++)) || true
        fi
    done
    if [[ $count -eq 0 ]]; then
        echo "  (no sites)"
    fi
}
