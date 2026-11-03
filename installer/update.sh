#!/bin/bash
# installer/update.sh — Atomically update to a new RCU version.
# Requires: new bundle staged at ~/.local/share/.rcu-stage-*/
# The new bundle must have a different RCU_VERSION.
# Usage: RCU_NEW_VERSION=0.2.0 ./installer/update.sh <path-to-new-bundle>

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

[[ $# -ge 1 ]] || fail 'Usage: update.sh <path-to-new-bundle-root>'
NEW_BUNDLE="$1"

# Read new version
NEW_VERSION="${RCU_NEW_VERSION:-}"
if [[ -z "$NEW_VERSION" ]]; then
    # Try to read from new bundle's install.sh
    if [[ -f "$NEW_BUNDLE/installer/install.sh" ]]; then
        NEW_VERSION=$('grep' -oP 'RCU_VERSION\:-\K[0-9.]+' "$NEW_BUNDLE/installer/install.sh" 2>/dev/null || printf '')
    fi
    [[ -n "$NEW_VERSION" ]] || fail 'Cannot determine new version. Set RCU_NEW_VERSION env var.'
fi

# Check current version
CURRENT_VERSION=""
if [[ -L "$RCU_CURRENT_LINK" ]]; then
    CURRENT_TARGET=$(readlink "$RCU_CURRENT_LINK")
    CURRENT_VERSION=$(basename "$CURRENT_TARGET")
fi

if [[ "$NEW_VERSION" == "$CURRENT_VERSION" ]]; then
    msg 'Already running version %s. Nothing to update.' "$NEW_VERSION"
    exit 0
fi

msg 'Updating RCU: %s → %s' "${CURRENT_VERSION:-none}" "$NEW_VERSION"

# Validate new bundle
for f in bin/rcu core/config.sh core/utm.sh core/ssh.sh core/progress.sh \
         commands/start.sh commands/connect.sh commands/shell.sh \
         commands/stop.sh commands/health.sh commands/status.sh; do
    [[ -f "$NEW_BUNDLE/$f" ]] || fail "Missing in new bundle: $f"
done

# Syntax check
for f in "$NEW_BUNDLE"/bin/rcu "$NEW_BUNDLE"/core/*.sh "$NEW_BUNDLE"/commands/*.sh; do
    /bin/bash -n "$f" 2>/dev/null || fail "Syntax error in new bundle: $f"
done
msg '✓ New bundle validated'

# Backup current version directory (for rollback)
if [[ -L "$RCU_CURRENT_LINK" ]] && [[ -d "$(readlink "$RCU_CURRENT_LINK")" ]]; then
    BACKUP_DIR="$RCU_RELEASES_DIR/rollback.$CURRENT_VERSION.$(date +%Y%m%d%H%M%S)"
    cp -R "$(readlink "$RCU_CURRENT_LINK")" "$BACKUP_DIR"
    msg '✓ Current version backed up to rollback.%s' "$CURRENT_VERSION"
fi

# Stage new version
NEW_VERSION_DIR="$RCU_RELEASES_DIR/$NEW_VERSION"
if [[ -d "$NEW_VERSION_DIR" ]]; then
    rm -rf "$NEW_VERSION_DIR"
fi
mkdir -p "$NEW_VERSION_DIR"
cp -R "$NEW_BUNDLE/bin" "$NEW_BUNDLE/core" "$NEW_BUNDLE/commands" "$NEW_BUNDLE/config" "$NEW_VERSION_DIR/"

# Create manifest
cat > "$NEW_VERSION_DIR/install-manifest" <<MANIFEST
# RCU Install Manifest — do not edit
version=$NEW_VERSION
installed_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
files=bin/rcu
files=core/config.sh
files=core/utm.sh
files=core/ssh.sh
files=core/progress.sh
files=commands/start.sh
files=commands/connect.sh
files=commands/shell.sh
files=commands/stop.sh
files=commands/health.sh
files=commands/status.sh
MANIFEST

# Atomic symlink switch
rm -f "$RCU_CURRENT_LINK"
ln -s "$NEW_VERSION_DIR" "$RCU_CURRENT_LINK"

msg '✓ RCU updated to v%s' "$NEW_VERSION"
msg 'Run: rcu help'
