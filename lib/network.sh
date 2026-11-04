#!/bin/bash
# No subnet scans or guessed DHCP addresses. Bind discovery to the selected VM.
valid_host() {
  [[ "$1" =~ ^[a-zA-Z0-9][a-zA-Z0-9.:-]*$ && "$1" != *..* && ${#1} -le 253 ]]
}
filter_addresses() {
  # utmctl emits one address per line. Prefer IPv4 for Apple shared networking;
  # retain global IPv6 as well, but reject loopback, unspecified and link-local.
  awk 'function ipv4(s, a,n,i) { n=split(s,a,"."); if(n!=4)return 0; for(i=1;i<=4;i++)if(a[i]!~/^[0-9]+$/ || a[i]>255)return 0; return a[1]>0 && a[1]<224 && a[1]!=127 && !(a[1]==169 && a[2]==254) }
  {gsub(/^[ \t]+|[ \t\r]+$/, ""); s=tolower($0); if(ipv4(s) || (s ~ /^[0-9a-f:]+$/ && s ~ /:/ && s!="::" && s!="::1" && s!~/^fe[89ab]/ && s!~/^ff/)) print s}' | sort -u
}
vm_mac_addresses() {
  # UTM scripting configuration is read-only. UUID is passed as data via argv.
  bounded "${1:-3}" osascript - "$VM_UUID" <<'APPLESCRIPT'
on run argv
  tell application id "com.utmapp.UTM"
    set cfg to configuration of virtual machine id (item 1 of argv)
    set output to ""
    repeat with nic in (network interfaces of cfg)
      set output to output & (address of nic) & linefeed
    end repeat
    return output
  end tell
end run
APPLESCRIPT
}
dhcp_addresses() {
  local macs="$1" leases="${2:-/var/db/dhcpd_leases}"
  [[ -r "$leases" ]] || return 1
  # MACs are normalized because bootpd can omit leading zeroes.
  awk -v macs="$macs" -v now="$(date +%s)" '
  function norm(s, a,n,i,r) {n=split(tolower(s),a,":"); if(n!=6)return ""; r=""; for(i=1;i<=6;i++){sub(/^0+/,"",a[i]); if(a[i]=="")a[i]="0"; r=r (i>1?":":"") a[i]} return r}
  function number(s, i,n,c) {if(s!~/^0x/)return s+0; s=substr(s,3); n=0; for(i=1;i<=length(s);i++){c=index("0123456789abcdef",tolower(substr(s,i,1)))-1; if(c<0)return 0; n=n*16+c} return n}
  BEGIN {n=split(macs, m,"\n"); for(i=1;i<=n;i++) if(norm(m[i])!="") wanted[norm(m[i])]=1}
  /^\{/ {ip="";mac="";expiry=0}
  /ip_address=/ {ip=$0;sub(/.*ip_address=/,"",ip)}
  /hw_address=/ {mac=$0;sub(/.*hw_address=[^,]*,/,"",mac)}
  /lease=/ {v=$0;sub(/.*lease=/,"",v);expiry=number(v)}
  /^\}/ {if(wanted[norm(mac)] && expiry>now)print ip}' "$leases"
}
arp_addresses() {
  local macs="$1"
  bounded 2 arp -an 2>/dev/null | awk -v macs="$macs" '
  function norm(s, a,n,i,r) {n=split(tolower(s),a,":"); if(n!=6)return ""; r=""; for(i=1;i<=6;i++){sub(/^0+/,"",a[i]); if(a[i]=="")a[i]="0"; r=r (i>1?":":"") a[i]} return r}
  BEGIN {n=split(macs,m,"\n");for(i=1;i<=n;i++)if(norm(m[i])!="")wanted[norm(m[i])]=1}
  $3=="at" && wanted[norm($4)] {ip=$2;gsub(/[()]/,"",ip);print ip}'
}
discover_addresses() {
  local budget="${1:-6}" ips macs limit=3 begin=$SECONDS remaining
  ((budget>=1)) || { rcu_log "DISCOVER_ADDRESSES budget_too_low"; return 1; }
  ((budget>=limit)) || limit="$budget"
  rcu_log "DISCOVER_ADDRESSES_START budget=${budget}s utmctl=$UTMCTL uuid=$VM_UUID"
  ips="$(bounded "$limit" "$UTMCTL" ip-address "$VM_UUID" 2>/dev/null | filter_addresses)" || ips=''
  if [[ -n "$ips" ]]; then
    rcu_log "DISCOVER_UTMCTL_OK ips=$ips"
    printf '%s\n' "$ips"
    return 0
  fi
  rcu_log "DISCOVER_UTMCTL_NO_IP"
  remaining=$((budget-(SECONDS-begin)))
  ((remaining>=1)) || { rcu_log "DISCOVER_TIMEOUT no_fallback_time"; return 1; }
  ((remaining>=limit)) || limit="$remaining"
  macs="$(vm_mac_addresses "$limit" 2>/dev/null)" || macs=''
  if [[ -z "$macs" ]]; then
    rcu_log "DISCOVER_MAC_EMPTY"
  else
    rcu_log "DISCOVER_MAC macs=$macs"
  fi
  if [[ -n "$macs" ]]; then
    ips="$(dhcp_addresses "$macs" | filter_addresses)" || ips=''
    if [[ -n "$ips" ]]; then
      rcu_log "DISCOVER_DHCP_OK ips=$ips"
      printf '%s\n' "$ips"
      return 0
    fi
    rcu_log "DISCOVER_DHCP_NO_IP"
    if ((SECONDS-begin<budget)); then
      ips="$(arp_addresses "$macs" | filter_addresses)" || ips=''
      if [[ -n "$ips" ]]; then
        rcu_log "DISCOVER_ARP_OK ips=$ips"
        printf '%s\n' "$ips"
        return 0
      fi
      rcu_log "DISCOVER_ARP_NO_IP"
    fi
  fi
  rcu_log "DISCOVER_FAILED elapsed=$((SECONDS-begin))s budget=${budget}s"
  return 1
}
choose_address() { choose_line 'Mehrere VM-Adressen: SSH-Ziel auswählen' "$1"; }
