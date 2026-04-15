#!/usr/bin/env bash
#
# site.sh - Site creation and configuration for docker-set
#
# Usage: source "$(dirname "$0")/../lib/site.sh"
# Requires: common.sh to be sourced first
#

# =============================================================================
# VERSION CONSTANTS
# =============================================================================

PHP_VERSIONS=("8.4" "8.3" "8.2")
DEFAULT_PHP_VERSION="8.4"

NODE_VERSIONS=("24" "22")
DEFAULT_NODE_VERSION="24"

BUN_VERSIONS=("1.3" "1")
DEFAULT_BUN_VERSION="1.3"

# =============================================================================
# TEMPLATE HELPERS
# =============================================================================

# Determine runtime type from template name
# Usage: get_template_runtime <template_name>
get_template_runtime() {
    local template="$1"
    case "$template" in
        php-*)    echo "php" ;;
        nodejs-*) echo "nodejs" ;;
        bun-*)    echo "bun" ;;
        *)        echo "unknown" ;;
    esac
}

# Get available templates
# Usage: get_templates
get_templates() {
    local templates=()
    for dir in "$TEMPLATES_DIR"/*/; do
        if [[ -d "$dir" && "$(basename "$dir")" != "dockerfiles" ]]; then
            templates+=("$(basename "$dir")")
        fi
    done
    echo "${templates[@]}"
}

# Check if template is traefik-based
# Usage: is_traefik_template <template_name>
is_traefik_template() {
    [[ "$1" == *-traefik ]]
}

# Check if template is standalone
# Usage: is_standalone_template <template_name>
is_standalone_template() {
    [[ "$1" == *-standalone ]]
}

# =============================================================================
# VALIDATION
# =============================================================================

# Validate runtime version
# Usage: validate_version <runtime> <version>
validate_version() {
    local runtime="$1"
    local version="$2"

    local -a versions
    case "$runtime" in
        php)    versions=("${PHP_VERSIONS[@]}") ;;
        nodejs) versions=("${NODE_VERSIONS[@]}") ;;
        bun)    versions=("${BUN_VERSIONS[@]}") ;;
        *)
            log_error "Unknown runtime: $runtime"
            return 1
            ;;
    esac

    for v in "${versions[@]}"; do
        if [[ "$v" == "$version" ]]; then
            return 0
        fi
    done

    log_error "Invalid $runtime version: $version"
    log_info "Available versions: ${versions[*]}"
    return 1
}

# Validate all site creation parameters
# Usage: validate_site_params <name> <url> <template> <cpu> <memory>
validate_site_params() {
    local name="$1"
    local url="$2"
    local template="$3"
    local cpu="$4"
    local memory="$5"

    if ! validate_site_name "$name"; then
        return 1
    fi

    if ! validate_url "$url"; then
        return 1
    fi

    if ! validate_template_name "$template"; then
        return 1
    fi

    # Validate CPU limit
    if [[ ! "$cpu" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
        log_error "Invalid CPU limit: $cpu"
        log_info "Use a number like: 0.5, 1, 2"
        return 1
    fi

    # Validate memory limit (accept lowercase too)
    if [[ ! "$memory" =~ ^[0-9]+[MmGg]$ ]]; then
        log_error "Invalid memory limit: $memory"
        log_info "Use format like: 256M, 512M, 1G"
        return 1
    fi

    # Validate CPU minimum value
    if [[ $(echo "$cpu <= 0" | bc -l 2>/dev/null || echo "0") == "1" ]]; then
        log_error "CPU limit must be greater than 0"
        return 1
    fi

    # Check site doesn't already exist
    if [[ -d "$SITES_DIR/$name" ]]; then
        log_error "Site '$name' already exists"
        log_info "To delete it: ./scripts/site-delete.sh $name"
        return 1
    fi

    return 0
}

# Validate alias domains
# Usage: validate_aliases <aliases_csv> <main_url>
validate_aliases() {
    local aliases_csv="$1"
    local main_url="$2"

    [[ -z "$aliases_csv" ]] && return 0

    local -a alias_array
    IFS=',' read -ra alias_array <<< "$aliases_csv"

    for alias_domain in "${alias_array[@]}"; do
        alias_domain=$(echo "$alias_domain" | xargs)
        [[ -z "$alias_domain" ]] && continue

        # Validate format
        if ! validate_url "$alias_domain"; then
            log_error "Invalid alias domain: '$alias_domain'"
            return 1
        fi

        # Check alias is not the same as main domain
        if [[ "$alias_domain" == "$main_url" ]]; then
            log_error "Alias '$alias_domain' is the same as the main URL (would cause redirect loop)"
            return 1
        fi
    done

    return 0
}

# Detect if a port is already being listened on
# Usage: check_port_conflict <port>
check_port_conflict() {
    local port="$1"

    if command -v lsof &>/dev/null; then
        if lsof -iTCP:"$port" -sTCP:LISTEN -P -n &>/dev/null; then
            log_warn "Port $port is already in use"
            return 1
        fi
    elif command -v ss &>/dev/null; then
        if ss -tlnp | grep -q ":${port} " 2>/dev/null; then
            log_warn "Port $port is already in use"
            return 1
        fi
    fi

    return 0
}

# Check for port conflicts on standalone templates
# Usage: check_standalone_ports <template_name> <compose_file>
# Returns: 0 if no conflict (or not standalone), 1 if ports are in use
check_standalone_ports() {
    local template="$1"
    local compose_file="$2"

    if ! is_standalone_template "$template"; then
        return 0
    fi

    local has_conflict=false

    # Extract ports from compose.yaml
    local ports
    ports=$(grep -Eo '"([0-9]+):[0-9]+"' "$compose_file" 2>/dev/null | grep -Eo '^"[0-9]+' | tr -d '"')

    for port in $ports; do
        if ! check_port_conflict "$port"; then
            has_conflict=true
        fi
    done

    if [[ "$has_conflict" == true ]]; then
        return 1
    fi

    return 0
}

# =============================================================================
# SITE CREATION
# =============================================================================

# Copy template and shared Dockerfile to site directory
# Usage: copy_template <template_name> <site_dir> <runtime_version>
copy_template() {
    local template_name="$1"
    local site_dir="$2"
    local runtime_version="$3"

    local template_dir="$TEMPLATES_DIR/$template_name"
    local runtime
    runtime=$(get_template_runtime "$template_name")

    # Copy template files (compose.yaml, .env.dist)
    cp -r "$template_dir" "$site_dir"

    # Copy shared Dockerfile
    local dockerfile_src="$TEMPLATES_DIR/dockerfiles/${runtime}.Dockerfile"
    if [[ -f "$dockerfile_src" ]]; then
        cp "$dockerfile_src" "$site_dir/Dockerfile"
    else
        log_error "Shared Dockerfile not found: $dockerfile_src"
        return 1
    fi

    log_ok "Template '$template_name' copied"
}

# Configure .env file with site-specific values
# Usage: configure_env <site_dir> <site_name> <site_url> <runtime> <version>
configure_env() {
    local site_dir="$1"
    local site_name="$2"
    local site_url="$3"
    local runtime="$4"
    local version="$5"

    if [[ -f "$site_dir/.env.dist" ]]; then
        mv "$site_dir/.env.dist" "$site_dir/.env"
    fi

    local env_file="$site_dir/.env"
    if [[ ! -f "$env_file" ]]; then
        return 0
    fi

    local escaped_name escaped_url
    escaped_name=$(sed_escape "$site_name")
    escaped_url=$(sed_escape "$site_url")

    sed_inplace "s|SITE_NAME=SITE_NAME|SITE_NAME=$escaped_name|g" "$env_file"
    sed_inplace "s|SITE_URL=SITE_URL|SITE_URL=$escaped_url|g" "$env_file"

    # Set runtime version
    case "$runtime" in
        php)    sed_inplace "s|PHP_VERSION=.*|PHP_VERSION=$version|g" "$env_file" ;;
        nodejs) sed_inplace "s|NODE_VERSION=.*|NODE_VERSION=$version|g" "$env_file" ;;
        bun)    sed_inplace "s|BUN_VERSION=.*|BUN_VERSION=$version|g" "$env_file" ;;
    esac

    log_ok "Environment configured"
}

# Configure compose.yaml with site-specific values
# Usage: configure_compose <compose_file> <site_name> <cpu> <memory> <no_ssl> [<no_autostart>]
configure_compose() {
    local compose_file="$1"
    local site_name="$2"
    local cpu="$3"
    local memory="$4"
    local no_ssl="$5"
    local no_autostart="${6:-false}"

    local escaped_name
    escaped_name=$(sed_escape "$site_name")

    sed_inplace "s|SERVICE_NAME|$escaped_name|g" "$compose_file"
    sed_inplace "s|CPU_LIMIT|$cpu|g" "$compose_file"
    sed_inplace "s|MEMORY_LIMIT|$memory|g" "$compose_file"

    # Configure restart policy
    local restart_policy="always"
    if [[ "$no_autostart" == true ]]; then
        restart_policy="\"no\""
    fi
    sed_inplace "s|RESTART_POLICY|$restart_policy|g" "$compose_file"

    # Configure SSL/TLS for traefik templates
    if [[ "$no_ssl" == true ]]; then
        if grep -q "entrypoints=websecure" "$compose_file" 2>/dev/null; then
            sed_inplace "s|entrypoints=websecure|entrypoints=web|g" "$compose_file"
            sed_inplace "/tls.certresolver/d" "$compose_file"
            log_ok "HTTP mode configured (no SSL)"
        fi
    fi

    log_ok "Docker service configured (CPU: $cpu, Memory: $memory)"
}

# =============================================================================
# ALIAS CONFIGURATION
# =============================================================================

# Configure domain aliases (same content mode)
# Usage: configure_same_content_aliases <compose_file> <alias1> <alias2> ...
configure_same_content_aliases() {
    local compose_file="$1"
    shift
    local aliases=("$@")

    # Build additional host rules via temp file (avoids backtick escaping issues)
    local tmpfile
    tmpfile=$(mktemp)

    for domain_alias in "${aliases[@]}"; do
        domain_alias=$(echo "$domain_alias" | xargs)
        [[ -z "$domain_alias" ]] && continue
        printf ' || Host(`%s`)' "$domain_alias" >> "$tmpfile"
    done

    # Use awk with ENVIRON to avoid escape processing on the value
    local extra
    extra=$(cat "$tmpfile")
    EXTRA="$extra" awk '
        /\.rule=Host\(/ {
            extra = ENVIRON["EXTRA"]
            sub(/"$/, extra "\"")
        }
        {print}
    ' "$compose_file" > "${compose_file}.tmp"
    mv "${compose_file}.tmp" "$compose_file"

    rm -f "$tmpfile"
    log_ok "Aliases configured (all domains serve same content)"
}

# Configure domain aliases (redirect mode)
# Usage: configure_redirect_aliases <compose_file> <no_ssl> <alias1> <alias2> ...
configure_redirect_aliases() {
    local compose_file="$1"
    local no_ssl="$2"
    shift 2
    local aliases=("$@")

    # Build alias Host rule via temp file
    local hosts_file
    hosts_file=$(mktemp)
    local first=true
    for domain_alias in "${aliases[@]}"; do
        domain_alias=$(echo "$domain_alias" | xargs)
        [[ -z "$domain_alias" ]] && continue
        if [[ "$first" == true ]]; then
            printf 'Host(`%s`)' "$domain_alias" >> "$hosts_file"
            first=false
        else
            printf ' || Host(`%s`)' "$domain_alias" >> "$hosts_file"
        fi
    done

    local scheme="https" entrypoint="websecure"
    if [[ "$no_ssl" == true ]]; then
        scheme="http"
        entrypoint="web"
    fi

    # Build redirect labels block
    local labels_file
    labels_file=$(mktemp)
    local alias_hosts
    alias_hosts=$(cat "$hosts_file")

    {
        echo "      - \"traefik.http.routers.\${SITE_NAME}-redirect.rule=${alias_hosts}\""
        echo "      - \"traefik.http.routers.\${SITE_NAME}-redirect.entrypoints=${entrypoint}\""
        echo "      - \"traefik.http.routers.\${SITE_NAME}-redirect.middlewares=\${SITE_NAME}-redirect\""
        echo "      - \"traefik.http.middlewares.\${SITE_NAME}-redirect.redirectregex.regex=^${scheme}://[^/]+(.*)\""
        echo "      - \"traefik.http.middlewares.\${SITE_NAME}-redirect.redirectregex.replacement=${scheme}://\${SITE_URL}\${1}\""
        echo "      - \"traefik.http.middlewares.\${SITE_NAME}-redirect.redirectregex.permanent=true\""
        if [[ "$no_ssl" == false ]]; then
            echo "      - \"traefik.http.routers.\${SITE_NAME}-redirect.tls.certresolver=le\""
        fi
    } > "$labels_file"

    # Insert redirect labels after loadbalancer line
    awk -v lf="$labels_file" '
        /loadbalancer\.server\.port/ {
            print
            while ((getline line < lf) > 0) print line
            close(lf)
            next
        }
        {print}
    ' "$compose_file" > "${compose_file}.tmp"
    mv "${compose_file}.tmp" "$compose_file"

    rm -f "$hosts_file" "$labels_file"
    log_ok "Aliases configured with redirect to main domain"
}

# Configure domain aliases (dispatcher)
# Usage: configure_aliases <compose_file> <aliases_csv> <redirect_aliases> <no_ssl>
configure_aliases() {
    local compose_file="$1"
    local aliases_csv="$2"
    local redirect="$3"
    local no_ssl="$4"

    [[ -z "$aliases_csv" ]] && return 0

    log_info "Configuring domain aliases..."

    # Parse comma-separated aliases
    local -a alias_array
    IFS=',' read -ra alias_array <<< "$aliases_csv"

    # Filter empty entries
    local -a valid_aliases=()
    for a in "${alias_array[@]}"; do
        a=$(echo "$a" | xargs)
        [[ -n "$a" ]] && valid_aliases+=("$a")
    done

    if [[ ${#valid_aliases[@]} -eq 0 ]]; then
        return 0
    fi

    if [[ "$redirect" == true ]]; then
        configure_redirect_aliases "$compose_file" "$no_ssl" "${valid_aliases[@]}"
    else
        configure_same_content_aliases "$compose_file" "${valid_aliases[@]}"
    fi
}

# =============================================================================
# SITE MANIFEST
# =============================================================================

# Generate site manifest file
# Usage: generate_site_manifest <site_dir> <name> <url> <template> <runtime_version> \
#        <cpu> <memory> <no_ssl> <framework> <aliases_csv> <redirect_aliases> <no_autostart>
generate_site_manifest() {
    local site_dir="$1"
    local name="$2"
    local url="$3"
    local template="$4"
    local version="$5"
    local cpu="$6"
    local memory="$7"
    local no_ssl="$8"
    local framework="${9:-}"
    local aliases_csv="${10:-}"
    local redirect_aliases="${11:-false}"
    local no_autostart="${12:-false}"

    local runtime
    runtime=$(get_template_runtime "$template")
    local ssl="true"
    [[ "$no_ssl" == true ]] && ssl="false"
    local autostart="true"
    [[ "$no_autostart" == true ]] && autostart="false"

    cat > "$site_dir/site.yaml" << EOF
# Site manifest - auto-generated by site-create.sh
# Do not edit manually unless you know what you are doing
name: "$name"
url: "$url"
template: "$template"
runtime: "$runtime"
${runtime}_version: "$version"
cpu_limit: "$cpu"
memory_limit: "$memory"
ssl: $ssl
autostart: $autostart
EOF

    if [[ -n "$framework" ]]; then
        echo "framework: \"$framework\"" >> "$site_dir/site.yaml"
    fi

    if [[ -n "$aliases_csv" ]]; then
        echo "aliases:" >> "$site_dir/site.yaml"
        IFS=',' read -ra alias_arr <<< "$aliases_csv"
        for a in "${alias_arr[@]}"; do
            a=$(echo "$a" | xargs)
            [[ -n "$a" ]] && echo "  - \"$a\"" >> "$site_dir/site.yaml"
        done
        echo "redirect_aliases: $redirect_aliases" >> "$site_dir/site.yaml"
    fi

    echo "created_at: \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"" >> "$site_dir/site.yaml"

    log_ok "Site manifest created"
}

# =============================================================================
# COMPOSE VALIDATION
# =============================================================================

# Validate generated compose.yaml using docker compose
# Usage: validate_compose <site_dir>
validate_compose() {
    local site_dir="$1"

    if command -v docker &>/dev/null; then
        if ! (cd "$site_dir" && docker compose config -q 2>/dev/null); then
            log_warn "Generated compose.yaml may have issues (docker compose config failed)"
            return 1
        fi
        log_ok "Compose configuration validated"
    fi

    return 0
}
