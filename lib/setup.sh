#!/bin/bash
# First-run onboarding. Persist identity, never an auto-discovered IP or VM name.
choose_line() {
  local title="$1" lines="$2" picked index=0 line count=0
  [[ -n "$lines" ]] || return 1
  if [[ "$(printf '%s\n' "$lines" | wc -l | tr -d ' ')" == 1 ]]; then printf '%s\n' "$lines"; return 0; fi
  [[ -t 0 && -t 2 ]] || { printf 'ERROR: %s: selection requires an interactive terminal.\n' "$title" >&2; return 1; }
  if [[ -t 0 && -t 2 ]] && command -v gum >/dev/null 2>&1; then printf '%s\n' "$lines" | gum choose --header "$title"; return $?; fi
  printf '%s\n' "$title" >&2
  while IFS= read -r line; do count=$((count+1)); printf '  %d) %s\n' "$count" "$line" >&2; done <<< "$lines"
  printf 'Auswahl: ' >&2; IFS= read -r picked || return 1
  [[ "$picked" =~ ^[0-9]{1,4}$ ]] || return 1
  index=$((10#$picked)); ((index>=1 && index<=count)) || return 1
  printf '%s\n' "$lines" | sed -n "${index}p"
}
prompt_value() {
  local title="$1" result
  [[ -t 0 && -t 2 ]] || die "Missing $title. Run rcu setup interactively or provide flags."
  if [[ -t 0 && -t 2 ]] && command -v gum >/dev/null 2>&1; then result="$(gum input --header "$title" --placeholder "$title")" || die 'Einrichtung abgebrochen.'
  else printf '%s: ' "$title" >&2; IFS= read -r result || die 'Einrichtung abgebrochen.'; fi
  [[ -n "$result" ]] || die "$title darf nicht leer sein."
  printf '%s' "$result"
}
save_profile() (
  umask 077
  local dir temp key value
  dir="$(dirname "$CONF")"
  [[ ! -L "$dir" && ! -L "$CONF" ]] || die 'Symlink configuration refused.'
  mkdir -p "$dir"
  [[ -O "$dir" ]] || die 'Configuration directory must be owned by current user.'
  temp="$(mktemp "$dir/.config.XXXXXX")"
  trap 'rm -f "$temp"' EXIT
  printf '# RCU host profile; passwords live in macOS Keychain.\nCONFIG_VERSION=1\n' > "$temp"
  for key in VM_UUID SSH_USER SSH_PORT SSH_KEY AUTH_MODE ADDRESS_MODE WAIT_SECONDS UTMCTL; do
    value="${!key}"
    [[ "$value" != *\'* && "$value" != *\"* && "$value" != *'$'* && "$value" != *'`'* && "$value" != *';'* && "$value" != *'\'* && "$value" != *[$'\001'-$'\037'$'\177']* ]] || die "Unsupported profile value: $key"
    printf "%s='%s'\n" "$key" "$value" >> "$temp"
  done
  if [[ "$ADDRESS_MODE" == manual ]]; then printf "SSH_HOST='%s'\n" "$SSH_HOST" >> "$temp"; fi
  chmod 600 "$temp"
  mv -f "$temp" "$CONF"
)
setup_profile() {
  local selected='' requested_vm='' requested_user='' requested_auth='' requested_key='' requested_host='' requested_port=22 records line mode
  find_utmctl
  while (($#)); do
    [[ $# -ge 2 ]] || die 'Every setup flag needs a value.'
    case "$1" in
      --vm) requested_vm="$2" ;;
      --user) requested_user="$2" ;;
      --auth) requested_auth="$2" ;;
      --key) requested_key="$2" ;;
      --host) requested_host="$2" ;;
      --port) requested_port="$2" ;;
      *) die "Unknown setup option: $1" ;;
    esac
    shift 2
  done
  user_notice 'UTM-VMs werden gelesen. macOS kann eine Automation-Berechtigung für UTM abfragen.'
  records="$(vm_records)" || die 'UTM VM list unavailable.'
  [[ -n "$records" ]] || die 'No UTM VMs registered. Open UTM and register your existing VM.'
  if [[ -n "$requested_vm" ]]; then
    valid_uuid "$requested_vm" || die 'Invalid --vm UUID.'
    selected="$(printf '%s\n' "$records" | awk -v id="$requested_vm" 'tolower($1)==tolower(id)')"
    [[ -n "$selected" ]] || die 'Requested VM is not registered.'
  else selected="$(choose_line 'UTM-VM auswählen' "$records")" || die 'VM selection cancelled; no profile changed.'; fi
  VM_UUID="${selected%% *}"
  SSH_USER="$requested_user"
  [[ -n "$SSH_USER" ]] || SSH_USER="$(prompt_value 'Benutzername innerhalb der VM')"
  SSH_KEY="$requested_key"; SSH_PORT="$requested_port"; SSH_HOST="$requested_host"
  ADDRESS_MODE=auto; [[ -z "$SSH_HOST" ]] || ADDRESS_MODE=manual
  AUTH_MODE="$requested_auth"
  if [[ -z "$AUTH_MODE" ]]; then
    mode="$(choose_line 'SSH-Anmeldung auswählen' $'Passwort · macOS-Keychain\nSSH-Agent / vorhandener Schlüssel')" || die 'Authentication selection cancelled.'
    case "$mode" in Passwort*) AUTH_MODE=keychain ;; *) AUTH_MODE=agent ;; esac
  fi
  LEGACY_SECRET=0
  check
  [[ "$ADDRESS_MODE" != manual ]] || valid_host "$SSH_HOST" || die 'Invalid --host.'
  if [[ "$AUTH_MODE" == keychain ]]; then
    [[ -t 0 && -t 2 ]] || die 'Password enrollment requires an interactive macOS terminal; no password flags accepted.'
    user_notice 'VM-Passwort jetzt verdeckt im nativen Keychain-Prompt eingeben. macOS kann eine Keychain-Berechtigung abfragen.'
    # -w MUST be last without an argument: security reads and confirms securely.
    # No password in shell variables, environment, process arguments or files.
    security_cmd add-generic-password -U -a "$SSH_USER" -s "rcu.vm.$VM_UUID" -w || die 'Keychain enrollment failed; profile not saved.'
  fi
  save_profile
  CONFIG_VERSION=1
  ui_card 'RCU · Einrichtung gespeichert' "VM: ${selected#* }"$'\n'"Benutzer: $SSH_USER · Anmeldung: $AUTH_MODE · Netzwerk: $ADDRESS_MODE"
}
