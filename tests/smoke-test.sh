#!/usr/bin/env bash
#
# smoke-test.sh - Basic validation tests for docker-set
#
# Validates scripts, templates, and configuration without requiring Docker.
# Run: ./tests/smoke-test.sh
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

PASSED=0
FAILED=0

pass() { echo -e "  ${GREEN}✓${NC} $1"; ((PASSED++)) || true; }
fail() { echo -e "  ${RED}✗${NC} $1"; ((FAILED++)) || true; }

# =============================================================================
# TEST: Script syntax
# =============================================================================
echo ""
echo -e "${YELLOW}Script syntax (bash -n)${NC}"

for script in "$PROJECT_ROOT"/scripts/*.sh "$PROJECT_ROOT"/lib/*.sh; do
    [[ -f "$script" ]] || continue
    name=$(basename "$script")
    if bash -n "$script" 2>/dev/null; then
        pass "$name"
    else
        fail "$name"
    fi
done

# =============================================================================
# TEST: Scripts are executable
# =============================================================================
echo ""
echo -e "${YELLOW}Scripts are executable${NC}"

for script in "$PROJECT_ROOT"/scripts/*.sh; do
    [[ -f "$script" ]] || continue
    name=$(basename "$script")
    if [[ -x "$script" ]]; then
        pass "$name"
    else
        fail "$name (not executable)"
    fi
done

# =============================================================================
# TEST: Templates have required files
# =============================================================================
echo ""
echo -e "${YELLOW}Template structure${NC}"

for template in "$PROJECT_ROOT"/templates/*/; do
    [[ -d "$template" ]] || continue
    name=$(basename "$template")
    [[ "$name" == "dockerfiles" ]] && continue

    local_ok=true
    if [[ ! -f "$template/compose.yaml" ]]; then
        fail "$name: missing compose.yaml"
        local_ok=false
    fi
    if [[ ! -f "$template/.env.dist" ]]; then
        fail "$name: missing .env.dist"
        local_ok=false
    fi
    [[ "$local_ok" == true ]] && pass "$name"
done

# =============================================================================
# TEST: Shared Dockerfiles exist
# =============================================================================
echo ""
echo -e "${YELLOW}Shared Dockerfiles${NC}"

for df in php.Dockerfile nodejs.Dockerfile bun.Dockerfile go.Dockerfile; do
    if [[ -f "$PROJECT_ROOT/templates/dockerfiles/$df" ]]; then
        pass "$df"
    else
        fail "$df (not found)"
    fi
done

# No Dockerfiles in individual templates (deduplication check)
for template in "$PROJECT_ROOT"/templates/*/; do
    [[ -d "$template" ]] || continue
    name=$(basename "$template")
    [[ "$name" == "dockerfiles" ]] && continue

    if [[ -f "$template/Dockerfile" ]]; then
        fail "$name: has local Dockerfile (should use shared)"
    else
        pass "$name: uses shared Dockerfile"
    fi
done

# =============================================================================
# TEST: Dockerfiles have version ARG
# =============================================================================
echo ""
echo -e "${YELLOW}Dockerfile version ARGs${NC}"

if grep -q "^ARG PHP_VERSION=" "$PROJECT_ROOT/templates/dockerfiles/php.Dockerfile"; then
    pass "php.Dockerfile has PHP_VERSION ARG"
else
    fail "php.Dockerfile missing PHP_VERSION ARG"
fi

if grep -q "^ARG NODE_VERSION=" "$PROJECT_ROOT/templates/dockerfiles/nodejs.Dockerfile"; then
    pass "nodejs.Dockerfile has NODE_VERSION ARG"
else
    fail "nodejs.Dockerfile missing NODE_VERSION ARG"
fi

if grep -q "^ARG BUN_VERSION=" "$PROJECT_ROOT/templates/dockerfiles/bun.Dockerfile"; then
    pass "bun.Dockerfile has BUN_VERSION ARG"
else
    fail "bun.Dockerfile missing BUN_VERSION ARG"
fi

if grep -q "^ARG GO_VERSION=" "$PROJECT_ROOT/templates/dockerfiles/go.Dockerfile"; then
    pass "go.Dockerfile has GO_VERSION ARG"
else
    fail "go.Dockerfile missing GO_VERSION ARG"
fi

# =============================================================================
# TEST: Compose templates have build args
# =============================================================================
echo ""
echo -e "${YELLOW}Compose build args${NC}"

for template in "$PROJECT_ROOT"/templates/*/; do
    [[ -d "$template" ]] || continue
    name=$(basename "$template")
    [[ "$name" == "dockerfiles" ]] && continue

    compose="$template/compose.yaml"
    [[ -f "$compose" ]] || continue

    if grep -q "args:" "$compose"; then
        pass "$name compose.yaml has build args"
    else
        fail "$name compose.yaml missing build args"
    fi
