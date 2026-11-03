#!/bin/bash
# installer/uninstall.sh — Safely remove RCU installation.
# Only removes RCU-owned files based on install manifest.
# Preserves user config and backups by default.
# Usage: ./installer/uninstall.sh [--purge-data]

set -euo pipefail

RCU_BUNDLE_DIR="$HOME/.local/share/utm/rcu"
RCU_LAUNCHER="$HOME/.local/bin/rcu"
RCU_CONF_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/rcu"
RCU_ZSHRC="$HOME/.zshrc"
RCU_PATH_MARKER='# rcu-cli: managed PATH'

PURGE_DATA=0
if [[ "${1:-}" == "--purge-data" ]]; then
    PURGE_DATA=1
fi

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

msg '=== RCU Uninstaller ==='

# 1. Remove launcher
if [[ -L "$RCU_LAUNCHER" ]]; then
    LINK_TARGET=$(readlink "$RCU_LAUNCHER")
    if [[ "$LINK_TARGET" == "$HOME/.local/share/utm/rcu/current/bin/rcu" ]]; then
        rm "$RCU_LAUNCHER"
        msg '✓ Removed launcher: ~/.local/bin/rcu'
    else
        msg '⚠ Launcher exists but points elsewhere: %s — skipping' "$LINK_TARGET"
    fi
elif [[ -f "$RCU_LAUNCHER" ]]; then
    # Check if it's the RCU launcher by content
    if grep -qF 'RCU_BUNDLE="$HOME/.local/share/utm/rcu/current"' "$RCU_LAUNCHER" 2>/dev/null; then
        rm "$RCU_LAUNCHER"
        msg '✓ Removed launcher: ~/.local/bin/rcu'
    else
        msg '⚠ Launcher exists but is not an RCU launcher — skipping for safety'
    fi
fi

# 2. Remove managed PATH entry from ~/.zshrc
if [[ -f "$RCU_ZSHRC" ]] && grep -qF "$RCU_PATH_MARKER" "$RCU_ZSHRC" 2>/dev/null; then
    TMPFILE=$(mktemp "$HOME/.zshrc.rcu.XXXXXX")
    awk -v m="$RCU_PATH_MARKER" '
        $0 == m { skip = 1; next }
        skip == 1 && /^export PATH.*\.local\/bin/ { skip = 0; next }
        skip == 1 && /^$/ { skip = 0; next }
        { print }
    ' "$RCU_ZSHRC" > "$TMPFILE"
    chmod --reference="$RCU_ZSHRC" "$TMPFILE" 2>/dev/null || chmod 600 "$TMPFILE"
    mv "$TMPFILE" "$RCU_ZSHRC"
    msg '✓ Removed managed PATH entry from ~/.zshrc'
fi

# 3. Remove bundle directory (releases + current symlink)
if [[ -e "$RCU_BUNDLE_DIR" ]]; then
    rm -rf "$RCU_BUNDLE_DIR"
    msg '✓ Removed bundle directory: ~/.local/share/utm/rcu/'
fi

# 4. Handle user config
if [[ -d "$RCU_CONF_DIR" ]]; then
    if [[ "$PURGE_DATA" -eq 1 ]]; then
        rm -rf "$RCU_CONF_DIR"
        msg '✓ Removed configuration: ~/.config/rcu/ (--purge-data)'
    else
        msg '✓ Configuration preserved: ~/.config/rcu/'
        msg '  To also remove config, re-run with --purge-data'
    fi
fi

msg ''
msg '=== RCU uninstalled ==='
msg 'Config and backups preserved (use --purge-data to remove them).'
