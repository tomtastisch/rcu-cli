#!/bin/bash
# UUID is identity. Display names are always read from the current UTM inventory.
utm_cmd() { "$UTMCTL" "$@"; }
vm_records() {
  local records
  records="$(bounded "${UTM_QUERY_LIMIT:-10}" "$UTMCTL" list)" || return 1
  printf '%s\n' "$records" | LC_ALL=C tr -d '\000-\010\013-\037\177' | awk 'NR>1 && NF>=3 && length($1)==36 && $1~/^[[:xdigit:]-]+$/ {print}'
}
utm_state() {
  local records
  records="$(vm_records)" || return 1
  printf '%s\n' "$records" | awk -v uuid="$VM_UUID" 'tolower($1)==tolower(uuid) {print $2; found=1; exit} END {if(!found)exit 1}'
}
ensure_vm() {
  local records selected
  records="$(vm_records)" || die 'UTM inventory unavailable.'
  selected="$(printf '%s\n' "$records" | awk -v uuid="$VM_UUID" 'tolower($1)==tolower(uuid) {print; exit}')"
  [[ -n "$selected" ]] || die 'Saved VM UUID no longer registered. Run rcu setup; no other VM will be started.'
  VM_NAME="$(printf '%s\n' "$selected" | awk '{$1="";$2="";sub(/^[[:space:]]+/,"");print}')"
}
utm_start() {
  prepare_profile
  ui_card 'RCU · Verbindung herstellen' "$VM_NAME"
  phase 1 'VM und Zugang geprüft'
  local state; state="$(utm_state)" || die 'Cannot read VM state.'
  rcu_log "VM_STATE state=$state vm=$VM_NAME"
  case "$state" in
    started|starting|resuming) ;;
    stopped)
      rcu_log "VM_START_REQUESTED vm=$VM_NAME"
      user_notice 'UTM-VM wird gestartet. Keine weitere Anwendung erforderlich.'
      spin 'VM starten' bounded 15 "$UTMCTL" start "$VM_UUID" || die 'UTM VM start failed.'
      rcu_log "VM_STARTED vm=$VM_NAME" ;;
    *) die "VM state is $state; cannot start safely." ;;
  esac
  phase 2 'Warte auf VM-Netzwerk und SSH'
  wait_for_ssh || die 'SSH readiness failed.'
  phase 3 'SSH-Benutzer authentifiziert'
  phase 4 'Verbindung bereit'
  rcu_log "UTM_START_COMPLETE vm=$VM_NAME host=$SSH_HOST"
}
utm_connect() {
  prepare_profile
  local state; state="$(utm_state)" || die 'VM not running.'
  rcu_log "UTM_CONNECT state=$state vm=$VM_NAME"
  [[ "$state" == started ]] || die 'VM not running.'
  wait_for_ssh || die 'SSH login not available.'
}
utm_shell() {
  utm_connect
  user_notice 'Gast-Terminal wird geöffnet. exit kehrt zu macOS zurück; die VM bleibt an.'
  ssh_terminal
}
utm_stop() {
  # Stopping requires an existing profile, never a first-run wizard.
  [[ "$CONFIG_VERSION" == 1 ]] || die 'No configured VM. Run rcu setup first.'
  _rcu_log_init
  rcu_log "UTM_STOP_REQUEST vm=$VM_UUID"
  find_utmctl; valid_uuid "$VM_UUID" || die 'Invalid VM UUID.'; ensure_vm
  local state; state="$(utm_state)" || die 'Cannot read VM state.'
  rcu_log "VM_STATE state=$state vm=$VM_NAME"
  [[ "$state" != stopped ]] || { notice 'Already stopped.'; rcu_log "VM_ALREADY_STOPPED"; return 0; }
  [[ "$state" == started ]] || die "Unexpected VM state: $state"
  [[ "$WAIT_SECONDS" =~ ^[0-9]{1,4}$ ]] && ((10#$WAIT_SECONDS>=1 && 10#$WAIT_SECONDS<=3600)) || die 'Invalid WAIT_SECONDS.'
  WAIT_SECONDS=$((10#$WAIT_SECONDS))
  user_notice 'Regulärer VM-Shutdown wird angefordert. Kein Force-Stop-Fallback.'
  bounded 15 "$UTMCTL" stop --request "$VM_UUID" || die 'Graceful shutdown request failed; no forced fallback.'
  rcu_log "VM_STOP_REQUESTED"
  local begin=$SECONDS
  while ((SECONDS-begin<WAIT_SECONDS)); do
    state="$(utm_state)" || die 'Cannot confirm shutdown.'
    [[ "$state" != stopped ]] || { notice 'UTM confirms VM stopped.'; rcu_log "VM_STOPPED elapsed=$((SECONDS-begin))s"; return 0; }
    sleep 1
  done
  die 'Shutdown not confirmed; VM was not forcibly stopped.'
}
utm_health() { utm_connect; notice 'HEALTH=PASS (UTM + SSH authentication)'; }
utm_status() {
  find_utmctl
  local records
  records="$(vm_records)" || die 'UTM inventory unavailable.'
  ui_card 'RCU · UTM-Status' "${records:-Keine registrierten VMs}"
  if [[ -n "$VM_UUID" ]]; then notice "Selected UUID: $VM_UUID"; else notice 'Noch keine VM ausgewählt; rcu startet die Ersteinrichtung.'; fi
}
upload() {
  [[ $# == 2 && -e "$1" && "$2" != -* && "$2" != *[$'\001'-$'\037'$'\177']* ]] || die 'Usage: rcu upload <local-file-or-directory> <guest-path>'
  local src="$1" destination="$2"; src="$(CDPATH='' cd -- "$(dirname "$src")" && pwd -P)/$(basename "$src")"
  rcu_log "UPLOAD_START src=$src dest=$destination"
  utm_start
  local ssh_opts=()
  ssh_options
  # SCP uses uppercase -P; SFTP transport avoids remote-shell path interpolation.
  local scp_opts=(-s -P "$SSH_PORT" "${ssh_opts[@]:2}")
  [[ ! -d "$src" ]] || scp_opts+=(-r)
  local target="$SSH_HOST"; [[ "$target" != *:* ]] || target="[$target]"
  if [[ "$AUTH_MODE" == keychain ]]; then
    RCU_KEYCHAIN_SERVICE="${KEYCHAIN_SERVICE:-rcu.vm.$VM_UUID}" RCU_KEYCHAIN_ACCOUNT="$SSH_USER" \
      SSH_ASKPASS="$RCU_ROOT/lib/ssh-askpass" SSH_ASKPASS_REQUIRE=force DISPLAY="${DISPLAY:-rcu:0}" \
      scp "${scp_opts[@]}" -o BatchMode=no -o NumberOfPasswordPrompts=1 -o PreferredAuthentications=password,keyboard-interactive -- "$src" "$SSH_USER@$target:$destination"
  else scp "${scp_opts[@]}" -o BatchMode=yes -- "$src" "$SSH_USER@$target:$destination"; fi
  rcu_log "UPLOAD_COMPLETE src=$src dest=$destination"
}