done

# =============================================================================
# TEST: .env.dist has version variables
# =============================================================================
echo ""
echo -e "${YELLOW}Version variables in .env.dist${NC}"

for template in "$PROJECT_ROOT"/templates/php-*/; do
    [[ -d "$template" ]] || continue
    name=$(basename "$template")
    env="$template/.env.dist"

    if grep -q "PHP_VERSION=" "$env" 2>/dev/null; then
        pass "$name has PHP_VERSION"
    else
        fail "$name missing PHP_VERSION"
    fi
done

for template in "$PROJECT_ROOT"/templates/nodejs-*/; do
    [[ -d "$template" ]] || continue
    name=$(basename "$template")
    env="$template/.env.dist"

    if grep -q "NODE_VERSION=" "$env" 2>/dev/null; then
        pass "$name has NODE_VERSION"
    else
        fail "$name missing NODE_VERSION"
    fi
done

for template in "$PROJECT_ROOT"/templates/bun-*/; do
    [[ -d "$template" ]] || continue
    name=$(basename "$template")
    env="$template/.env.dist"

    if grep -q "BUN_VERSION=" "$env" 2>/dev/null; then
        pass "$name has BUN_VERSION"
    else
        fail "$name missing BUN_VERSION"
    fi
done

for template in "$PROJECT_ROOT"/templates/go-*/; do
    [[ -d "$template" ]] || continue
    name=$(basename "$template")
    env="$template/.env.dist"

    if grep -q "GO_VERSION=" "$env" 2>/dev/null; then
        pass "$name has GO_VERSION"
    else
        fail "$name missing GO_VERSION"
    fi
done

# =============================================================================
# TEST: No dead references
# =============================================================================
echo ""
echo -e "${YELLOW}No dead references${NC}"

# Check that db-create-user.sh is not referenced
dead_refs=$(grep -rl "db-create-user.sh" "$PROJECT_ROOT"/templates/ "$PROJECT_ROOT"/scripts/ "$PROJECT_ROOT"/lib/ 2>/dev/null || true)
if [[ -z "$dead_refs" ]]; then
    pass "No references to non-existent db-create-user.sh"
else
    fail "Dead references to db-create-user.sh in: $dead_refs"
fi

# =============================================================================
# TEST: Library modules exist
# =============================================================================
echo ""
echo -e "${YELLOW}Library modules${NC}"

for lib in common.sh site.sh database.sh framework.sh; do
    if [[ -f "$PROJECT_ROOT/lib/$lib" ]]; then
        pass "$lib exists"
    else
        fail "$lib missing"
    fi
done

# =============================================================================
# TEST: Config files exist
# =============================================================================
echo ""
echo -e "${YELLOW}Infrastructure config${NC}"

for f in config/traefik/compose.yaml config/traefik/traefik.yaml.dist \
         config/traefik/dynamic.yaml.dist \
         config/mysql/compose.yaml config/mysql/.env.dist \
         config/default-site.dist/compose-page.yaml \
         config/default-site.dist/compose-redirect.yaml \
         config/default-site.dist/compose-404.yaml \
         config/default-site.dist/index-page.html \
         config/default-site.dist/index-404.html \
         config/default-site.dist/nginx-404.conf; do
    if [[ -f "$PROJECT_ROOT/$f" ]]; then
        pass "$f"
    else
        fail "$f missing"
    fi
done

# =============================================================================
# TEST: Framework installer syntax
# =============================================================================
echo ""
echo -e "${YELLOW}Framework installer syntax (sh -n)${NC}"

