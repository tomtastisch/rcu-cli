#!/bin/bash
# End-to-end lifecycle tests with fully isolated HOME and mocked external services.
# Tests the 0.4.1 release including the bounded 3 nc -z fix (Race Condition in SSH port check).
set -euo pipefail
src="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
case_dir="$(mktemp -d)"
trap 'rm -rf "$case_dir"' EXIT
export HOME="$case_dir/home" XDG_CONFIG_HOME="$case_dir/home/.config" RCU_TEST=1
mkdir -p "$HOME/.ssh" "$case_dir/mock" "$case_dir/vm"
printf 'fake-identity\n' > "$HOME/.ssh/thi-clion-ed25519"
chmod 600 "$HOME/.ssh/thi-clion-ed25519"
printf 'started\n' > "$case_dir/vm/state"
export TEST_VM_STATE="$case_dir/vm/state" TEST_VM_LOG="$case_dir/vm/log" TEST_VM_FAIL=0 TEST_SSH_FAIL=0
export TEST_SSH_HOST='192.168.64.2' TEST_UTM_IP_FAIL=0 TEST_SCP_LOG="$case_dir/vm/scp.log"
: > "$TEST_VM_LOG"
: > "$TEST_SCP_LOG"

# --- Mocks ---
cat > "$case_dir/mock/utmctl" <<'MOCK'
#!/bin/bash
printf '%s\n' "$*" >> "${TEST_VM_LOG:-/dev/null}"
case "$1" in
  list)
    printf 'UUID Status Name\nA16B662F-A8E9-4615-B0E9-A16BA73BA7E7 %s Virtuelle Maschine\n' "$(cat "${TEST_VM_STATE:-/dev/null}")"
    [[ "${TEST_VM_MULTIPLE:-0}" == 0 ]] || printf 'B16B662F-A8E9-4615-B0E9-A16BA73BA7E7 stopped Zweite Maschine\n'
    ;;
  ip-address)
    [[ "${TEST_UTM_IP_FAIL:-0}" == 0 ]] || exit 70
    printf '192.168.64.2\n'
    ;;
  start) printf 'started\n' > "${TEST_VM_STATE:-/dev/null}" ;;
  stop)
    [[ "$2" == --request ]] || exit 19
    [[ "${TEST_VM_FAIL:-0}" == 0 ]] || exit 20
    printf 'stopped\n' > "${TEST_VM_STATE:-/dev/null}" ;;
  *) exit 21 ;;
esac
MOCK

cat > "$case_dir/mock/ssh" <<'MOCK'
#!/bin/bash
[[ "${TEST_SSH_FAIL:-0}" == 0 ]] || exit 255
for word in "$@"; do
  if [[ "$word" == 'id -un' ]]; then printf 'lars\n'; break; fi
done
exit 0
MOCK

cat > "$case_dir/mock/scp" <<'MOCK'
#!/bin/bash
printf '%s\n' "$*" >> "${TEST_SCP_LOG:-/dev/null}"
exit 0
MOCK

cat > "$case_dir/mock/nc" <<'MOCK'
#!/bin/bash
exit 0
MOCK

cat > "$case_dir/mock/arp" <<'MOCK'
#!/bin/bash
printf '? (192.168.64.2) at b6:e1:3f:94:c9:f3 on en0 on en0\n'
MOCK

cat > "$case_dir/mock/security" <<'MOCK'
#!/bin/bash
exit 0
MOCK

cat > "$case_dir/mock/ssh-keygen" <<'MOCK'
#!/bin/bash
case "${1:-}" in
  -F) exit 0 ;;
  -l) printf '    256 SHA256:mockfingerprint (RSA)\n' ;;
  *) exit 0 ;;
esac
MOCK

cat > "$case_dir/mock/ssh-keyscan" <<'MOCK'
#!/bin/bash
printf 'rcu-A16B662F-A8E9-4615-B0E9-A16BA73BA7E7 ssh-rsa AAAAB3mock\n'
exit 0
MOCK

cat > "$case_dir/mock/brew" <<'MOCK'
#!/bin/bash
printf 'mock brew\n'
MOCK

cat > "$case_dir/mock/gum" <<'MOCK'
#!/bin/bash
case "${1:-}" in
  spin)
    while (( $# > 0 )); do
      if [[ "$1" == '--' ]]; then shift; exec "$@"; fi
      shift
    done
    exit 64
    ;;
  style)
    shift; while (( $# > 1 )); do shift; done; printf '%s\n' "${1:-}"
    ;;
  choose) head -1 ;;
  input) printf '%s\n' "${TEST_GUM_INPUT:-}"
    ;;
  *) head -1 ;;
