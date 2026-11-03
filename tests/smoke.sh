#!/bin/bash
set -euo pipefail
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/.ssh"
printf 'dummy\n' > "$tmp/.ssh/key"
printf 'started\n' > "$tmp/state"
cat > "$tmp/bin/utmctl" <<'MOCK'
#!/bin/bash
case "$1" in
 list) printf 'UUID Status Name\nA16B662F-A8E9-4615-B0E9-A16BA73BA7E7 %s Virtuelle Maschine\n' "$(cat "$TEST_STATE")" ;;
 start) printf 'started\n' > "$TEST_STATE" ;;
 stop) [[ "$2" == '--request' ]] || { echo 'not a graceful shutdown' >&2; exit 7; }; printf 'stopped\n' > "$TEST_STATE" ;;
 *) exit 8 ;;
esac
MOCK
cat > "$tmp/bin/ssh" <<'MOCK'
#!/bin/bash
[[ "${TEST_SSH_FAIL:-0}" == 0 ]] || exit 255
if [[ "${*: -1}" == 'id -un' ]]; then printf 'lars\n'; fi
exit 0
MOCK
chmod +x "$tmp/bin/utmctl" "$tmp/bin/ssh"
cat > "$tmp/config" <<EOF2
VM_NAME='Virtuelle Maschine'
UTMCTL='$tmp/bin/utmctl'
SSH_KEY='$tmp/.ssh/key'
SSH_HOST='192.168.64.2'
SSH_USER='lars'
WAIT_SECONDS=1
EOF2
export RCU_TEST=1 RCU_CONFIG="$tmp/config" TEST_STATE="$tmp/state" PATH="$tmp/bin:$PATH"
"$root/bin/rcu" help | grep -q 'rcu utm'
"$root/bin/rcu" utm status | grep -q 'SSH_AUTH=PASS'
"$root/bin/rcu" utm health | grep -q 'HEALTH=PASS'
"$root/bin/rcu" utm connect | grep -q '100% CHECKS'
"$root/bin/rcu" utm shell | grep -q 'USER: Opening Debian shell'
"$root/bin/rcu" utm stop | grep -q 'stopped'
[[ $(cat "$tmp/state") == stopped ]]
"$root/bin/rcu" utm start | grep -q '100% CHECKS'
[[ $(cat "$tmp/state") == started ]]
export TEST_SSH_FAIL=1
if "$root/bin/rcu" utm health >/dev/null 2>&1; then echo 'FAIL: SSH failure must fail'; exit 1; fi
if "$root/bin/rcu" utm connect >/dev/null 2>&1; then echo 'FAIL: connection failure must fail'; exit 1; fi
if "$root/bin/rcu" wrong >/dev/null 2>&1; then echo 'FAIL: bad provider must fail'; exit 1; fi
printf 'PASS: mock commands and failure paths\n'
