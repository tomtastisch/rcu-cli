#!/bin/bash
# core/ssh.sh — SSH transport operations.
# Requires: core/config.sh already sourced (SSH_HOST, SSH_USER, SSH_PORT, SSH_KEY).

# SSH options array — strict, batch-mode, key-only
_rcu_ssh_opts=()
_rcu_ssh_opts=(-p "$SSH_PORT" -i "$SSH_KEY" -o IdentitiesOnly=yes -o StrictHostKeyChecking=yes -o BatchMode=yes -o ConnectTimeout=4 -o ConnectionAttempts=1)

# Probe SSH — returns 0 if remote user matches expected SSH_USER
rcu_ssh_probe() {
    local result
    result=$(ssh "${_rcu_ssh_opts[@]}" "$SSH_USER@$SSH_HOST" 'id -un' 2>/dev/null) || return 1
    [[ "$result" == "$SSH_USER" ]]
}

# Wait for SSH to become available
rcu_ssh_wait() {
    local timeout="${1:-$WAIT_SECONDS}"
    local elapsed=0

    while (( elapsed < timeout )); do
        if rcu_ssh_probe; then
            return 0
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done

    return 1
}

# Open interactive SSH terminal — passes through directly, no pipe
rcu_ssh_terminal() {
    ssh -tt "${_rcu_ssh_opts[@]}" "$SSH_USER@$SSH_HOST"
}

# Get remote architecture
rcu_ssh_remote_arch() {
    ssh "${_rcu_ssh_opts[@]}" "$SSH_USER@$SSH_HOST" 'uname -m' 2>/dev/null || printf 'unknown'
}

# Get remote hostname
rcu_ssh_remote_hostname() {
    ssh "${_rcu_ssh_opts[@]}" "$SSH_USER@$SSH_HOST" 'hostname' 2>/dev/null || printf 'unknown'
}

# Get remote OS info
rcu_ssh_remote_os() {
    ssh "${_rcu_ssh_opts[@]}" "$SSH_USER@$SSH_HOST" 'lsb_release -ds 2>/dev/null || cat /etc/os-release 2>/dev/null || echo unknown' 2>/dev/null || printf 'unknown'
}
