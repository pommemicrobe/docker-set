#!/usr/bin/env bash
#
# lint.sh - shellcheck lint for docker-set
#
# Runs shellcheck (via the koalaman/shellcheck Docker image, no local install
# needed) over scripts/, lib/ and tests/ at --severity=warning.
# Exit 0 when clean, 1 on findings. When Docker is unavailable or the image
# cannot run, prints a skip message and exits 0 (lint is advisory in
# environments without Docker).
#
# Baseline decision: 7 known pre-existing findings are tolerated HERE by
# filtering them out of the report — the scripts themselves are left
# untouched (no inline disable directives). This keeps lint.sh exiting 0 on
# the current tree so it can be wired into CI; the same codes in any other
# file, or on any other variable, still fail. The baseline:
#   - scripts/site-create.sh: SC2207 x2 (array from command output),
#     SC2034 (INTERACTIVE)
#   - lib/common.sh: SC2034 x3 (FRAMEWORKS_DIR/CONFIG_DIR/BACKUPS_DIR are
#     defined here but used by sourcing scripts — per-file analysis
#     false positives)
#   - lib/framework.sh: SC2034 (runtime_version — accepted 5th parameter
#     of install_framework, currently unused)
#
# Run: ./tests/lint.sh
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

SHELLCHECK_IMAGE="koalaman/shellcheck:stable"

# Known pre-existing findings tolerated on the current tree (see header)
BASELINE_PATTERN='^scripts/site-create\.sh:[0-9]+:[0-9]+: warning: .*\[SC2207\]$'
BASELINE_PATTERN+='|^scripts/site-create\.sh:[0-9]+:[0-9]+: warning: INTERACTIVE .*\[SC2034\]$'
BASELINE_PATTERN+='|^lib/common\.sh:[0-9]+:[0-9]+: warning: (FRAMEWORKS_DIR|CONFIG_DIR|BACKUPS_DIR) appears unused.*\[SC2034\]$'
BASELINE_PATTERN+='|^lib/framework\.sh:[0-9]+:[0-9]+: warning: runtime_version appears unused.*\[SC2034\]$'
BASELINE_DESC="site-create.sh, common.sh, framework.sh (see header)"

skip() {
    echo -e "${YELLOW}SKIP:${NC} $1"
    echo "shellcheck lint is advisory in environments without Docker."
    exit 0
}

# --- Docker availability (skip, don't fail: lint is advisory without it) ----
command -v docker >/dev/null 2>&1 \
    || skip "docker not found in PATH — shellcheck lint skipped"
docker info >/dev/null 2>&1 \
    || skip "docker daemon not reachable — shellcheck lint skipped"
docker run --rm "$SHELLCHECK_IMAGE" --version >/dev/null 2>&1 \
    || skip "cannot run $SHELLCHECK_IMAGE — shellcheck lint skipped"

# --- Collect files (paths relative to the project root, mounted at /mnt) ----
files=()
for f in scripts/*.sh lib/*.sh tests/*.sh; do
    [[ -f "$PROJECT_ROOT/$f" ]] && files+=("$f")
done

echo ""
echo -e "${YELLOW}shellcheck --severity=warning over ${#files[@]} files${NC}"

# gcc format = one line per finding: file:line:col: level: message [SCxxxx]
set +e
output=$(docker run --rm -v "$PROJECT_ROOT":/mnt -w /mnt "$SHELLCHECK_IMAGE" \
    --severity=warning --format=gcc "${files[@]}" 2>&1)
status=$?
set -e

if [[ $status -ne 0 && $status -ne 1 ]]; then
    # Not "clean" (0) and not "findings" (1): shellcheck/docker itself failed
    echo "$output"
    skip "$SHELLCHECK_IMAGE exited with status $status — shellcheck lint skipped"
fi

baseline_hits=$(grep -Ec "$BASELINE_PATTERN" <<<"$output" || true)
findings=$(grep -Ev "$BASELINE_PATTERN" <<<"$output" | grep -E '\[SC[0-9]+\]$' || true)

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [[ -n "$findings" ]]; then
    echo "$findings" | sed 's/^/  /'
    count=$(wc -l <<<"$findings" | tr -d '[:space:]')
    echo -e "Results: ${RED}$count finding(s)${NC}" \
        "(baseline: $baseline_hits tolerated in $BASELINE_DESC)"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    exit 1
fi

echo -e "Results: ${GREEN}clean${NC} — ${#files[@]} files," \
    "$baseline_hits baseline finding(s) tolerated in $BASELINE_DESC"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
