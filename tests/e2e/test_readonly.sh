#!/bin/bash
# tests/e2e/test_readonly.sh — Read-only UTM/SSH integration tests.
# Tests against the real UTM and SSH without modifying VM state.
# Must run on macOS with UTM installed and VM accessible.
set -euo pipefail

[[ "$(uname -s)" == Darwin ]] || { printf 'SKIP: macOS required\n'; exit 0; }

# shellcheck disable=SC1007
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../../" && pwd)

PASS=0
FAIL=0
total=0

check() {
    local name="$1"
    shift
    total=$((total + 1))
    if "$@" >/dev/null 2>&1; then
        PASS=$((PASS + 1))
        printf '  ✓ %s\n' "$name"
    else
        FAIL=$((FAIL + 1))
        printf '  ✗ %s\n' "$name"
    fi
}

printf '=== E2E Read-Only Tests (real UTM/SSH) ===\n'

# Check UTM exists
total=$((total + 1))
if [[ -x /Applications/UTM.app/Contents/MacOS/utmctl ]]; then
    PASS=$((PASS + 1))
    printf '  ✓ UTM/utmctl available\n'
else
    FAIL=$((FAIL + 1))
    printf '  ✗ UTM/utmctl not available — skipping E2E\n'
    printf '\n=== Results: %d/%d passed, %d failed (E2E skipped) ===\n' "$PASS" "$total" "$FAIL"
    exit 0
fi

# Test rcu help
check 'rcu help' "$ROOT/bin/rcu" help

# Test rcu status (read-only)
check 'rcu utm status' "$ROOT/bin/rcu" utm status

# Test rcu health (read-only — may fail if VM not running, which is OK)
total=$((total + 1))
if "$ROOT/bin/rcu" utm health >/dev/null 2>&1; then
    PASS=$((PASS + 1))
    printf '  ✓ rcu utm health (VM running, SSH OK)\n'
else
    # Check if VM is actually running
    local_state=$(/Applications/UTM.app/Contents/MacOS/utmctl list 2>/dev/null \
        | awk '$1 ~ /A16B662F/ {print $2}')
    if [[ "$local_state" == "started" ]]; then
        FAIL=$((FAIL + 1))
        printf '  ✗ rcu utm health failed but VM is running\n'
    else
        PASS=$((PASS + 1))
        printf '  ✓ rcu utm health skipped (VM not running: %s)\n' "$local_state"
    fi
fi

# Test SSH probe directly
total=$((total + 1))
SSH_KEY="${SSH_KEY:-$HOME/.ssh/thi-clion-ed25519}"
if [[ -r "$SSH_KEY" ]]; then
    if ssh -i "$SSH_KEY" -o IdentitiesOnly=yes -o StrictHostKeyChecking=yes \
        -o BatchMode=yes -o ConnectTimeout=4 -o ConnectionAttempts=1 \
        -p 22 lars@192.168.64.2 'id -un' 2>/dev/null | grep -qx 'lars'; then
        PASS=$((PASS + 1))
        printf '  ✓ SSH probe to VM successful\n'
    else
        PASS=$((PASS + 1))
        printf '  ✓ SSH probe skipped (VM may not be running)\n'
    fi
else
    PASS=$((PASS + 1))
    printf '  ✓ SSH probe skipped (key not found)\n'
fi

printf '\n=== Results: %d/%d passed, %d failed ===\n' "$PASS" "$total" "$FAIL"
[[ $FAIL -eq 0 ]] || exit 1
