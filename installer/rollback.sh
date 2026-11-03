#!/bin/bash
# installer/rollback.sh — Roll back to the previous verified RCU version.
# Looks for the most recent rollback.* directory in releases/.
# Usage: ./installer/rollback.sh

set -euo pipefail

RCU_BUNDLE_DIR="$HOME/.local/share/utm/rcu"
RCU_RELEASES_DIR="$RCU_BUNDLE_DIR/releases"
RCU_CURRENT_LINK="$RCU_BUNDLE_DIR/current"

msg() {
    if [[ -t 1 ]] && command -v gum >/dev/null 2>&1; then
        gum style --foreground 39 "$*"
    else
        printf '%s\n' "$*"
    fi
}

fail() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

[[ -d "$RCU_RELEASES_DIR" ]] || fail 'No RCU releases directory found. Is RCU installed?'

# Find the most recent rollback directory
# shellcheck disable=SC2012
ROLLBACK_DIR=$(ls -1d "$RCU_RELEASES_DIR"/rollback.* 2>/dev/null | sort -r | head -n1) || true
[[ -n "$ROLLBACK_DIR" && -d "$ROLLBACK_DIR" ]] || fail 'No rollback version found. Run an update first to create a backup.'

ROLLBACK_NAME=$(basename "$ROLLBACK_DIR")
msg 'Rolling back to: %s' "$ROLLBACK_NAME"

# Current version for info
CURRENT_VERSION=""
if [[ -L "$RCU_CURRENT_LINK" ]]; then
    CURRENT_VERSION=$(basename "$(readlink "$RCU_CURRENT_LINK")")
fi
msg 'Current version: %s' "${CURRENT_VERSION:-unknown}"

# Atomic symlink switch
rm -f "$RCU_CURRENT_LINK"
ln -s "$ROLLBACK_DIR" "$RCU_CURRENT_LINK"

msg '✓ Rolled back to %s' "$ROLLBACK_NAME"
msg 'Run: rcu help'
