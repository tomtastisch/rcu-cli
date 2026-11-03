#!/bin/bash
# commands/shell.sh — Open interactive SSH session.
# Requires: core/config.sh, core/utm.sh, core/ssh.sh, core/progress.sh

cmd_utm_shell() {
    rcu_validate_config || exit 1

    rcu_utm_ensure_vm || exit 1
    local state
    state=$(rcu_utm_vm_state) || { rcu_error 'Cannot read VM state'; exit 1; }
    [[ "$state" == "started" ]] || { rcu_error "VM not started (state: $state)"; exit 1; }

    if ! rcu_ssh_probe; then
        rcu_notice 'SSH not yet ready, waiting...'
        if ! rcu_spin 'Checking SSH authentication' rcu_ssh_wait; then
            rcu_error 'SSH unavailable'
            exit 1
        fi
    fi

    rcu_notice 'USER: macOS-Host — Opening Debian shell; type exit to return to macOS.'
    rcu_ssh_terminal
}
