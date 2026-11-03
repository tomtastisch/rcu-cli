#!/bin/bash
# commands/stop.sh — Request graceful VM shutdown.
# Requires: core/config.sh, core/utm.sh, core/ssh.sh, core/progress.sh

cmd_utm_stop() {
    rcu_validate_config || exit 1

    rcu_utm_ensure_vm || exit 1
    local state
    state=$(rcu_utm_vm_state) || { rcu_error 'Cannot read VM state'; exit 1; }

    if [[ "$state" == "stopped" ]]; then
        rcu_notice 'VM is already stopped.'
        return 0
    fi

    if [[ "$state" != "started" ]]; then
        rcu_error "VM in unexpected state: $state"
        exit 1
    fi

    rcu_notice 'USER: macOS-Host — Requesting graceful VM shutdown. Do not force-close the VM.'
    rcu_spin 'Requesting guest shutdown' rcu_utm_stop_vm || { rcu_error 'UTM graceful stop request failed'; exit 1; }

    rcu_notice 'Waiting for VM to stop...'
    if ! rcu_utm_wait_state "stopped" "$WAIT_SECONDS"; then
        rcu_error 'Shutdown not confirmed within timeout; VM was not forcibly stopped.'
        exit 1
    fi

    rcu_notice 'UTM confirms VM stopped.'
}