for script in "$PROJECT_ROOT"/frameworks/*/install.sh; do
    [[ -f "$script" ]] || continue
    name=$(echo "$script" | sed "s|$PROJECT_ROOT/||")
    if sh -n "$script" 2>/dev/null; then
        pass "$name"
    else
        fail "$name"
    fi
done

# =============================================================================
# TEST: Frameworks have runtime.txt
# =============================================================================
echo ""
echo -e "${YELLOW}Frameworks have runtime.txt${NC}"

for fw_dir in "$PROJECT_ROOT"/frameworks/*/; do
    [[ -d "$fw_dir" ]] || continue
    name=$(basename "$fw_dir")
    if [[ -f "$fw_dir/runtime.txt" ]]; then
        runtime=$(head -1 "$fw_dir/runtime.txt" | tr -d '[:space:]')
        if [[ "$runtime" =~ ^(php|nodejs|bun|go)$ ]]; then
            pass "$name runtime.txt ($runtime)"
        else
            fail "$name runtime.txt has invalid runtime: $runtime"
        fi
    else
        fail "$name missing runtime.txt"
    fi
done

# =============================================================================
# TEST: Framework installers have error handling
# =============================================================================
echo ""
echo -e "${YELLOW}Framework installers have error handling${NC}"

for script in "$PROJECT_ROOT"/frameworks/*/install.sh; do
    [[ -f "$script" ]] || continue
    name=$(echo "$script" | sed "s|$PROJECT_ROOT/||")
    if grep -q "set -e" "$script" 2>/dev/null; then
        pass "$name has set -e"
    else
        fail "$name missing set -e"
    fi
done

# =============================================================================
# TEST: Templates have security_opt
# =============================================================================
echo ""
echo -e "${YELLOW}Templates have security_opt${NC}"

for template in "$PROJECT_ROOT"/templates/*/; do
    [[ -d "$template" ]] || continue
    name=$(basename "$template")
    [[ "$name" == "dockerfiles" ]] && continue

    compose="$template/compose.yaml"
    [[ -f "$compose" ]] || continue

    if grep -q "no-new-privileges" "$compose" 2>/dev/null; then
        pass "$name has security_opt"
    else
        fail "$name missing security_opt"
    fi
done

# =============================================================================
# TEST: Templates have consistent memory quoting
# =============================================================================
echo ""
echo -e "${YELLOW}Templates have consistent resource limit quoting${NC}"

for template in "$PROJECT_ROOT"/templates/*/; do
    [[ -d "$template" ]] || continue
    name=$(basename "$template")
    [[ "$name" == "dockerfiles" ]] && continue

    compose="$template/compose.yaml"
    [[ -f "$compose" ]] || continue

    # Check that MEMORY_LIMIT is quoted (like CPU_LIMIT)
    if grep -q "'MEMORY_LIMIT'" "$compose" 2>/dev/null; then
        pass "$name memory limit is quoted"
    elif grep -q "MEMORY_LIMIT" "$compose" 2>/dev/null; then
        fail "$name memory limit is not quoted"
    fi
done

# =============================================================================
# TEST: Placeholder consistency
# =============================================================================
echo ""
echo -e "${YELLOW}Template placeholders${NC}"

for template in "$PROJECT_ROOT"/templates/*/; do
    [[ -d "$template" ]] || continue
    name=$(basename "$template")
    [[ "$name" == "dockerfiles" ]] && continue

    compose="$template/compose.yaml"
    env="$template/.env.dist"

    # compose.yaml should have SERVICE_NAME placeholder
    if grep -q "SERVICE_NAME" "$compose" 2>/dev/null; then
        pass "$name compose.yaml has SERVICE_NAME placeholder"
    else
        fail "$name compose.yaml missing SERVICE_NAME placeholder"
    fi

    # .env.dist should have SITE_NAME=SITE_NAME placeholder
    if grep -q "SITE_NAME=SITE_NAME" "$env" 2>/dev/null; then
        pass "$name .env.dist has SITE_NAME placeholder"
    else
        fail "$name .env.dist missing SITE_NAME placeholder"
    fi
done

# =============================================================================
# TEST: MySQL credentials never passed via -p on command line
# =============================================================================
echo ""
echo -e "${YELLOW}MySQL credentials use MYSQL_PWD (not -p arg)${NC}"

