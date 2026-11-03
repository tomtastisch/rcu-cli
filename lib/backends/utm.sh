#!/bin/bash
# VM lifecycle via utmctl, never force-stop.
utm_cmd() { "$UTMCTL" "$@"; }
utm_state() {
  utm_cmd list | awk -v uuid="$VM_UUID" -v name="$VM_NAME" '
  NR>1 {
    id=$1; state=$2
    $1=""; $2=""; sub(/^[[:space:]]+/, "", $0)
    if (id==uuid && $0==name) {print state; found=1; exit}
  }
  END {if (!found) exit 1}'
}
ensure_vm() { utm_state >/dev/null || die "VM not found (UUID $VM_UUID, Name $VM_NAME)"; }
utm_start() {
  check; phase 1 'UTM and SSH profile validated'; ensure_vm
  local state; state="$(utm_state)" || die 'Cannot read VM state'
  if [[ "$state" != started ]]; then
    [[ "$state" == stopped ]] || die "VM state is $state; cannot start safely"
    user_notice 'macOS-Host: Requesting UTM VM start; no action required.'
    spin 'Requesting VM start' utm_cmd start "$VM_UUID" || die 'UTM VM start failed.'
  fi
  phase 2 'VM start reported or already running'
  wait_for_ssh || die 'SSH readiness timeout.'
  phase 3 'Remote SSH user authenticated'
  [[ "$(utm_state)" == started ]] || die 'UTM does not report started.'
  phase 4 'VM started and SSH ready'
}
utm_connect() {
  check; phase 1 'Validated local profile'; ensure_vm
  [[ "$(utm_state)" == started ]] || die 'VM not running.'
  phase 2 'UTM reports started'
  wait_for_ssh || die 'SSH login not available.'
  phase 3 'Remote SSH identity authenticated'; phase 4 'Connection ready'
}
utm_shell() {
  check; ensure_vm
  [[ "$(utm_state)" == started ]] || die 'VM not running.'
  wait_for_ssh || die 'SSH unavailable.'
  user_notice 'macOS-Host: Opening Debian VM shell; type exit to return to macOS.'
  ssh_terminal
}
utm_stop() {
  check; ensure_vm
  local state; state="$(utm_state)" || die 'Cannot read VM state.'
  [[ "$state" == stopped ]] && { notice 'Already stopped.'; return 0; }
  [[ "$state" == started ]] || die "Unexpected VM state: $state"
  user_notice 'macOS-Host: Requesting graceful VM shutdown; do not force-close.'
  spin 'Requesting guest shutdown' utm_cmd stop --request "$VM_UUID" || die 'Graceful shutdown request failed; no forced fallback.'
  local n=0
  while ((n<WAIT_SECONDS)); do
    state="$(utm_state)" || die 'Cannot confirm shutdown.'
    [[ "$state" == stopped ]] && { notice 'UTM confirms VM stopped.'; return 0; }
    sleep 2; n=$((n+2))
  done
  die 'Shutdown not confirmed, VM was not forcibly stopped.'
}
utm_health() {
  check; ensure_vm
  notice "UTM_STATUS=$(utm_state)"
  [[ "$(utm_state)" == started ]] || die 'VM not running.'
  wait_for_ssh || die 'SSH authentication failed.'
  notice 'HEALTH=PASS (UTM + SSH only)'
}
utm_status() {
  check; notice "VM_NAME=$VM_NAME"; notice "VM_UUID=$VM_UUID"
  utm_cmd list
  printf 'SSH_TARGET=%s@%s:%s\n' "$SSH_USER" "$SSH_HOST" "$SSH_PORT"
  if ssh_probe; then notice 'SSH_AUTH=PASS'; else notice 'SSH_AUTH=UNAVAILABLE'; fi
}
