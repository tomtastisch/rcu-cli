#!/bin/bash
# UTM backend; VM selected by name to support migration between Macs.
utm_cmd() { "$UTMCTL" "$@"; }
utm_state() { utm_cmd list | awk -v name="$VM_NAME" 'NR>1 {line=$0; sub(/^[^ ]+[[:space:]]+/, "", line); state=line; sub(/[[:space:]].*$/, "", state); sub(/^[^[:space:]]+[[:space:]]+/, "", line); if(line==name){print state; found=1; exit}} END {if(!found)exit 1}'; }
ensure_vm() { utm_state >/dev/null || die "VM '$VM_NAME' not present in UTM list"; }
utm_start() {
  check; phase 1 'UTM and SSH profile validated'; ensure_vm
  local state; state=$(utm_state) || die 'Cannot read VM state'
  if [[ "$state" != started ]]; then
    [[ "$state" == stopped ]] || die "VM currently in '$state'; cannot safely start"
    notice 'USER: UTM VM will be started; no manual action required.'
    spin 'Requesting VM start' utm_cmd start "$VM_NAME" || die 'UTM start failed'
  fi
  phase 2 'UTM reports VM started or start requested'
  spin 'Checking SSH readiness' wait_probe || die 'Timed out waiting for authenticated SSH; VM may still be booting'
  phase 3 'Remote SSH identity authenticated'
  [[ "$(utm_state)" == started ]] || die 'UTM does not report started'
  phase 4 'VM state and SSH ready'
}
utm_connect() { check; phase 1 'Tools and profile'; ensure_vm; [[ "$(utm_state)" == started ]] || die 'VM not started'; phase 2 'UTM running'; spin 'Checking SSH connection' wait_probe || die 'SSH login unavailable'; phase 3 'SSH authenticated'; phase 4 'Connection verified'; }
utm_shell() { check; ensure_vm; [[ "$(utm_state)" == started ]] || die 'VM not started'; spin 'Checking SSH authentication' wait_probe || die 'SSH unavailable'; notice 'USER: Opening Debian shell; type exit to return to macOS.'; ssh_terminal; }
utm_stop() {
  check; ensure_vm
  local state; state=$(utm_state)
  [[ "$state" == stopped ]] && { notice 'Already stopped'; return 0; }
  [[ "$state" == started ]] || die "Unexpected VM state: $state"
  notice 'USER: Requesting graceful VM shutdown. Do not force-close the VM.'
  spin 'Requesting guest shutdown' utm_cmd stop --request "$VM_NAME" || die 'UTM graceful stop request failed'
  local t=0
  while ((t<WAIT_SECONDS)); do
    state=$(utm_state) || die 'Cannot verify shutdown'
    [[ "$state" == stopped ]] && { notice 'UTM confirms VM stopped'; return 0; }
    sleep 2; t=$((t+2))
  done
  die 'Shutdown not confirmed; VM was not forcibly stopped'
}
utm_status() {
  check; notice "VM: $VM_NAME"; utm_cmd list
  printf 'SSH target: %s@%s:%s\nKey: %s\n' "$SSH_USER" "$SSH_HOST" "$SSH_PORT" "$SSH_KEY"
  if ssh_probe; then notice 'SSH_AUTH=PASS'; else notice 'SSH_AUTH=UNAVAILABLE'; fi
}
utm_health() {
  check; ensure_vm; notice "UTM_STATUS=$(utm_state)"
  [[ "$(utm_state)" == started ]] || die 'VM not running'
  spin 'Checking remote SSH identity' ssh_probe || die 'SSH auth or network check failed'
  notice 'SSH_AUTH=PASS'; notice 'HEALTH=PASS (UTM + SSH only; guest agent separate)'
}
