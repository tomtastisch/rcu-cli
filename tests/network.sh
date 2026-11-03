#!/bin/bash
# Parser, deadline and safe discovery boundary tests with captured fixture data.
set -euo pipefail
src="$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd -P)"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
export RCU_CONFIG="$tmp/missing" RCU_TEST=1 RCU_ROOT="$src"
source "$src/lib/core.sh"
source "$src/lib/network.sh"
printf '10.4.5.6\n127.0.0.1\n169.254.1.2\n0.0.0.0\n999.1.2.3\n224.1.2.3\n::1\n::\nfe80::1\nff02::1\n2001:db8::1\n10.4.5.6\n' | filter_addresses > "$tmp/ips"
printf '10.4.5.6\n2001:db8::1\n' > "$tmp/expected"
cmp "$tmp/ips" "$tmp/expected"
printf 'PASS IP filtering and deduplication\n'
cat > "$tmp/leases" <<'LEASES'
{
ip_address=10.5.6.7
hw_address=1,a:b:c:d:e:f
lease=0xffffffff
}
{
ip_address=10.5.6.8
hw_address=1,aa:bb:cc:dd:ee:ff
lease=0xffffffff
}
{
ip_address=10.5.6.9
hw_address=1,0a:0b:0c:0d:0e:0f
lease=0x1
}
LEASES
actual="$(dhcp_addresses '0a:0b:0c:0d:0e:0f' "$tmp/leases")"
[[ "$actual" == 10.5.6.7 ]]
printf 'PASS DHCP: only selected NIC, normalized MAC, expired leases excluded\n'
cat > "$tmp/hang" <<'HANG'
#!/bin/bash
exec sleep 30
HANG
chmod +x "$tmp/hang"
begin=$SECONDS
if bounded 1 "$tmp/hang"; then exit 1; else [[ $? == 124 ]]; fi
((SECONDS-begin<=2))
printf 'PASS unresponsive guest-agent deadline\n'
if bounded 2 /bin/bash -c 'exit 17'; then exit 1; else [[ $? == 17 ]]; fi
printf 'PASS bounded command preserves failure exit status\n'
failed=0
actual="$(bounded 2 cat <<'INPUT'
selected-vm-mac
INPUT
)"
if [[ "$actual" == selected-vm-mac ]]; then printf 'PASS bounded preserves script stdin\n'
else printf 'FAIL bounded discards script stdin\n'; failed=1; fi
begin=$SECONDS
if actual="$(bounded 1 /bin/bash -c 'sleep 4; printf late')"; then
  printf 'FAIL child-process timeout unexpectedly succeeded\n'; failed=1
else
  result=$?
  if [[ "$result" == 124 && -z "$actual" ]] && ((SECONDS-begin<=2)); then
    printf 'PASS timeout closes descendant stdout promptly\n'
  else printf 'FAIL timeout leaked descendant: status=%s elapsed=%ss\n' "$result" "$((SECONDS-begin))"; failed=1; fi
fi
begin=$SECONDS
actual="$(bounded 2 /bin/bash -c 'sleep 4 & printf done')"
if [[ "$actual" == 'done' ]] && ((SECONDS-begin<=2)); then
  printf 'PASS completed worker leaves no stdout-holding descendant\n'
else printf 'FAIL completed worker leaked descendant stdout\n'; failed=1; fi
# Exercise real readiness arithmetic with a valid, decimal-leading-zero profile.
find_utmctl() { UTMCTL=/bin/true; }
utm_state() { printf 'started\n'; }
ensure_host_key() { :; }
ssh_probe() { :; }
choose_address() { printf '%s\n' "$1"; }
mkdir "$tmp/mock"
printf '#!/bin/bash\nexit 0\n' > "$tmp/mock/nc"; chmod +x "$tmp/mock/nc"
export PATH="$tmp/mock:$PATH"
VM_UUID=12345678-1234-4567-8910-123456789ABC
SSH_USER=guest; SSH_HOST=10.5.6.7; ADDRESS_MODE=manual; WAIT_SECONDS=08
check
if wait_for_ssh > "$tmp/readiness" 2>&1; then printf 'PASS decimal-leading-zero wait reaches SSH readiness\n'
else printf 'FAIL decimal-leading-zero wait rejected after validation\n'; cat "$tmp/readiness"; failed=1; fi
[[ "$failed" == 0 ]]