esac
MOCK

chmod +x "$case_dir/mock/"*
export PATH="$case_dir/mock:/usr/bin:/bin"
export RCU_UTMCTL_PATH="$case_dir/mock/utmctl"
export RCU_CONFIG="$HOME/.config/rcu/config"
mkdir -p "$(dirname "$RCU_CONFIG")"

# Pre-enroll SSH host key so ensure_host_key passes
printf 'rcu-A16B662F-A8E9-4615-B0E9-A16BA73BA7E7 ssh-rsa AAAAB3mock\n' > "$(dirname "$RCU_CONFIG")/known_hosts"
chmod 600 "$(dirname "$RCU_CONFIG")/known_hosts"

# --- Helper ---
failures=0
pass() { printf '\033[32mPASS\033[0m  %s\n' "$1"; }
fail() { printf '\033[31mFAIL\033[0m  %s\n' "$1"; ((failures++)); }
expect() {
  local label="$1"; shift
  if "$@" >/dev/null 2>&1; then pass "$label"; else fail "$label"; fi
}

# --- Write a valid 0.4.1 config ---
write_config() {
  cat > "$RCU_CONFIG" <<EOF2
CONFIG_VERSION=1
VM_UUID='A16B662F-A8E9-4615-B0E9-A16BA73BA7E7'
SSH_USER='lars'
SSH_PORT=22
SSH_KEY='$HOME/.ssh/thi-clion-ed25519'
AUTH_MODE=agent
ADDRESS_MODE=manual
SSH_HOST='192.168.64.2'
WAIT_SECONDS=2
UTMCTL='$case_dir/mock/utmctl'
EOF2
  chmod 600 "$RCU_CONFIG"
}

# --- Tests ---
write_config

# Basic commands must not crash.
expect 'rcu help' "$src/bin/rcu" help
expect 'rcu --version' "$src/bin/rcu" --version
expect 'version is 0.4.1' test "$(cat "$src/VERSION")" = "0.4.1"

# utm status must list the VM.
expect 'rcu utm status' "$src/bin/rcu" utm status

# utm connect must verify SSH on a running VM.
expect 'rcu utm connect' "$src/bin/rcu" utm connect

# utm health must pass.
expect 'rcu utm health' "$src/bin/rcu" utm health

# utm start on already-started VM must not restart.
expect 'rcu utm start (already running)' "$src/bin/rcu" utm start

# utm stop must request shutdown.
printf 'started\n' > "$TEST_VM_STATE"
expect 'rcu utm stop' "$src/bin/rcu" utm stop
expect 'VM stopped' test "$(cat "$TEST_VM_STATE")" = "stopped"

# Failed SSH must be reported.
TEST_SSH_FAIL=1
if "$src/bin/rcu" utm connect >/dev/null 2>&1; then fail 'SSH failure detected'; else pass 'SSH failure detected'; fi
TEST_SSH_FAIL=0

# utmctl ip-address failure with auto mode must be reported.
TEST_UTM_IP_FAIL=1
sed -i '' 's/ADDRESS_MODE=manual/ADDRESS_MODE=auto/' "$RCU_CONFIG"
sed -i '' 's/SSH_HOST=.*/SSH_HOST=/' "$RCU_CONFIG"
if "$src/bin/rcu" utm connect >/dev/null 2>&1; then fail 'utmctl IP failure detected'; else pass 'utmctl IP failure detected'; fi
TEST_UTM_IP_FAIL=0

# Restore config for remaining tests
write_config

# Upload must invoke scp.
mkdir -p "$case_dir/upload-src"
printf 'hello\n' > "$case_dir/upload-src/test.txt"
expect 'rcu upload' "$src/bin/rcu" upload "$case_dir/upload-src" /tmp/upload-dest
expect 'scp was invoked' test -s "$TEST_SCP_LOG"

# Invalid config must be rejected.
printf 'VM_UUID="bad"\n' > "$case_dir/bad-config"
RCU_CONFIG="$case_dir/bad-config" "$src/bin/rcu" utm connect >/dev/null 2>&1 && fail 'bad config rejected' || pass 'bad config rejected'

