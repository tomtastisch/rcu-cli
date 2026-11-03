#!/bin/bash
# commands/connect.sh — Verify SSH connectivity without opening a shell.
# Requires: core/config.sh, core/utm.sh, core/ssh.sh, core/progress.sh

cmd_utm_connect() {
    rcu_validate_config || exit 1
    rcu_phase 1 3 'Tools and profile validated'

    rcu_utm_ensure_vm || exit 1
    local state
    state=$(rcu_utm_vm_state) || { rcu_error 'Cannot read VM state'; exit 1; }
    [[ "$state" == "started" ]] || { rcu_error "VM not started (state: $state)"; exit 1; }
    rcu_phase 2 3 'UTM reports VM running'

    if ! rcu_spin 'Checking SSH connection' rcu_ssh_wait; then
        rcu_error 'SSH login unavailable'
        exit 1
    fi

    rcu_phase 3 3 'SSH authenticated'
    rcu_notice 'Connection verified: %s@%s:%s' "$SSH_USER" "$SSH_HOST" "$SSH_PORT"
}
