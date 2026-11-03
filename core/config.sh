#!/bin/bash
# core/config.sh — Configuration loading and validation.
# Loads user config, applies defaults, validates all fields.
# This module is sourced by bin/rcu before any other core module.

set -euo pipefail

# Resolve the bundle root from the launcher or the script's own location.
_rcu_resolve_bundle_root() {
    local script_path
    # shellcheck disable=SC1007
    script_path="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
    # bin/rcu lives in <bundle>/bin/rcu, so go up one level.
    printf '%s' "$(dirname "$script_path")"
}

RCU_BUNDLE_ROOT="${RCU_BUNDLE_ROOT:-$(_rcu_resolve_bundle_root)}"

# Configuration file path
RCU_CONF="${RCU_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/rcu/config}"

# Load configuration if present
if [[ -f "$RCU_CONF" ]]; then
    # Safety: no symlinks, must be readable
    if [[ -L "$RCU_CONF" ]]; then
        printf 'ERROR: Config is a symlink (unsafe): %s\n' "$RCU_CONF" >&2
        exit 1
    fi
    if [[ ! -r "$RCU_CONF" ]]; then
        printf 'ERROR: Config unreadable: %s\n' "$RCU_CONF" >&2
        exit 1
    fi
    # shellcheck source=/dev/null
    source "$RCU_CONF"
fi

# Apply defaults (user config takes precedence since it was sourced first)
VM_UUID="${VM_UUID:-A16B662F-A8E9-4615-B0E9-A16BA73BA7E7}"
VM_NAME="${VM_NAME:-Virtuelle Maschine}"
SSH_HOST="${SSH_HOST:-192.168.64.2}"
SSH_USER="${SSH_USER:-lars}"
SSH_PORT="${SSH_PORT:-22}"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/thi-clion-ed25519}"
WAIT_SECONDS="${WAIT_SECONDS:-120}"
UTMCTL="${UTMCTL:-/Applications/UTM.app/Contents/MacOS/utmctl}"

# Validate configuration values
rcu_validate_config() {
    local errors=0

    # UTMCTL must exist and be executable
    if [[ ! -x "$UTMCTL" ]]; then
        printf 'ERROR: UTM CLI absent or not executable: %s\n' "$UTMCTL" >&2
        errors=1
    fi

    # SSH key must exist and be readable
    if [[ ! -r "$SSH_KEY" ]]; then
        printf 'ERROR: SSH key missing or unreadable: %s\n' "$SSH_KEY" >&2
        errors=1
    fi

    # SSH_USER must be a valid username pattern
    if [[ ! "$SSH_USER" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
        printf 'ERROR: Invalid SSH_USER: %s\n' "$SSH_USER" >&2
        errors=1
    fi

    # SSH_HOST must be a valid host pattern
    if [[ ! "$SSH_HOST" =~ ^[a-zA-Z0-9.:-]+$ ]]; then
        printf 'ERROR: Invalid SSH_HOST: %s\n' "$SSH_HOST" >&2
        errors=1
    fi

    # SSH_PORT must be a valid port number
    if [[ ! "$SSH_PORT" =~ ^[0-9]+$ ]] || (( SSH_PORT < 1 || SSH_PORT > 65535 )); then
        printf 'ERROR: Invalid SSH_PORT: %s\n' "$SSH_PORT" >&2
        errors=1
    fi

    # WAIT_SECONDS must be a reasonable timeout
    if [[ ! "$WAIT_SECONDS" =~ ^[0-9]+$ ]] || (( WAIT_SECONDS < 1 || WAIT_SECONDS > 3600 )); then
        printf 'ERROR: Invalid WAIT_SECONDS: %s\n' "$WAIT_SECONDS" >&2
        errors=1
    fi

    # VM_UUID must be non-empty
    if [[ -z "$VM_UUID" ]]; then
        printf 'ERROR: VM_UUID is not set\n' >&2
        errors=1
    fi

    return $errors
}
