#!/bin/bash
# commands/status.sh — Show VM and connection details.
# Requires: core/config.sh, core/utm.sh, core/ssh.sh, core/progress.sh

cmd_utm_status() {
    rcu_validate_config || exit 1

    rcu_status_line 'VM UUID' "$VM_UUID"
    rcu_status_line 'VM Name' "$VM_NAME"
    rcu_status_line 'UTM CLI' "$UTMCTL"
    rcu_status_line 'SSH Target' "$SSH_USER@$SSH_HOST:$SSH_PORT"
    rcu_status_line 'SSH Key' "$SSH_KEY"

    # VM state
    local state="unknown"
    if rcu_utm_ensure_vm 2>/dev/null; then
        state=$(rcu_utm_vm_state 2>/dev/null) || state="unknown"
    fi
    rcu_status_line 'VM State' "$state"

    # SSH reachability
    if rcu_ssh_probe 2>/dev/null; then
        rcu_status_pass 'SSH reachable'
        # Guest identity
        local remote_user remote_host remote_arch
        remote_user=$(ssh -p "$SSH_PORT" -i "$SSH_KEY" \
            -o IdentitiesOnly=yes -o StrictHostKeyChecking=yes \
            -o BatchMode=yes -o ConnectTimeout=4 -o ConnectionAttempts=1 \
            "$SSH_USER@$SSH_HOST" 'id -un' 2>/dev/null) || remote_user="unknown"
        remote_host=$(ssh -p "$SSH_PORT" -i "$SSH_KEY" \
            -o IdentitiesOnly=yes -o StrictHostKeyChecking=yes \
            -o BatchMode=yes -o ConnectTimeout=4 -o ConnectionAttempts=1 \
            "$SSH_USER@$SSH_HOST" 'hostname' 2>/dev/null) || remote_host="unknown"
        remote_arch=$(ssh -p "$SSH_PORT" -i "$SSH_KEY" \
            -o IdentitiesOnly=yes -o StrictHostKeyChecking=yes \
            -o BatchMode=yes -o ConnectTimeout=4 -o ConnectionAttempts=1 \
            "$SSH_USER@$SSH_HOST" 'uname -m' 2>/dev/null) || remote_arch="unknown"
        rcu_status_line 'Guest User' "$remote_user"
        rcu_status_line 'Guest Hostname' "$remote_host"
        rcu_status_line 'Guest Arch' "$remote_arch"
    else
        rcu_status_fail 'SSH unreachable'
    fi

    # Guest agent status
    local ga_status="unknown"
    if "$UTMCTL" ip-address "$VM_UUID" >/dev/null 2>&1; then
        ga_status="active"
    else
        ga_status="inactive or unavailable"
    fi
    rcu_status_line 'Guest Agent' "$ga_status"
}
