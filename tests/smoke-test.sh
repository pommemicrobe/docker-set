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

for df in php.Dockerfile nodejs.Dockerfile; do
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

for f in config/traefik/compose.yaml config/traefik/traefik.yaml.dist config/mysql/compose.yaml config/mysql/.env.dist; do
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
# SUMMARY
# =============================================================================
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "Results: ${GREEN}$PASSED passed${NC}, ${RED}$FAILED failed${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [[ $FAILED -gt 0 ]]; then
    exit 1
fi
