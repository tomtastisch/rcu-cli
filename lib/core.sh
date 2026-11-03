#!/bin/bash
# Shared UI, safe configuration, and SSH transport. No VM mutation here.
CONF="${RCU_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/rcu/config}"
if [[ -f "$CONF" ]]; then
  [[ ! -L "$CONF" && -r "$CONF" ]] || { printf 'Config unsafe/unreadable: %s\n' "$CONF" >&2; exit 1; }
  # Trusted, user-owned shell assignments (not an external input format).
  source "$CONF"
fi
VM_NAME="${VM_NAME:-Virtuelle Maschine}"
SSH_HOST="${SSH_HOST:-192.168.64.2}"
SSH_USER="${SSH_USER:-lars}"
SSH_PORT="${SSH_PORT:-22}"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/thi-clion-ed25519}"
WAIT_SECONDS="${WAIT_SECONDS:-120}"
UTMCTL="${UTMCTL:-/Applications/UTM.app/Contents/MacOS/utmctl}"
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
notice() { if [[ -t 1 ]] && command -v gum >/dev/null; then gum style --foreground 39 "$*"; else printf '%s\n' "$*"; fi; }
phase() {
  local n="$1" label="$2"
  printf '[%d/4] %3d%% CHECKS  %s\n' "$n" "$((n*25))" "$label"
}
spin() {
  local title="$1"; shift
  if [[ -t 1 ]] && command -v gum >/dev/null; then
    if declare -F "$1" >/dev/null; then
      gum spin --spinner dot --title "$title" -- /bin/bash -c 'source "$1/lib/core.sh"; source "$1/lib/backends/utm.sh"; shift; "$@"' _ "$RCU_ROOT" "$@"
    else
      gum spin --spinner dot --title "$title" -- "$@"
    fi
  else "$@"; fi
}
check() {
  [[ -x "$UTMCTL" ]] || die "UTM CLI absent: $UTMCTL"
  [[ -r "$SSH_KEY" ]] || die "SSH key missing: $SSH_KEY"
  [[ "$SSH_USER" =~ ^[a-z_][a-z0-9_-]*$ ]] || die 'Invalid SSH_USER'
  [[ "$SSH_HOST" =~ ^[a-zA-Z0-9.:-]+$ ]] || die 'Invalid SSH_HOST'
  [[ "$SSH_PORT" =~ ^[0-9]+$ ]] && ((SSH_PORT>=1 && SSH_PORT<=65535)) || die 'Invalid SSH_PORT'
  [[ "$WAIT_SECONDS" =~ ^[0-9]+$ ]] && ((WAIT_SECONDS>=1 && WAIT_SECONDS<=3600)) || die 'Invalid WAIT_SECONDS'
}
ssh_opts=(-p "$SSH_PORT" -i "$SSH_KEY" -o IdentitiesOnly=yes -o StrictHostKeyChecking=yes -o BatchMode=yes -o ConnectTimeout=4 -o ConnectionAttempts=1)
ssh_probe() { ssh "${ssh_opts[@]}" "$SSH_USER@$SSH_HOST" 'id -un' 2>/dev/null | grep -qx "$SSH_USER"; }
ssh_terminal() { ssh -tt "${ssh_opts[@]}" "$SSH_USER@$SSH_HOST"; }
wait_probe() {
  local t=0
  while ((t<WAIT_SECONDS)); do
    if ssh_probe; then return 0; fi
    sleep 2
    t=$((t+2))
  done
  return 1
}
show_help() {
  printf '%s\n' 'rcu - Remote Control Unit (run on macOS)' '' 'rcu utm start     Start VM and await verified SSH login' 'rcu utm connect   Verify remote connection without opening a shell' 'rcu utm shell     Open Debian terminal (exit returns to macOS)' 'rcu utm stop      Ask guest to shut down safely; never force stop' 'rcu utm health    Check UTM, networking and SSH authentication' 'rcu utm status    Show UTM state and connection details' '' 'Progress percentages represent verified checks, not actual kernel boot percentage.'
}
