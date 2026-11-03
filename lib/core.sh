#!/bin/bash
# Safe configuration and SSH transport shared by the UTM backend.
_rcu_parse_config() {
  local file="$1" perm line key value raw
  [[ -f "$file" ]] || { [[ ! -L "$file" ]] || die 'Symlink config refused.'; return 0; }
  [[ ! -L "$file" && -r "$file" ]] || die 'Configuration must be a readable regular file.'
  if [[ "$(uname -s)" == Darwin ]]; then perm="$(stat -f '%Lp' "$file")"; else perm="$(stat -c '%a' "$file")"; fi
  [[ "$perm" == 600 || "$perm" == 400 ]] || die "Configuration permissions must be 0600 or 0400, not $perm."
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
    [[ "$line" =~ ^([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]] || die 'Invalid configuration syntax.'
    key="${BASH_REMATCH[1]}"
    raw="${BASH_REMATCH[2]}"
    case "$key" in
      VM_UUID|VM_NAME|SSH_HOST|SSH_USER|SSH_PORT|SSH_KEY|WAIT_SECONDS|UTMCTL) ;;
      *) die "Unknown configuration key: $key" ;;
    esac
    case "$raw" in
      \'*\') value="${raw:1:${#raw}-2}" ;;
      \"*\") value="${raw:1:${#raw}-2}" ;;
      *) value="$raw" ;;
    esac
    [[ "$value" != *'$('* && "$value" != *'`'* && "$value" != *';'* && "$value" != *'\n'* ]] || die "Unsafe configuration value for $key"
    value="${value//\$HOME/$HOME}"
    [[ "$value" != *'$'* && "$value" != *'\'* ]] || die "Unsupported configuration expansion for $key"
    printf -v "$key" '%s' "$value"
    export "$key"
  done < "$file"
}
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
notice() {
  if [[ -t 1 ]] && command -v gum >/dev/null 2>&1; then gum style --foreground 39 "$*"; else printf '%s\n' "$*"; fi
}
user_notice() {
  if [[ -t 1 ]]; then printf '\033[1;33mUSER: %s\033[0m\n' "$*"; else printf 'USER: %s\n' "$*"; fi
}
CONF="${RCU_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/rcu/config}"
_rcu_parse_config "$CONF"
VM_UUID="${VM_UUID:-A16B662F-A8E9-4615-B0E9-A16BA73BA7E7}"
VM_NAME="${VM_NAME:-Virtuelle Maschine}"
SSH_HOST="${SSH_HOST:-192.168.64.2}"
SSH_USER="${SSH_USER:-lars}"
SSH_PORT="${SSH_PORT:-22}"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/thi-clion-ed25519}"
WAIT_SECONDS="${WAIT_SECONDS:-120}"
UTMCTL="${UTMCTL:-/Applications/UTM.app/Contents/MacOS/utmctl}"
check() {
  [[ -x "$UTMCTL" ]] || die "UTM CLI absent: $UTMCTL"
  [[ -r "$SSH_KEY" ]] || die "SSH key missing: $SSH_KEY"
  [[ "$SSH_USER" =~ ^[a-z_][a-z0-9_-]*$ ]] || die 'Invalid SSH_USER.'
  [[ "$SSH_HOST" =~ ^[a-zA-Z0-9.:-]+$ ]] || die 'Invalid SSH_HOST.'
  [[ "$VM_UUID" =~ ^[0-9A-Fa-f-]{36}$ ]] || die 'Invalid VM_UUID.'
  [[ "$SSH_PORT" =~ ^[0-9]+$ ]] && (( 10#$SSH_PORT >= 1 && 10#$SSH_PORT <= 65535 )) || die 'Invalid SSH_PORT.'
  [[ "$WAIT_SECONDS" =~ ^[0-9]+$ ]] && (( 10#$WAIT_SECONDS >= 1 && 10#$WAIT_SECONDS <= 3600 )) || die 'Invalid WAIT_SECONDS.'
}
phase() { local step="$1" text="$2"; printf '[%d/4] %d%% CHECKS  %s\n' "$step" "$((step*25))" "$text"; }
spin() {
  local title="$1"; shift
  if [[ -t 1 ]] && command -v gum >/dev/null 2>&1; then
    if declare -F "$1" >/dev/null 2>&1; then
      gum spin --spinner dot --title "$title" -- /bin/bash -c 'source "$1/lib/core.sh"; source "$1/lib/backends/utm.sh"; shift; "$@"' _ "$RCU_ROOT" "$@"
    else
      gum spin --spinner dot --title "$title" -- "$@"
    fi
  else "$@"; fi
}
ssh_opts=(-p "$SSH_PORT" -i "$SSH_KEY" -o IdentitiesOnly=yes -o StrictHostKeyChecking=yes -o BatchMode=yes -o ConnectTimeout=4 -o ConnectionAttempts=1)
ssh_probe() { local result; result="$(ssh "${ssh_opts[@]}" "$SSH_USER@$SSH_HOST" 'id -un' 2>/dev/null)" || return 1; [[ "$result" == "$SSH_USER" ]]; }
ssh_terminal() { ssh -tt "${ssh_opts[@]}" "$SSH_USER@$SSH_HOST"; }
wait_probe() { local n=0; while ((n<WAIT_SECONDS)); do ssh_probe && return 0; sleep 2; n=$((n+2)); done; return 1; }
show_help() {
  printf '%s\n' 'rcu - Remote Control Unit (macOS host)' \
    'rcu utm start     Start VM, then verify SSH' \
    'rcu utm connect   Verify VM and SSH connectivity' \
    'rcu utm shell     Open Debian terminal (exit returns to macOS)' \
    'rcu utm stop      Request graceful shutdown only' \
    'rcu utm health    Check UTM and SSH authentication' \
    'rcu utm status    Show VM and SSH status' \
    'rcu update <dir>  Install a version from the trusted source directory' \
    'rcu rollback      Switch to previous managed version' \
    'rcu uninstall     Archive installed bundle and remove launcher' \
    'Progress percentage counts verified check stages, not guest boot progress.'
}
