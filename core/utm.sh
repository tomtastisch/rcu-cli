#!/bin/bash
# core/utm.sh — UTM/utmctl operations. VM identified by UUID.
# Requires: core/config.sh already sourced (UTMCTL, VM_UUID, VM_NAME).

# Run utmctl with arguments
rcu_utm_cmd() {
    "$UTMCTL" "$@"
}

# Get VM state by UUID — returns "started", "stopped", etc.
rcu_utm_vm_state() {
    local state
    state=$(rcu_utm_cmd list 2>/dev/null \
        | awk -v uuid="$VM_UUID" '
            NR > 1 {
                if ($1 == uuid) {
                    print $2
                    found = 1
                    exit
                }
            }
            END { if (!found) exit 1 }
        ') || return 1
    printf '%s' "$state"
}

# Verify VM exists in UTM list
rcu_utm_ensure_vm() {
    if ! rcu_utm_vm_state >/dev/null 2>&1; then
        printf 'ERROR: VM not found in UTM (UUID: %s, Name: %s)\n' "$VM_UUID" "$VM_NAME" >&2
        return 1
    fi
    return 0
}

# Start VM if stopped; returns 0 when VM is running
rcu_utm_start_vm() {
    local state
    state=$(rcu_utm_vm_state) || { printf 'ERROR: Cannot read VM state\n' >&2; return 1; }

    if [[ "$state" == "started" ]]; then
        return 0
    fi

    if [[ "$state" != "stopped" ]]; then
        printf 'ERROR: VM in unexpected state: %s (cannot safely start)\n' "$state" >&2
        return 1
    fi

    rcu_utm_cmd start "$VM_UUID" || { printf 'ERROR: UTM start failed\n' >&2; return 1; }
    return 0
}

# Request graceful VM shutdown (never force)
rcu_utm_stop_vm() {
    local state
    state=$(rcu_utm_vm_state) || { printf 'ERROR: Cannot read VM state\n' >&2; return 1; }

    if [[ "$state" == "stopped" ]]; then
        return 0
    fi

    if [[ "$state" != "started" ]]; then
        printf 'ERROR: VM in unexpected state for shutdown: %s\n' "$state" >&2
        return 1
    fi

    # Check utmctl supports --request flag
    if rcu_utm_cmd stop --request "$VM_UUID" 2>/dev/null; then
        return 0
    else
        # Fallback: try without --request
        rcu_utm_cmd stop "$VM_UUID" || { printf 'ERROR: UTM stop request failed\n' >&2; return 1; }
        return 0
    fi
}

# Wait for VM to reach expected state
rcu_utm_wait_state() {
    local target_state="$1"
    local timeout="${2:-$WAIT_SECONDS}"
    local elapsed=0

    while (( elapsed < timeout )); do
        local current
        current=$(rcu_utm_vm_state 2>/dev/null) || { sleep 2; elapsed=$((elapsed + 2)); continue; }
        if [[ "$current" == "$target_state" ]]; then
            return 0
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done

    printf 'ERROR: VM did not reach state "%s" within %ds\n' "$target_state" "$timeout" >&2
    return 1
}

# List all VMs
rcu_utm_list_vms() {
    rcu_utm_cmd list 2>/dev/null || { printf 'ERROR: Cannot list VMs\n' >&2; return 1; }
}
