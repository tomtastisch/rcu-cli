#!/bin/bash
# tests/integration/test_installer.sh — Test install, update, rollback, uninstall cycle.
# Uses a temporary HOME to avoid touching the real installation.
# Must run on macOS.
set -euo pipefail

[[ "$(uname -s)" == Darwin ]] || { printf 'SKIP: macOS required\n'; exit 0; }

# shellcheck disable=SC1007
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../../" && pwd)
TMP=$(mktemp -d "$HOME/.rcu-integ-test.XXXXXX")
trap 'rm -rf "$TMP"' EXIT

# Override HOME for the entire test
export HOME="$TMP"
export XDG_CONFIG_HOME="$TMP/.config"

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
        printf '  ✗ %s\n' "$name" "$@"
    fi
}

check_file() {
    local name="$1"
    local path="$2"
    total=$((total + 1))
    if [[ -e "$path" ]]; then
        PASS=$((PASS + 1))
        printf '  ✓ %s\n' "$name"
    else
        FAIL=$((FAIL + 1))
        printf '  ✗ %s (missing: %s)\n' "$name" "$path"
    fi
}

check_symlink() {
    local name="$1"
    local path="$2"
    total=$((total + 1))
    if [[ -L "$path" ]]; then
        PASS=$((PASS + 1))
        printf '  ✓ %s\n' "$name"
    else
        FAIL=$((FAIL + 1))
        printf '  ✗ %s (not a symlink: %s)\n' "$name" "$path"
    fi
}

printf '=== Integration Tests: Installer Cycle ===\n'

# --- 1. First install ---
printf '\n--- First Install (v0.1.0) ---\n'
RCU_VERSION=0.1.0 "$ROOT/installer/install.sh"
check_file 'Bundle installed' "$TMP/.local/share/utm/rcu/releases/0.1.0"
check_symlink 'Current symlink' "$TMP/.local/share/utm/rcu/current"
check_file 'Launcher' "$TMP/.local/bin/rcu"
check_file 'Config' "$TMP/.config/rcu/config"
check_file 'Manifest' "$TMP/.local/share/utm/rcu/releases/0.1.0/install-manifest"

# Verify launcher works
check 'Launcher runs help' "$TMP/.local/bin/rcu" help

# Verify PATH entry in zshrc
total=$((total + 1))
if [[ -f "$TMP/.zshrc" ]] && grep -qF '# rcu-cli: managed PATH' "$TMP/.zshrc" 2>/dev/null; then
    PASS=$((PASS + 1))
    printf '  ✓ PATH entry in ~/.zshrc\n'
else
    FAIL=$((FAIL + 1))
    printf '  ✗ PATH entry missing in ~/.zshrc\n'
fi

# --- 2. Idempotent install ---
printf '\n--- Idempotent Install (v0.1.0 again) ---\n'
RCU_VERSION=0.1.0 "$ROOT/installer/install.sh"
check 'Idempotent install succeeds' true

# --- 3. Create v0.2.0 bundle for update test ---
printf '\n--- Prepare v0.2.0 ---\n'
V2_DIR="$TMP/v2-bundle"
mkdir -p "$V2_DIR"
cp -R "$ROOT/bin" "$ROOT/core" "$ROOT/commands" "$ROOT/config" "$ROOT/installer" "$V2_DIR/"
# Modify version (macOS sed syntax)
# shellcheck disable=SC2016
sed -i '' 's/RCU_VERSION.*0.1.0/RCU_VERSION="${RCU_VERSION:-0.2.0}"/' "$V2_DIR/installer/install.sh" 2>/dev/null || \
    sed -i 's/RCU_VERSION.*0.1.0/RCU_VERSION="${RCU_VERSION:-0.2.0}"/' "$V2_DIR/installer/install.sh"

# --- 4. Update to v0.2.0 ---
printf '\n--- Update to v0.2.0 ---\n'
RCU_NEW_VERSION=0.2.0 "$ROOT/installer/update.sh" "$V2_DIR"
check_file 'v0.2.0 installed' "$TMP/.local/share/utm/rcu/releases/0.2.0"
check_file 'Rollback backup exists' "$TMP/.local/share/utm/rcu/releases/rollback.0.1.0."* 2>/dev/null || {
    # Check if any rollback dir exists
    if ls "$TMP/.local/share/utm/rcu/releases/rollback."* >/dev/null 2>&1; then
        PASS=$((PASS + 1)); printf '  ✓ Rollback backup exists\n'; total=$((total + 1))
    else
        FAIL=$((FAIL + 1)); printf '  ✗ Rollback backup missing\n'; total=$((total + 1))
    fi
}
CURRENT_TARGET=$(readlink "$TMP/.local/share/utm/rcu/current")
total=$((total + 1))
if [[ "$CURRENT_TARGET" == *"0.2.0" ]]; then
    PASS=$((PASS + 1)); printf '  ✓ Current points to 0.2.0\n'
else
    FAIL=$((FAIL + 1)); printf '  ✗ Current does not point to 0.2.0: %s\n' "$CURRENT_TARGET"
fi

# --- 5. Rollback ---
printf '\n--- Rollback ---\n'
"$ROOT/installer/rollback.sh"
CURRENT_TARGET=$(readlink "$TMP/.local/share/utm/rcu/current")
total=$((total + 1))
if [[ "$CURRENT_TARGET" == *"rollback"* ]]; then
    PASS=$((PASS + 1)); printf '  ✓ Rolled back to backup\n'
else
    FAIL=$((FAIL + 1)); printf '  ✗ Rollback failed: %s\n' "$CURRENT_TARGET"
fi

# --- 6. Uninstall ---
printf '\n--- Uninstall ---\n'
"$ROOT/installer/uninstall.sh"
total=$((total + 1))
if [[ ! -e "$TMP/.local/share/utm/rcu" ]]; then
    PASS=$((PASS + 1)); printf '  ✓ Bundle removed\n'
else
    FAIL=$((FAIL + 1)); printf '  ✗ Bundle still exists\n'
fi

total=$((total + 1))
if [[ ! -e "$TMP/.local/bin/rcu" ]]; then
    PASS=$((PASS + 1)); printf '  ✓ Launcher removed\n'
else
    FAIL=$((FAIL + 1)); printf '  ✗ Launcher still exists\n'
fi

# Config should be preserved
check_file 'Config preserved after uninstall' "$TMP/.config/rcu/config"

# PATH entry should be removed
total=$((total + 1))
if [[ ! -f "$TMP/.zshrc" ]] || ! grep -qF '# rcu-cli: managed PATH' "$TMP/.zshrc" 2>/dev/null; then
    PASS=$((PASS + 1)); printf '  ✓ PATH entry removed from ~/.zshrc\n'
else
    FAIL=$((FAIL + 1)); printf '  ✗ PATH entry still in ~/.zshrc\n'
fi

# --- 7. Uninstall with --purge-data ---
printf '\n--- Uninstall --purge-data ---\n'
"$ROOT/installer/uninstall.sh" --purge-data
total=$((total + 1))
if [[ ! -d "$TMP/.config/rcu" ]]; then
    PASS=$((PASS + 1)); printf '  ✓ Config removed with --purge-data\n'
else
    FAIL=$((FAIL + 1)); printf '  ✗ Config still exists after --purge-data\n'
fi

printf '\n=== Results: %d/%d passed, %d failed ===\n' "$PASS" "$total" "$FAIL"
[[ $FAIL -eq 0 ]] || exit 1
