#!/bin/bash
# commands/start.sh — Start VM and await SSH readiness.
# Requires: core/config.sh, core/utm.sh, core/ssh.sh, core/progress.sh

cmd_utm_start() {
    rcu_validate_config || exit 1
    rcu_phase 1 4 'UTM and SSH profile validated'

    rcu_utm_ensure_vm || exit 1
    rcu_phase 2 4 'VM found in UTM'

    local state
    state=$(rcu_utm_vm_state) || { rcu_error 'Cannot read VM state'; exit 1; }

    if [[ "$state" == "started" ]]; then
        rcu_notice 'VM is already running.'
    else
        rcu_notice 'USER: macOS-Host — Starting VM via UTM...'
        rcu_spin 'Requesting VM start' rcu_utm_start_vm || { rcu_error 'UTM start failed'; exit 1; }
    fi

    rcu_phase 3 4 'UTM reports VM started or start requested'

    rcu_notice 'Waiting for SSH readiness...'
    if ! rcu_spin 'Checking SSH readiness' rcu_ssh_wait; then
        rcu_error 'Timed out waiting for authenticated SSH; VM may still be booting'
        exit 1
    fi

    rcu_phase 4 4 'Remote SSH identity authenticated'
    rcu_notice 'VM is running and SSH is ready.'
}
