#!/bin/bash
# commands/health.sh — Verify UTM and SSH availability.
# Requires: core/config.sh, core/utm.sh, core/ssh.sh, core/progress.sh

cmd_utm_health() {
    rcu_validate_config || exit 1

    rcu_utm_ensure_vm || exit 1
    local state
    state=$(rcu_utm_vm_state) || { rcu_error 'Cannot read VM state'; exit 1; }

    rcu_status_line 'UTM' "$UTMCTL"
    rcu_status_line 'VM UUID' "$VM_UUID"
    rcu_status_line 'VM Name' "$VM_NAME"
    rcu_status_line 'VM State' "$state"

    if [[ "$state" != "started" ]]; then
        rcu_status_fail 'VM not running'
        exit 1
    fi
    rcu_status_pass 'VM running'

    if rcu_ssh_probe; then
        rcu_status_pass 'SSH authenticated'
    else
        rcu_status_fail 'SSH auth or network check failed'
        exit 1
    fi

    rcu_notice 'HEALTH=PASS (UTM + SSH verified; guest agent status separate)'
}