mysql_pw_hits=$(grep -RIn --include='*.sh' -E '(mysql|mysqldump)[[:space:]]+.*-p"' \
    "$PROJECT_ROOT"/lib "$PROJECT_ROOT"/scripts 2>/dev/null || true)
if [[ -z "$mysql_pw_hits" ]]; then
    pass "no -p\"\$password\" usage"
else
    fail "found -p\"\$password\" usage (use MYSQL_PWD env var instead):"
    echo "$mysql_pw_hits" | sed 's/^/    /'
fi

# =============================================================================
# TEST: All templates forward DB_* env vars (apps can read via env at runtime)
# =============================================================================
echo ""
echo -e "${YELLOW}Templates forward DB_* env vars${NC}"

for template in "$PROJECT_ROOT"/templates/*/; do
    [[ -d "$template" ]] || continue
    name=$(basename "$template")
    [[ "$name" == "dockerfiles" ]] && continue

    compose="$template/compose.yaml"
    [[ -f "$compose" ]] || continue

    if grep -q 'DB_DATABASE=${DB_DATABASE' "$compose" 2>/dev/null; then
        pass "$name forwards DB_*"
    else
        fail "$name missing DB_* in environment section"
    fi
done

# =============================================================================
# TEST: Framework runtime.txt matches known runtimes
# =============================================================================
echo ""
echo -e "${YELLOW}inject_db_credentials exists in lib/database.sh${NC}"

if grep -q "^inject_db_credentials()" "$PROJECT_ROOT/lib/database.sh"; then
    pass "inject_db_credentials defined"
else
    fail "inject_db_credentials missing"
fi

# =============================================================================
# Helpers for Dockerfile stage inspection (Phase 1: dev/prod site modes)
# =============================================================================

# Lines from "FROM ... AS build" up to (excluding) "FROM ... AS dev":
# everything that ends up in prod images
dockerfile_prod_region() {
    awk '/^FROM .* AS dev$/{exit} /^FROM .* AS build$/{found=1} found' "$1"
}

# Lines of the prod stage only (from "FROM ... AS prod" to the next FROM)
dockerfile_prod_stage() {
    awk '/^FROM /{found=0} /^FROM .* AS prod$/{found=1} found' "$1"
}

# Lines of the dev stage (from "FROM ... AS dev" to EOF)
dockerfile_dev_stage() {
    awk '/^FROM .* AS dev$/{found=1} found' "$1"
}

# =============================================================================
# TEST: Every template ships compose.prod.yaml
# =============================================================================
echo ""
echo -e "${YELLOW}Templates ship compose.prod.yaml${NC}"

for template in "$PROJECT_ROOT"/templates/*/; do
    [[ -d "$template" ]] || continue
    name=$(basename "$template")
    [[ "$name" == "dockerfiles" ]] && continue

    if [[ -f "$template/compose.prod.yaml" ]]; then
        pass "$name"
    else
        fail "$name: missing compose.prod.yaml"
    fi
done

# =============================================================================
# TEST: compose.prod.yaml invariants (baked image, named data volume)
# =============================================================================
echo ""
echo -e "${YELLOW}compose.prod.yaml invariants${NC}"

