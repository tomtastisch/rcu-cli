#!/bin/bash
# Strict data-only configuration, shared terminal UI and transport.
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
ui_enabled() { [[ -t 1 && -t 2 && "${TERM:-dumb}" != dumb && -z "${NO_COLOR:-}" ]] && command -v gum >/dev/null 2>&1; }
notice() { printf '%s\n' "$*"; }
ui_card() {
  if ui_enabled; then gum style --border rounded --border-foreground 38 --padding '0 1' "$1" "$2"; else printf '%s\n%s\n' "$1" "$2"; fi
}
user_notice() {
  if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then printf '\033[33mUSER: %s\033[0m\n' "$*"; else printf 'USER: %s\n' "$*"; fi
}
phase() { notice "  [$1/4] $2"; }
spin() { local title="$1"; shift; notice "  $title"; "$@"; }
# Hard deadline for guest-agent / Apple Events operations, which may otherwise hang.
# A function is executed in a subshell; it never changes the caller's state.
bounded() (
  local limit="$1" worker rc=0 begin=$SECONDS; shift
  # A separate job group includes descendants (SSH -> askpass -> security).
  # Preserve stdin explicitly: asynchronous commands otherwise lose heredocs.
  set -m
  "$@" <&0 & worker=$!
  set +m
  trap 'kill -KILL -- "-$worker" 2>/dev/null || true; wait "$worker" 2>/dev/null || true' EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  while kill -0 "$worker" 2>/dev/null; do
    if ((SECONDS-begin>=limit)); then
      kill -KILL -- "-$worker" 2>/dev/null || true
      wait "$worker" 2>/dev/null || true
      return 124
    fi
    sleep 0.1
  done
  wait "$worker" || rc=$?
  return "$rc"
)
_rcu_parse_config() {
  local file="$1" perm line key value raw
  [[ -f "$file" ]] || { [[ ! -L "$file" ]] || die 'Symlink config refused.'; return 0; }
  [[ ! -L "$file" && -r "$file" && -O "$file" ]] || die 'Configuration must be an owned readable regular file.'
  if [[ "$(uname -s)" == Darwin ]]; then perm="$(stat -f '%Lp' "$file")"; else perm="$(stat -c '%a' "$file")"; fi
  [[ "$perm" == 600 || "$perm" == 400 ]] || die "Configuration permissions must be 0600 or 0400, not $perm."
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
    [[ "$line" =~ ^([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]] || die 'Invalid configuration syntax.'
    key="${BASH_REMATCH[1]}"; raw="${BASH_REMATCH[2]}"
    case "$key" in
      KEYCHAIN_SERVICE|CONFIG_VERSION|VM_UUID|VM_NAME|SSH_HOST|SSH_USER|SSH_PORT|SSH_KEY|WAIT_SECONDS|UTMCTL|AUTH_MODE|ADDRESS_MODE) ;;
      SSH_PASSWORD) LEGACY_SECRET=1; continue ;;
      *) die "Unknown configuration key: $key" ;;
    esac
    case "$raw" in
      \'*\') value="${raw:1:${#raw}-2}" ;;
      \"*\") value="${raw:1:${#raw}-2}" ;;
      *) value="$raw" ;;
    esac
    [[ "$value" != *'$('* && "$value" != *'`'* && "$value" != *';'* ]] || die "Unsafe configuration value for $key"
    value="${value//\$HOME/$HOME}"
    [[ "$value" != *'$'* && "$value" != *'\'* && "$value" != *\'* && "$value" != *\"* && "$value" != *[$'\001'-$'\037'$'\177']* ]] || die "Unsupported configuration value for $key"
    printf -v "$key" '%s' "$value"
  done < "$file"
}
CONF="${RCU_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/rcu/config}"
CONFIG_VERSION=''; VM_UUID=''; VM_NAME=''; SSH_HOST=''; SSH_USER=''; SSH_KEY=''
KEYCHAIN_SERVICE=''; AUTH_MODE=agent; ADDRESS_MODE=auto; SSH_PORT=22; WAIT_SECONDS=120; UTMCTL=''; LEGACY_SECRET=0
# Help and release management must remain usable even with a broken old profile.
case "${1:-}" in help|--help|--version|setup|update|rollback|uninstall) ;; *) _rcu_parse_config "$CONF" ;; esac
find_utmctl() {
  local candidate
  if [[ -n "${RCU_UTMCTL_PATH:-}" ]]; then candidate="$RCU_UTMCTL_PATH"
  elif [[ -n "$UTMCTL" ]]; then candidate="$UTMCTL"
  elif command -v utmctl >/dev/null 2>&1; then candidate="$(command -v utmctl)"
  else
    for candidate in /Applications/UTM.app/Contents/MacOS/utmctl "$HOME/Applications/UTM.app/Contents/MacOS/utmctl"; do
      [[ ! -x "$candidate" ]] || break
    done
  fi
  [[ -x "$candidate" ]] || die 'UTM CLI not found. Install UTM or set RCU_UTMCTL_PATH to its utmctl executable.'
  UTMCTL="$candidate"
}
valid_uuid() { [[ "$1" =~ ^[[:xdigit:]]{8}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{12}$ ]]; }
check() {
  find_utmctl
  valid_uuid "$VM_UUID" || die 'Invalid VM_UUID; run rcu setup.'
  [[ "$SSH_USER" =~ ^[a-zA-Z_][a-zA-Z0-9_.-]*\$?$ ]] || die 'Invalid guest username; run rcu setup.'
  [[ -z "$SSH_KEY" || ( "$SSH_KEY" == /* && -r "$SSH_KEY" ) ]] || die 'Configured SSH key unreadable; run rcu setup.'
  [[ "$SSH_PORT" =~ ^[0-9]{1,5}$ ]] && ((10#$SSH_PORT>=1 && 10#$SSH_PORT<=65535)) || die 'Invalid SSH_PORT.'
  [[ "$WAIT_SECONDS" =~ ^[0-9]{1,4}$ ]] && ((10#$WAIT_SECONDS>=1 && 10#$WAIT_SECONDS<=3600)) || die 'Invalid WAIT_SECONDS.'
  SSH_PORT=$((10#$SSH_PORT)); WAIT_SECONDS=$((10#$WAIT_SECONDS))
  [[ "$AUTH_MODE" == agent || "$AUTH_MODE" == keychain ]] || die 'Invalid AUTH_MODE.'
  [[ -z "$KEYCHAIN_SERVICE" || "$KEYCHAIN_SERVICE" == "rcu.vm.$VM_UUID" || "$KEYCHAIN_SERVICE" =~ ^rcu\.vm\.$VM_UUID\.[[:alnum:]]{12}$ ]] || die 'Invalid Keychain service for selected VM.'
  [[ "$ADDRESS_MODE" == auto || "$ADDRESS_MODE" == manual ]] || die 'Invalid ADDRESS_MODE.'
  [[ "$LEGACY_SECRET" == 0 ]] || die 'Legacy plaintext password refused. Run rcu setup to replace it with Keychain authentication.'
}
prepare_profile() {
  if [[ "$CONFIG_VERSION" != 1 || -z "$VM_UUID" || -z "$SSH_USER" ]]; then
    user_notice 'Einmalige Einrichtung erforderlich. Bestehende Entwicklungsrechner-Vorgaben werden nicht übernommen.'
    setup_profile
  fi
  check
  ensure_vm
}
WAIT_STATUS_LINES=0
render_wait_status() {
  local elapsed="$1" state="$2" ssh_state="$3"
  if ui_enabled; then
    if ((WAIT_STATUS_LINES>0)); then printf '\033[%dA\033[0J' "$WAIT_STATUS_LINES"; fi
    printf '  VM   %s  |  %s\n  SSH  %s  |  %ss / %ss\n' "$VM_NAME" "$state" "$ssh_state" "$elapsed" "$WAIT_SECONDS"
    WAIT_STATUS_LINES=2
  else printf 'SSH_WAIT elapsed=%ss UTM=%s SSH=%s\n' "$elapsed" "$state" "$ssh_state"; fi
}
security_cmd() {
  if [[ "${RCU_TEST:-0}" == 1 ]]; then security "$@"; else /usr/bin/security "$@"; fi
}
ssh_options() {
  ssh_opts=(-p "$SSH_PORT" -o StrictHostKeyChecking=yes -o "HostKeyAlias=rcu-$VM_UUID" -o "UserKnownHostsFile=$(dirname "$CONF")/known_hosts" -o ConnectTimeout=4 -o ConnectionAttempts=1)
  [[ -z "$SSH_KEY" ]] || ssh_opts+=(-i "$SSH_KEY")
}
ssh_run() {
  local limit=0
  if [[ "${1:-}" == --probe ]]; then limit="$2"; shift 2; fi
  ssh_options
  local command=(ssh "${ssh_opts[@]}")
  if [[ "$AUTH_MODE" == keychain ]]; then
    command=(env "RCU_KEYCHAIN_SERVICE=${KEYCHAIN_SERVICE:-rcu.vm.$VM_UUID}" "RCU_KEYCHAIN_ACCOUNT=$SSH_USER"
      "SSH_ASKPASS=$RCU_ROOT/lib/ssh-askpass" SSH_ASKPASS_REQUIRE=force "DISPLAY=${DISPLAY:-rcu:0}"
      "${command[@]}" -o BatchMode=no -o NumberOfPasswordPrompts=1 -o "PreferredAuthentications=password,keyboard-interactive")
  else command+=(-o BatchMode=yes); fi
  if ((limit>0)); then bounded "$limit" "${command[@]}" "$@"; else "${command[@]}" "$@"; fi
}
ssh_probe() {
  local result
  result="$(ssh_run --probe "${SSH_PROBE_TIMEOUT:-8}" "$SSH_USER@$SSH_HOST" 'id -un' </dev/null)" || return 1
  [[ "$result" == "$SSH_USER" ]]
}
ssh_terminal() { ssh_run -tt "$SSH_USER@$SSH_HOST"; }
ensure_host_key() {
  local hosts scan fingerprints answer
  hosts="$(dirname "$CONF")/known_hosts"
  [[ ! -L "$(dirname "$CONF")" && -O "$(dirname "$CONF")" ]] || die 'Unsafe configuration directory.'
  [[ ! -L "$hosts" ]] || die 'Symlink known_hosts refused.'
  if [[ -f "$hosts" ]]; then
    [[ -O "$hosts" && -r "$hosts" && -w "$hosts" ]] || die 'Host-key file must be owned and readable/writable by current user.'
    chmod 600 "$hosts"
  fi
  if [[ -f "$hosts" ]] && ssh-keygen -F "rcu-$VM_UUID" -f "$hosts" >/dev/null; then return 0; fi
  [[ -t 0 && -t 1 ]] || die 'Host key not enrolled. Run rcu interactively and verify the displayed fingerprint against the VM.'
  scan="$(ssh-keyscan -T 4 -p "$SSH_PORT" "$SSH_HOST" 2>/dev/null)" || die 'Cannot retrieve SSH host key.'
  [[ -n "$scan" ]] || die 'No SSH host key received.'
  fingerprints="$(printf '%s\n' "$scan" | ssh-keygen -lf -)" || die 'Invalid SSH host key response.'
  ui_card 'SSH · Erstmalige Vertrauensprüfung' "$fingerprints"
  user_notice 'Fingerprints mit /etc/ssh/ssh_host_*_key.pub in der VM vergleichen. Nur bei Übereinstimmung yes eingeben.'
  IFS= read -r answer || die 'Host key enrollment cancelled.'
  [[ "$answer" == yes ]] || die 'Host key not trusted; nothing saved.'
  ( umask 077; printf '%s\n' "$scan" | awk -v alias="rcu-$VM_UUID" '!/^#/ && NF>=3 {print alias, $2, $3}' >> "$hosts" )
  chmod 600 "$hosts"
}
wait_for_ssh() {
  local begin=$SECONDS elapsed=0 state ips remaining
  WAIT_STATUS_LINES=0
  while ((elapsed<WAIT_SECONDS)); do
    remaining=$((WAIT_SECONDS-elapsed))
    state="$(UTM_QUERY_LIMIT="$remaining" utm_state 2>/dev/null || printf unknown)"
    if [[ "$state" == started ]]; then
      if [[ "$ADDRESS_MODE" == auto ]]; then
        if ips="$(discover_addresses "$remaining")" && [[ -n "$ips" ]]; then
          SSH_HOST="$(choose_address "$ips")" || return 1
        else SSH_HOST=''; fi
      fi
      if [[ -n "$SSH_HOST" ]]; then
        valid_host "$SSH_HOST" || die 'Invalid SSH address.'
        if bounded 2 nc -z -w 1 "$SSH_HOST" "$SSH_PORT" >/dev/null 2>&1; then
          ensure_host_key
          if [[ "$AUTH_MODE" == keychain && "${RCU_KEYCHAIN_NOTICE:-0}" != 1 ]]; then
            user_notice 'macOS-Keychain kann den Zugriff auf das VM-Passwort abfragen.'
            RCU_KEYCHAIN_NOTICE=1
          fi
          remaining=$((WAIT_SECONDS-(SECONDS-begin)))
          ((remaining>0)) || break
          if SSH_PROBE_TIMEOUT="$remaining" ssh_probe; then render_wait_status "$((SECONDS-begin))" "$state" authenticated; return 0; fi
          die 'SSH authentication or host-key verification failed. Run rcu setup for correct credentials. A publickey-only server needs an authorized key on the Mac; storing a password cannot enable server-side password login. Saved host keys are never replaced automatically.'
        fi
      fi
    fi
    elapsed=$((SECONDS-begin))
    render_wait_status "$elapsed" "$state" 'warte auf Netzwerk / SSH'
    ((elapsed<WAIT_SECONDS)) || break
    sleep 1
    elapsed=$((SECONDS-begin))
  done
  printf 'ERROR: SSH readiness timeout after %ss. No unambiguous reachable address. Check guest SSH/network, QEMU guest agent or DHCP; for forwarded ports use rcu setup --host HOST --port PORT.\n' "$((SECONDS-begin))" >&2
  return 1
}
show_help() {
  ui_card "RCU $(cat "$RCU_ROOT/VERSION") · Remote Control Unit" 'macOS → UTM → Gast-Terminal'
  printf '%s\n' \
    '  rcu                   VM starten und Terminal öffnen' \
    '  rcu setup             VM und Gast-Zugang einmalig einrichten' \
    '    --vm UUID --user NAME [--auth keychain|agent] [--key PATH]' \
    '    Standard: Benutzername und Passwort einmalig speichern und prüfen.' \
    '    [--host HOST --port PORT]  Expliziter Zugang, z.B. Portweiterleitung' \
    '  rcu utm status        Nur Status lesen; kein VM-Start / Setup / Login' \
    '  rcu utm start         Starten und SSH prüfen' \
    '  rcu utm connect       Laufende VM und SSH prüfen' \
    '  rcu utm shell         Gast-Terminal öffnen; exit lässt VM laufen' \
    '  rcu utm health        Authentifizierung prüfen' \
    '  rcu utm stop          Nur regulären Shutdown anfordern' \
    '  rcu upload SRC DEST   Datei/Ordner in den Gast kopieren' \
    '  rcu update DIR        Geprüftes Quellverzeichnis installieren' \
    '  rcu rollback          Vorherigen Release aktivieren' \
    '  rcu uninstall         Installation archivieren; Zugang behalten'
}
