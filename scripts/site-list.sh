#!/usr/bin/env bash
#
# site-list.sh - List all sites and their status
#
# Usage: ./scripts/site-list.sh [--json]
#

# Load libraries
source "$(dirname "$0")/../lib/common.sh"

# =============================================================================
# HELP
# =============================================================================

show_help() {
    echo "Usage: $0 [options]"
    echo ""
    echo "List all sites and their current status."
    echo ""
    echo "Options:"
    echo "  --json       Output as JSON"
    echo "  --help, -h   Show this help"
}

# =============================================================================
# ARGUMENTS
# =============================================================================

JSON_OUTPUT=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --json)
            JSON_OUTPUT=true
            shift
            ;;
        --help|-h)
            show_help
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# =============================================================================
# LIST SITES
# =============================================================================

# Check if any sites exist
site_count=0
for site_dir in "$SITES_DIR"/*/; do
    [[ -d "$site_dir" ]] || continue
    name=$(basename "$site_dir")
    [[ "$name" == ".gitkeep" ]] && continue
    ((site_count++)) || true
done

if [[ $site_count -eq 0 ]]; then
    if [[ "$JSON_OUTPUT" == true ]]; then
        echo "[]"
    else
        log_info "No sites found"
        log_info "Create one with: ./scripts/site-create.sh"
    fi
    exit 0
fi

# JSON output
if [[ "$JSON_OUTPUT" == true ]]; then
    echo "["
    first=true
    for site_dir in "$SITES_DIR"/*/; do
        [[ -d "$site_dir" ]] || continue
        name=$(basename "$site_dir")
        [[ "$name" == ".gitkeep" ]] && continue

        # Get container status
        status="stopped"
        if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${name}$"; then
            status="running"
        elif docker ps -a --format '{{.Names}}' 2>/dev/null | grep -q "^${name}$"; then
            status="exited"
        fi

        # Read URL from .env
        url=""
        if [[ -f "$site_dir/.env" ]]; then
            url=$(grep "^SITE_URL=" "$site_dir/.env" 2>/dev/null | cut -d'=' -f2)
        fi

        # Read template from site.yaml
        template=""
        if [[ -f "$site_dir/site.yaml" ]]; then
            template=$(grep "^template:" "$site_dir/site.yaml" 2>/dev/null | sed 's/template: *"\?\([^"]*\)"\?/\1/')
        fi

        [[ "$first" == true ]] || echo ","
        first=false
        printf '  {"name":"%s","url":"%s","template":"%s","status":"%s"}' "$name" "$url" "$template" "$status"
    done
    echo ""
    echo "]"
    exit 0
fi

# Table output
print_header "Sites"

printf "  %-20s %-30s %-20s %s\n" "NAME" "URL" "TEMPLATE" "STATUS"
printf "  %-20s %-30s %-20s %s\n" "----" "---" "--------" "------"

for site_dir in "$SITES_DIR"/*/; do
    [[ -d "$site_dir" ]] || continue
    name=$(basename "$site_dir")
    [[ "$name" == ".gitkeep" ]] && continue

    # Get container status
    status="${RED}stopped${NC}"
    if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${name}$"; then
        status="${GREEN}running${NC}"
    elif docker ps -a --format '{{.Names}}' 2>/dev/null | grep -q "^${name}$"; then
        status="${YELLOW}exited${NC}"
    fi

    # Read URL from .env
    url="-"
    if [[ -f "$site_dir/.env" ]]; then
        url=$(grep "^SITE_URL=" "$site_dir/.env" 2>/dev/null | cut -d'=' -f2)
        [[ -z "$url" ]] && url="-"
    fi

    # Read template from site.yaml
    template="-"
    if [[ -f "$site_dir/site.yaml" ]]; then
        template=$(grep "^template:" "$site_dir/site.yaml" 2>/dev/null | sed 's/template: *"\?\([^"]*\)"\?/\1/')
        [[ -z "$template" ]] && template="-"
    fi

    printf "  %-20s %-30s %-20s " "$name" "$url" "$template"
    echo -e "$status"
done

echo ""
echo "  Total: $site_count site(s)"