for template in "$PROJECT_ROOT"/templates/*/; do
    [[ -d "$template" ]] || continue
    name=$(basename "$template")
    [[ "$name" == "dockerfiles" ]] && continue

    compose="$template/compose.prod.yaml"
    [[ -f "$compose" ]] || continue

    local_ok=true
    if ! grep -q 'target: prod' "$compose"; then
        fail "$name: missing 'target: prod'"
        local_ok=false
    fi
    if ! grep -q 'init: true' "$compose"; then
        fail "$name: missing 'init: true' (SIGTERM forwarding)"
        local_ok=false
    fi
    if ! grep -q 'app-data:/app/data' "$compose"; then
        fail "$name: missing app-data:/app/data mount"
        local_ok=false
    fi
    if ! grep -q '^volumes:' "$compose" || ! grep -q '^  app-data:' "$compose"; then
        fail "$name: missing top-level app-data volume declaration"
        local_ok=false
    fi
    if grep -q '\./app:' "$compose"; then
        fail "$name: has ./app bind mount (prod code must be baked into the image)"
        local_ok=false
    fi
    if ! grep -q 'no-new-privileges' "$compose"; then
        fail "$name: missing security_opt no-new-privileges"
        local_ok=false
    fi
    if ! grep -q 'DB_DATABASE=${DB_DATABASE' "$compose"; then
        fail "$name: missing DB_* forwarding in environment section"
        local_ok=false
    fi
    [[ "$local_ok" == true ]] && pass "$name"
done

# =============================================================================
# TEST: Dev compose targets the dev stage
# =============================================================================
echo ""
echo -e "${YELLOW}Dev compose targets the dev stage${NC}"

for template in "$PROJECT_ROOT"/templates/*/; do
    [[ -d "$template" ]] || continue
    name=$(basename "$template")
    [[ "$name" == "dockerfiles" ]] && continue

    compose="$template/compose.yaml"
    [[ -f "$compose" ]] || continue

    if grep -q 'target: dev' "$compose"; then
        pass "$name"
    else
        fail "$name: compose.yaml missing 'target: dev'"
    fi
done

# =============================================================================
# TEST: Dockerfile stages (base/build/prod present, dev LAST)
# =============================================================================
echo ""
echo -e "${YELLOW}Dockerfile stages (base/build/prod, dev last)${NC}"

for df in php.Dockerfile nodejs.Dockerfile bun.Dockerfile go.Dockerfile; do
    file="$PROJECT_ROOT/templates/dockerfiles/$df"
    [[ -f "$file" ]] || continue

    local_ok=true
    for stage in base build prod; do
        if ! grep -q "^FROM .* AS ${stage}$" "$file"; then
            fail "$df: missing stage 'AS $stage'"
            local_ok=false
        fi
    done
    # Backward-compat invariant: the LAST FROM must be the dev stage so
    # untargeted builds (pre-existing sites without build.target) stay dev
    last_from=$(grep '^FROM ' "$file" | tail -1)
    if [[ "$last_from" != *" AS dev" ]]; then
        fail "$df: last FROM is not 'AS dev' (breaks untargeted builds): $last_from"
        local_ok=false
    fi
    [[ "$local_ok" == true ]] && pass "$df"
done

# =============================================================================
# TEST: nodejs prod stages are PM2-free (dev keeps PM2 for backward compat)
# =============================================================================
echo ""
echo -e "${YELLOW}nodejs prod stages are PM2-free${NC}"

nodejs_df="$PROJECT_ROOT/templates/dockerfiles/nodejs.Dockerfile"
# Comments (e.g. "no PM2") are fine; actual pm2 install/usage is not
if dockerfile_prod_region "$nodejs_df" | grep -v '^[[:space:]]*#' | grep -qi 'pm2'; then
    fail "nodejs.Dockerfile: pm2 referenced between AS build and AS dev (prod must not use PM2)"
else
    pass "no pm2 between AS build and AS dev"
fi

if dockerfile_dev_stage "$nodejs_df" | grep -qi 'pm2'; then
    pass "pm2 still present in dev stage (backward compat)"
else
    fail "nodejs.Dockerfile: pm2 missing from dev stage"
fi

# =============================================================================
# TEST: Prod stage runtime user
# =============================================================================
echo ""
echo -e "${YELLOW}Prod stage runtime user${NC}"

for df in go.Dockerfile bun.Dockerfile nodejs.Dockerfile; do
    file="$PROJECT_ROOT/templates/dockerfiles/$df"
    if dockerfile_prod_stage "$file" | grep -q '^USER app$'; then
        pass "$df prod runs as USER app"
    else
        fail "$df: prod stage missing 'USER app'"
    fi
done

# FrankenPHP binds :80 as root and drops privileges itself — no USER in prod
if dockerfile_prod_stage "$PROJECT_ROOT/templates/dockerfiles/php.Dockerfile" | grep -q '^USER '; then
    fail "php.Dockerfile: prod stage sets USER (FrankenPHP manages privileges itself)"
else
    pass "php.Dockerfile prod has no USER (FrankenPHP drops privileges)"
fi

