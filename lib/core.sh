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
ui_enabled() { [[ -t 1 && -t 2 ]] && command -v gum >/dev/null 2>&1; }
ui_card() {
  local title="$1" body="$2" content
  if ui_enabled; then
    content="$title"$'\n'"$body"
    gum style --border rounded --border-foreground 39 --padding '0 1' "$content"
  else
    printf '%s\n%s\n' "$title" "$body"
  fi
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
phase() {
  local step="$1" text="$2" percent
  percent=$((step*25))
  if ui_enabled; then
    ui_card "RCU  |  PHASE $step/4  |  $percent%" "$text"
  else
    printf '[%d/4] %d%% CHECKS  %s\n' "$step" "$percent" "$text"
  fi
}
progress_bar() {
  local percent="$1" width=24 filled empty bar i
  ((filled=percent*width/100))
  ((empty=width-filled))
  bar=''
  for ((i=0; i<filled; i++)); do bar="${bar}#"; done
  for ((i=0; i<empty; i++)); do bar="${bar}-"; done
  printf '[%s] %3d%%' "$bar" "$percent"
}
WAIT_STATUS_LINES=0
render_wait_status() {
  local elapsed="$1" state="$2" ssh_state="$3" percent="$4" bar rendered
  bar="$(progress_bar "$percent")"
  if ui_enabled; then
    rendered="$(gum style --border rounded --border-foreground 39 --padding '0 1' \
      'RCU  |  SSH-BEREITSCHAFT' \
      "VM: $state"$'\n'"SSH: $ssh_state"$'\n'"Wartefenster: $bar"$'\n'"Vergangen: ${elapsed}s / ${WAIT_SECONDS}s"
    )"
    if ((WAIT_STATUS_LINES > 0)); then
      printf '\033[%dA\033[0J' "$WAIT_STATUS_LINES"
    fi
    printf '%s\n' "$rendered"
    if ((WAIT_STATUS_LINES == 0)); then
      WAIT_STATUS_LINES="$(printf '%s\n' "$rendered" | wc -l | tr -d ' ')"
    fi
  else
    printf 'SSH_WAIT elapsed=%ss UTM=%s SSH=%s\n' "$elapsed" "$state" "$ssh_state"
  fi
}
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
wait_for_ssh() {
  local n=0 state percent current_percent
  while ((n<WAIT_SECONDS)); do
    state="$(utm_state 2>/dev/null || printf 'unknown')"
    if ssh_probe; then
      current_percent=$((n*100/WAIT_SECONDS))
      ((current_percent > 99)) && current_percent=99
      if ui_enabled; then
        while ((current_percent < 100)); do
          current_percent=$((current_percent+1))
          render_wait_status "$n" "$state" 'authenticated' "$current_percent"
          sleep 0.01
        done
      else
        render_wait_status "$n" "$state" 'authenticated' 100
      fi
      return 0
    fi
    percent=$((n*100/WAIT_SECONDS))
    ((percent > 99)) && percent=99
    render_wait_status "$n" "$state" 'unavailable' "$percent"
    sleep 2
    n=$((n+2))
  done
  state="$(utm_state 2>/dev/null || printf 'unknown')"
  if ui_enabled; then
    ui_card 'RCU  |  FEHLER' "SSH-Bereitschaft Timeout"$'\n'"VM: $state"$'\n'"Vergangen: ${n}s / ${WAIT_SECONDS}s" >&2
  else
    printf 'SSH_WAIT elapsed=%ss UTM=%s SSH=timeout\n' "$n" "$state" >&2
  fi
  return 1
}
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