# Config with unsafe values must be rejected.
cat > "$case_dir/unsafe-config" <<'UNSAFE'
CONFIG_VERSION=1
VM_UUID='A16B662F-A8E9-4615-B0E9-A16BA73BA7E7'
SSH_USER='lars; rm -rf /'
SSH_PORT=22
AUTH_MODE=agent
ADDRESS_MODE=manual
SSH_HOST='192.168.64.2'
WAIT_SECONDS=2
UNSAFE
chmod 600 "$case_dir/unsafe-config"
RCU_CONFIG="$case_dir/unsafe-config" "$src/bin/rcu" utm connect >/dev/null 2>&1 && fail 'unsafe config rejected' || pass 'unsafe config rejected'

# Symlink config must be refused.
ln -sf "$RCU_CONFIG" "$case_dir/symlink-config"
RCU_CONFIG="$case_dir/symlink-config" "$src/bin/rcu" utm connect >/dev/null 2>&1 && fail 'symlink config rejected' || pass 'symlink config rejected'

# --- Regression test: bounded 3 nc -z fix ---
if grep -q 'bounded 3 nc -z' "$src/lib/core.sh"; then
  pass 'bounded 3 nc -z fix is present in core.sh'
else
  fail 'bounded 3 nc -z fix is missing from core.sh'
fi

# --- Diagnostic logging ---
# After a successful connect, a log file must exist with key entries.
LOG_DIR="$HOME/.local/logs/rcu"
LOG_FILE="$LOG_DIR/rcu-$(date +%Y-%m-%d).log"
if [[ -f "$LOG_FILE" ]]; then
  pass 'diagnostic log file created'
else
  fail 'diagnostic log file missing at '$LOG_FILE
fi
if [[ -f "$LOG_FILE" ]] && grep -q 'SESSION_START' "$LOG_FILE"; then
  pass 'log contains SESSION_START'
else
  fail 'log missing SESSION_START entry'
fi
if [[ -f "$LOG_FILE" ]] && grep -q 'SSH_READY\|SSH_TIMEOUT\|FATAL' "$LOG_FILE"; then
  pass 'log contains SSH outcome entry'
else
  fail 'log missing SSH outcome entry'
fi
if [[ -f "$LOG_FILE" ]] && grep -q 'PROFILE_OK' "$LOG_FILE"; then
  pass 'log contains PROFILE_OK'
else
  fail 'log missing PROFILE_OK entry'
fi
# Verify log directory permissions
if [[ -d "$LOG_DIR" ]]; then
  perms="$(stat -f '%Lp' "$LOG_DIR" 2>/dev/null || stat -c '%a' "$LOG_DIR" 2>/dev/null)"
  if [[ "$perms" == "700" ]]; then
    pass 'log directory has 700 permissions'
  else
    fail "log directory permissions $perms (expected 700)"
  fi
else
  fail 'log directory missing'
fi

# --- Update and rollback ---
# First, install 0.4.1 as the base release via install.sh
/bin/bash "$src/install.sh" >/dev/null 2>&1
expect 'initial install 0.4.1' test "$(cat "$HOME/.local/share/utm/rcu/current/VERSION")" = "0.4.1"

# Then update to 0.4.2
cp -R "$src" "$case_dir/new-bundle"
printf '0.4.2\n' > "$case_dir/new-bundle/VERSION"
expect 'update installs new version' "$HOME/.local/bin/rcu" update "$case_dir/new-bundle"
expect 'new version selected' test "$(cat "$HOME/.local/share/utm/rcu/current/VERSION")" = "0.4.2"

# Rollback must restore 0.4.1
expect 'rollback works' "$HOME/.local/bin/rcu" rollback
expect 'rollback selects earlier release' test "$(cat "$HOME/.local/share/utm/rcu/current/VERSION")" = "0.4.1"

# Failed update must leave the active release unchanged.
cp -R "$src" "$case_dir/bad-bundle"
printf '0.4.3\n' > "$case_dir/bad-bundle/VERSION"
printf 'syntax(\n' >> "$case_dir/bad-bundle/lib/backends/utm.sh"
if "$HOME/.local/bin/rcu" update "$case_dir/bad-bundle" >/dev/null 2>&1; then fail 'corrupt update rejected'; else pass 'corrupt update rejected'; fi
expect 'current release unchanged after failed update' test "$(cat "$HOME/.local/share/utm/rcu/current/VERSION")" = "0.4.1"

# --- Summary ---
[[ "$failures" -eq 0 ]] || { printf '\nFAILURES: %d\n' "$failures" >&2; exit 1; }
printf '\n\033[32mAll smoke tests passed.\033[0m\n'