# =============================================================================
# TEST: Prod stages fail fast (no keep-alive tail)
# =============================================================================
echo ""
echo -e "${YELLOW}Prod stages fail fast (no tail -f /dev/null)${NC}"

for df in php.Dockerfile nodejs.Dockerfile bun.Dockerfile go.Dockerfile; do
    file="$PROJECT_ROOT/templates/dockerfiles/$df"
    if dockerfile_prod_region "$file" | grep -q 'tail -f /dev/null'; then
        fail "$df: 'tail -f /dev/null' between AS build and AS dev (prod must exit on crash)"
    else
        pass "$df"
    fi
done

# =============================================================================
# TEST: Build context dockerignore keeps secrets out of images
# =============================================================================
echo ""
echo -e "${YELLOW}Build context dockerignore${NC}"

dockerignore="$PROJECT_ROOT/templates/dockerfiles/dockerignore"
if [[ -f "$dockerignore" ]]; then
    pass "dockerignore exists"
else
    fail "templates/dockerfiles/dockerignore missing"
fi
if grep -q '^\.env$' "$dockerignore" 2>/dev/null; then
    pass "dockerignore covers .env"
else
    fail "dockerignore does not exclude .env (DB_PASSWORD would leak into images)"
fi
if grep -q '^site\.yaml$' "$dockerignore" 2>/dev/null; then
    pass "dockerignore covers site.yaml"
else
    fail "dockerignore does not exclude site.yaml"
fi

# =============================================================================
# TEST: Site mode functions in lib/site.sh
# =============================================================================
echo ""
echo -e "${YELLOW}Site mode functions in lib/site.sh${NC}"

for fn in validate_mode get_site_mode switch_site_mode \
          get_site_data_volume archive_site_data_volume restore_site_data_volume; do
    if grep -q "^${fn}()" "$PROJECT_ROOT/lib/site.sh"; then
        pass "$fn defined"
    else
        fail "$fn missing"
    fi
done

# =============================================================================
# TEST: Site mode scripts exist
# =============================================================================
echo ""
echo -e "${YELLOW}Site mode scripts exist${NC}"

for script in site-deploy.sh site-shell.sh site-run.sh; do
    if [[ -f "$PROJECT_ROOT/scripts/$script" ]]; then
        pass "$script"
    else
        fail "$script missing"
    fi
done

# =============================================================================
# TEST: Data volume safety nets (delete archives, backup includes data)
# =============================================================================
echo ""
echo -e "${YELLOW}Data volume safety nets${NC}"

if grep -q 'archive_site_data_volume' "$PROJECT_ROOT/scripts/site-delete.sh"; then
    pass "site-delete.sh archives app-data before deletion"
else
    fail "site-delete.sh does not archive the app-data volume"
fi

if grep -q 'data\.tar\.gz' "$PROJECT_ROOT/scripts/site-backup.sh"; then
    pass "site-backup.sh includes data.tar.gz"
else
    fail "site-backup.sh does not include the app-data volume (data.tar.gz)"
fi

# =============================================================================
# TEST: API control plane sources (Phase 2) — static, no Docker
# =============================================================================
echo ""
echo -e "${YELLOW}API control plane sources${NC}"

api_dir="$PROJECT_ROOT/api"

for f in go.mod main.go handlers.go jobs.go auth.go Dockerfile; do
    if [[ -f "$api_dir/$f" ]]; then
        pass "api/$f exists"
    else
        fail "api/$f missing"
    fi
done

if grep -q '^module docker-set/api$' "$api_dir/go.mod" 2>/dev/null; then
    pass "go.mod declares module docker-set/api"
else
    fail "go.mod missing 'module docker-set/api'"
fi

# stdlib-only invariant: any require directive means a dependency crept in
if grep -q 'require' "$api_dir/go.mod" 2>/dev/null; then
    fail "go.mod has require directives (API must stay stdlib-only)"
else
    pass "go.mod is stdlib-only (no require)"
fi

if [[ -f "$PROJECT_ROOT/scripts/api-setup.sh" && -x "$PROJECT_ROOT/scripts/api-setup.sh" ]]; then
    pass "scripts/api-setup.sh exists and is executable"
else
    fail "scripts/api-setup.sh missing or not executable"
fi

