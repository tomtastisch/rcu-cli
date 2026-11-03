#!/bin/bash
# Shared UI, safe configuration, and SSH transport. No VM mutation here.
# --- Safe config parser: no source, no eval, no shell-code execution ---
_rcu_parse_config() {
  local conf_file="$1"
  [[ -f "$conf_file" ]] || return 0
  [[ ! -L "$conf_file" ]] || { printf 'Config is a symlink (unsafe): %s\n' "$conf_file" >&2; exit 1; }
  [[ -r "$conf_file" ]] || { printf 'Config unreadable: %s\n' "$conf_file" >&2; exit 1; }
  # Check permissions: owner-read/write only (0600 or stricter)
  local perms_oct
  perms_oct=$(stat -f '%Lp' "$conf_file" 2>/dev/null) || { printf 'Cannot stat config: %s\n' "$conf_file" >&2; exit 1; }
  # stat -f '%Lp' returns octal string; prefix with 8# for arithmetic
  (( 8#$perms_oct & 8#77 )) && { printf 'Config too permissive (%s): %s\n' "$perms_oct" "$conf_file" >&2; exit 1; }
  local line_num=0
  while IFS= read -r line || [[ -n "$line" ]]; do
    line_num=$((line_num + 1))
    # Skip comments and blank lines
    [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
    # Strip leading/trailing whitespace
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    # Match KEY='value', KEY="value", or KEY=value (unquoted)
    if [[ "$line" =~ ^([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]]; then
      local key="${BASH_REMATCH[1]}"
      local raw_val="${BASH_REMATCH[2]}"
      # Validate key is an allowed config field
      case "$key" in
        VM_NAME|SSH_HOST|SSH_USER|SSH_PORT|SSH_KEY|WAIT_SECONDS|UTMCTL) ;;
        *) printf 'Config line %d: unknown key "%s" (ignored)\n' "$line_num" "$key" >&2; continue ;;
      esac
      # Parse value: strip quotes
      local val=""
      if [[ "$raw_val" =~ ^\'.*\'$ ]]; then
        val="${raw_val:1:${#raw_val}-2}"
      elif [[ "$raw_val" =~ ^\".*\"$ ]]; then
        val="${raw_val:1:${#raw_val}-2}"
      elif [[ "$raw_val" =~ ^[A-Za-z0-9_./:@%^+=,-]+$ ]]; then
        val="$raw_val"
      else
        printf 'Config line %d: invalid value for %s (unsafe characters)\n' "$line_num" "$key" >&2
        continue
      fi
      # Expand $HOME in values safely
      val="${val//\$HOME/$HOME}"
      # Export the variable
      export "$key"="$val"
    else
      printf 'Config line %d: invalid syntax (ignored): %s\n' "$line_num" "$line" >&2
    fi
  done < "$conf_file"
}
CONF="${RCU_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/rcu/config}"
_rcu_parse_config "$CONF"
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
  if [[ ! "$SSH_PORT" =~ ^[0-9]+$ ]] || ((SSH_PORT<1 || SSH_PORT>65535)); then die 'Invalid SSH_PORT'; fi
  if [[ ! "$WAIT_SECONDS" =~ ^[0-9]+$ ]] || ((WAIT_SECONDS<1 || WAIT_SECONDS>3600)); then die 'Invalid WAIT_SECONDS'; fi
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
  printf '%s\n' \
    'rcu - Remote Control Unit (run on macOS)' \
    '' \
    'VM commands:' \
    '  rcu utm start     Start VM and await verified SSH login' \
    '  rcu utm connect   Verify remote connection without opening a shell' \
    '  rcu utm shell     Open Debian terminal (exit returns to macOS)' \
    '  rcu utm stop      Ask guest to shut down safely; never force stop' \
    '  rcu utm health    Check UTM, networking and SSH authentication' \
    '  rcu utm status    Show UTM state and connection details' \
    '' \
    'Management commands:' \
    '  rcu update        Reinstall or update rcu from source directory' \
    '  rcu rollback      Restore the last working version' \
    '  rcu uninstall     Remove rcu symlink and PATH entry (preserves config)' \
    '' \
    'Progress percentages represent verified checks, not actual kernel boot percentage.'
}
