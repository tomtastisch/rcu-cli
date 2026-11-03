#!/bin/bash
# Cross-machine behavior: no inherited developer environment or real VM changes.
set -euo pipefail
src="$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd -P)"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
export HOME="$tmp/home" XDG_CONFIG_HOME="$tmp/home/.config" RCU_CONFIG="$tmp/home/.config/rcu/config" RCU_TEST=1
mkdir -p "$HOME" "$tmp/mock" "$(dirname "$RCU_CONFIG")"
export TEST_LOG="$tmp/log" TEST_STATE="$tmp/state" TEST_IP="$tmp/ip" TEST_LIST="$tmp/list"
uuid=12345678-1234-4567-8910-123456789ABC
printf 'started\n' > "$TEST_STATE"; printf '10.42.7.19\n' > "$TEST_IP"
printf 'UUID Status Name\n%s started Debian Other Mac\n' "$uuid" > "$TEST_LIST"
cat > "$tmp/mock/utmctl" <<'MOCK'
#!/bin/bash
printf '%s\n' "$*" >> "$TEST_LOG"
case "$1" in
list) awk -v state="$(cat "$TEST_STATE")" 'NR==2 {$2=state} {print}' "$TEST_LIST" ;;
status) cat "$TEST_STATE" ;;
ip-address) cat "$TEST_IP" ;;
start) printf 'started\n' > "$TEST_STATE" ;;
stop) [[ "$2" == --request ]] || exit 90; printf 'stopped\n' > "$TEST_STATE" ;;
esac
MOCK
cat > "$tmp/mock/ssh" <<'MOCK'
#!/bin/bash
printf 'ssh %s\n' "$*" >> "$TEST_LOG"
[[ "${TEST_AUTH_FAIL:-0}" == 0 ]] || exit 255
for arg in "$@"; do [[ "$arg" != 'id -un' ]] || printf '%s\n' "${TEST_USER:-alex}"; done
exit "${TEST_SHELL_EXIT:-0}"
MOCK
cat > "$tmp/mock/nc" <<'MOCK'
#!/bin/bash
exit 0
MOCK
cat > "$tmp/mock/ssh-keygen" <<'MOCK'
#!/bin/bash
exit 0
MOCK
printf 'pinned-test-key\n' > "$(dirname "$RCU_CONFIG")/known_hosts"
chmod +x "$tmp/mock/"*
export PATH="$tmp/mock:$PATH" RCU_UTMCTL_PATH="$tmp/mock/utmctl"
PASS=0; FAIL=0
expect() { local label="$1"; shift; if "$@" > "$tmp/out" 2>&1; then PASS=$((PASS+1)); printf 'PASS %s\n' "$label"; else FAIL=$((FAIL+1)); printf 'FAIL %s\n' "$label"; cat "$tmp/out"; fi; }
reject() { if "$@"; then return 1; else return 0; fi; }
config() {
cat > "$RCU_CONFIG" <<EOF
CONFIG_VERSION=1
VM_UUID='$uuid'
SSH_USER='alex'
AUTH_MODE=agent
WAIT_SECONDS=2
UTMCTL='$tmp/mock/utmctl'
EOF
chmod 600 "$RCU_CONFIG"
}
config
expect 'keyless health on another machine' bash "$src/bin/rcu" utm health
expect 'dynamic IP used' grep -q 'alex@10.42.7.19' "$TEST_LOG"
printf '10.42.9.81\n' > "$TEST_IP"
expect 'DHCP changes discovered again' bash "$src/bin/rcu" utm health
expect 'new IP used' grep -q 'alex@10.42.9.81' "$TEST_LOG"
expect 'renamed VM identified by UUID only' bash "$src/bin/rcu" utm connect
expect 'status requires no credentials or setup' env RCU_CONFIG="$tmp/missing" bash "$src/bin/rcu" utm status
expect 'no configuration silently invented' test ! -e "$tmp/missing"
: > "$TEST_LOG"
expect 'status succeeds' bash "$src/bin/rcu" utm status
expect 'status does not start guest' reject grep -q '^start ' "$TEST_LOG"
printf 'stopped\n' > "$TEST_STATE"
expect 'direct entry starts and connects' bash "$src/bin/rcu"
expect 'exit leaves VM running' grep -qx started "$TEST_STATE"
expect 'only one start' test "$(grep -c '^start ' "$TEST_LOG")" = 1
expect 'repeat entry does not restart' bash "$src/bin/rcu"
expect 'still only one start' test "$(grep -c '^start ' "$TEST_LOG")" = 1
# Unknown UUID in a configured profile must never select another VM.
printf "VM_UUID='00000000-0000-0000-0000-000000000000'\n" >> "$RCU_CONFIG"
expect 'stale UUID fails closed' reject bash "$src/bin/rcu"
config
printf '127.0.0.1\n169.254.5.4\n::1\nfe80::a\n' > "$TEST_IP"
expect 'guest loopback and link-local IPs rejected' reject bash "$src/bin/rcu" utm connect
printf '10.1.1.2\n10.1.1.3\n' > "$TEST_IP"
expect 'ambiguous addresses fail noninteractively' reject bash "$src/bin/rcu" utm connect
printf '10.1.1.2\n' > "$TEST_IP"
expect 'authentication failure propagated' reject env TEST_AUTH_FAIL=1 bash "$src/bin/rcu" utm connect
expect 'shell exit propagated' reject env TEST_SHELL_EXIT=7 bash "$src/bin/rcu" utm shell
expect 'empty noninteractive setup fails' reject env RCU_CONFIG="$tmp/empty" bash "$src/bin/rcu"
expect 'explicit setup supports another user' bash "$src/bin/rcu" setup --vm "$uuid" --user guest --auth agent
expect 'setup persisted user' grep -q "SSH_USER='guest'" "$RCU_CONFIG"
expect 'configuration mode is private' test "$(stat -c '%a' "$RCU_CONFIG" 2>/dev/null || stat -f '%Lp' "$RCU_CONFIG")" = 600
expect 'no IP persisted by auto setup' reject grep -q 'SSH_HOST=' "$RCU_CONFIG"
expect 'no VM name persisted' reject grep -q 'VM_NAME=' "$RCU_CONFIG"
expect 'unknown setup flags rejected' reject bash "$src/bin/rcu" setup --password unsafe
expect 'single VM setup selects automatically' env RCU_CONFIG="$tmp/empty" bash "$src/bin/rcu" setup --user guest --auth agent
# Above single-VM case should work; make multiple-VM case explicit below.
config
printf '%s\n' '87654321-1234-4567-8910-123456789ABC started A second VM' >> "$TEST_LIST"
expect 'multiple VMs require selection' reject env RCU_CONFIG="$tmp/empty2" bash "$src/bin/rcu" setup --user guest --auth agent
config
printf "SSH_PASSWORD='do-not-load-this'\n" >> "$RCU_CONFIG"
expect 'legacy plaintext password not used' reject bash "$src/bin/rcu" utm health
expect 'help remains available for recovery' bash "$src/bin/rcu" help
printf 'RESULT: %d PASS, %d FAIL\n' "$PASS" "$FAIL"
[[ "$FAIL" == 0 ]]