# =============================================================================
# TEST: API Dockerfile is multi-stage with a gofmt/vet gate
# =============================================================================
echo ""
echo -e "${YELLOW}API Dockerfile (gofmt/vet gate, runtime deps)${NC}"

api_df="$api_dir/Dockerfile"
if grep -qE '^FROM .* AS build$' "$api_df" 2>/dev/null && grep -qE '^FROM .* AS prod$' "$api_df" 2>/dev/null; then
    pass "Dockerfile is multi-stage (build + prod)"
else
    fail "Dockerfile missing build/prod stages"
fi

if grep -q 'gofmt -l' "$api_df" 2>/dev/null && grep -q 'go vet' "$api_df" 2>/dev/null; then
    pass "Dockerfile enforces gofmt -l + go vet"
else
    fail "Dockerfile missing gofmt -l/go vet gate"
fi

if grep -q 'CGO_ENABLED=0' "$api_df" 2>/dev/null; then
    pass "build is static (CGO_ENABLED=0)"
else
    fail "Dockerfile missing CGO_ENABLED=0"
fi

# Final stage must stay on alpine (minimal runtime, apk-installed CLI tools)
api_last_from=$(grep '^FROM ' "$api_df" 2>/dev/null | tail -1)
if [[ "$api_last_from" == FROM\ alpine:* ]]; then
    pass "final stage runs on alpine"
else
    fail "final stage is not alpine: ${api_last_from:-<none>}"
fi

if grep -q '^HEALTHCHECK ' "$api_df" 2>/dev/null; then
    pass "Dockerfile has a HEALTHCHECK"
else
    fail "Dockerfile missing HEALTHCHECK"
fi

if grep -qE 'apk add .*docker-cli' "$api_df" 2>/dev/null && grep -qE 'apk add .*bash' "$api_df" 2>/dev/null; then
    pass "prod stage installs docker-cli + bash"
else
    fail "prod stage missing docker-cli/bash"
fi

# =============================================================================
# TEST: API compose binds localhost, mounts the socket, hardened
# =============================================================================
echo ""
echo -e "${YELLOW}API compose (config/api/compose.yaml)${NC}"

api_compose="$PROJECT_ROOT/config/api/compose.yaml"
if grep -q '127.0.0.1:9000:9000' "$api_compose" 2>/dev/null; then
    pass "binds 127.0.0.1:9000 (localhost only)"
else
    fail "compose does not bind 127.0.0.1:9000"
fi

if grep -q '/var/run/docker.sock:/var/run/docker.sock' "$api_compose" 2>/dev/null; then
    pass "mounts the Docker socket"
else
    fail "compose does not mount the Docker socket"
fi

# Repo mounted at the SAME path on both sides: bind mounts issued by the
# scripts (docker compose in sites/<name>) must resolve on the host daemon
if grep -qF '${DOCKER_SET_ROOT}:${DOCKER_SET_ROOT}' "$api_compose" 2>/dev/null; then
    pass "repo mounted at the same host/container path"
else
    fail "compose missing \${DOCKER_SET_ROOT}:\${DOCKER_SET_ROOT} same-path mount"
fi

if grep -q 'no-new-privileges' "$api_compose" 2>/dev/null; then
    pass "sets no-new-privileges"
else
    fail "compose missing no-new-privileges"
fi

if grep -q 'init: true' "$api_compose" 2>/dev/null; then
    pass "sets init: true"
else
    fail "compose missing init: true"
fi

# =============================================================================
# TEST: API .env.dist keys and .gitignore coverage
# =============================================================================
echo ""
echo -e "${YELLOW}API .env.dist keys${NC}"

api_env="$PROJECT_ROOT/config/api/.env.dist"
for key in API_TOKEN WEBHOOK_SECRET DOCKER_SET_ROOT; do
    if grep -qE "^${key}=" "$api_env" 2>/dev/null; then
        pass ".env.dist has $key"
    else
        fail ".env.dist missing $key"
    fi
done

if grep -qE '^config/api/\.env$' "$PROJECT_ROOT/.gitignore" 2>/dev/null; then
    pass ".gitignore ignores config/api/.env"
else
    fail ".gitignore does not ignore config/api/.env"
fi

# =============================================================================
# TEST: API auth primitives (constant-time comparisons)
# =============================================================================
echo ""
echo -e "${YELLOW}API auth primitives${NC}"

api_auth="$api_dir/auth.go"
if grep -q 'subtle.ConstantTimeCompare' "$api_auth" 2>/dev/null; then
    pass "bearer token compared with subtle.ConstantTimeCompare"
else
    fail "auth.go does not use subtle.ConstantTimeCompare"
fi

if grep -q 'hmac.Equal' "$api_auth" 2>/dev/null; then
    pass "webhook signature verified with hmac.Equal"
else
    fail "auth.go does not use hmac.Equal"
fi

# =============================================================================
# TEST: Web UI (Phase 3) — embedded SPA served by the API binary
# =============================================================================
echo ""
echo -e "${YELLOW}Web UI (embedded SPA)${NC}"

# Backend + asset files present
for f in static.go meta.go static/index.html static/app.js static/style.css; do
    if [[ -f "$api_dir/$f" ]]; then
        pass "api/$f exists"
    else
        fail "api/$f missing"
    fi
done

# Assets are embedded into the binary (single-binary invariant)
if grep -qF '//go:embed static/*' "$api_dir/static.go" 2>/dev/null; then
    pass "static.go embeds the assets (//go:embed static/*)"
else
    fail "static.go missing //go:embed static/*"
fi

# A strict CSP is declared for the UI responses
if grep -qF "default-src 'self'" "$api_dir/static.go" 2>/dev/null; then
    pass "static.go declares the Content-Security-Policy constant"
else
    fail "static.go missing CSP constant (default-src 'self')"
fi

# Dockerfile copies the assets so the embed resolves at build time
if grep -qF 'COPY static/' "$api_dir/Dockerfile" 2>/dev/null; then
    pass "Dockerfile copies static/ into the build context"
else
    fail "Dockerfile missing COPY static/"
fi

# routes(): SPA index + assets are unauthenticated; /api/meta is Bearer-gated
routes_file="$api_dir/handlers.go"

index_line=$(grep -F 'GET /{$}' "$routes_file" 2>/dev/null || true)
if [[ -n "$index_line" ]] && grep -q 'handleIndex' <<<"$index_line" \
        && ! grep -qF 'requireBearer' <<<"$index_line"; then
    pass 'routes() serves GET /{$} (SPA index) unauthenticated'
else
    fail 'routes() missing unauthenticated GET /{$} -> handleIndex'
fi

static_line=$(grep -F 'GET /static/{path...}' "$routes_file" 2>/dev/null || true)
if [[ -n "$static_line" ]] && ! grep -qF 'requireBearer' <<<"$static_line"; then
    pass 'routes() serves GET /static/{path...} unauthenticated'
else
    fail 'routes() missing unauthenticated GET /static/{path...}'
fi

meta_line=$(grep -F 'GET /api/meta' "$routes_file" 2>/dev/null || true)
if [[ -n "$meta_line" ]] && grep -qF 'requireBearer' <<<"$meta_line"; then
    pass 'routes() gates GET /api/meta behind requireBearer'
else
    fail 'routes() missing bearer-gated GET /api/meta'
fi

# Token flow lives in sessionStorage (this tab only)
if grep -q 'sessionStorage' "$api_dir/static/app.js" 2>/dev/null; then
    pass "app.js keeps the API token in sessionStorage"
else
    fail "app.js does not reference sessionStorage"
fi

# CSP-clean HTML: no inline event handlers, no inline <script> blocks
ui_html="$api_dir/static/index.html"
if grep -qiE '<[^>]+ on[a-z]+=' "$ui_html" 2>/dev/null; then
    fail "index.html has inline event handler(s) (e.g. onclick=) — CSP-unsafe"
else
    pass "index.html has no inline event handlers"
fi
if grep -oE '<script[^>]*>' "$ui_html" 2>/dev/null | grep -qv 'src='; then
    fail "index.html has an inline <script> block (CSP forbids inline JS)"
else
    pass "index.html has no inline <script> (all scripts external)"
fi

# =============================================================================
# SUMMARY
# =============================================================================
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "Results: ${GREEN}$PASSED passed${NC}, ${RED}$FAILED failed${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [[ $FAILED -gt 0 ]]; then
    exit 1
fi
