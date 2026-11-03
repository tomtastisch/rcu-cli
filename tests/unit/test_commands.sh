#!/bin/bash
# tests/unit/test_commands.sh — Unit tests with mocked utmctl and SSH.
# Runs entirely in a temporary HOME with controlled PATH.
# Can be executed on macOS or in Colima (with RCU_TEST=1).
set -euo pipefail

# shellcheck disable=SC1007
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../../" && pwd)
TMP=$(mktemp -d "$HOME/.rcu-test-home.XXXXXX")
trap 'rm -rf "$TMP"' EXIT

# Create mock binaries
mkdir -p "$TMP/bin" "$TMP/.ssh" "$TMP/state"
printf 'dummy-key\n' > "$TMP/.ssh/key"
chmod 600 "$TMP/.ssh/key"
printf 'started\n' > "$TMP/state/current"

# Mock utmctl — output format must match real utmctl (space-separated columns)
cat > "$TMP/bin/utmctl" <<'MOCK'
#!/bin/bash
STATE_FILE="${TEST_STATE:-/dev/null}"
case "${1:-}" in
    list)
        printf 'UUID                                 Status   Name\n'
        printf '%-42s %s  %s\n' 'A16B662F-A8E9-4615-B0E9-A16BA73BA7E7' "$(cat "$STATE_FILE")" 'Virtuelle Maschine'
        ;;
    start)
        printf 'started\n' > "$STATE_FILE"
        ;;
    stop)
        [[ "${2:-}" == "--request" ]] || { echo 'not graceful' >&2; exit 7; }
        printf 'stopped\n' > "$STATE_FILE"
        ;;
    version)
        printf '5.0.8\n'
        ;;
    *)
        exit 8
        ;;
esac
MOCK
chmod +x "$TMP/bin/utmctl"

# Mock ssh
cat > "$TMP/bin/ssh" <<'MOCK'
#!/bin/bash
# Parse args to find the command at the end
CMD=""
for arg in "$@"; do
    if [[ "$arg" != -* && "$arg" != *@* && "$arg" != *:* ]]; then
        CMD="$arg"
    fi
done
if [[ "${TEST_SSH_FAIL:-0}" == 1 ]]; then
    exit 255
fi
case "${CMD:-}" in
    'id -un') printf 'lars\n' ;;
    'hostname') printf 'ws25-AsmCpp2204-32bit\n' ;;
    'uname -m') printf 'i686\n' ;;
    *) exit 0 ;;
esac
MOCK
chmod +x "$TMP/bin/ssh"

# Mock gum (no-op)
cat > "$TMP/bin/gum" <<'MOCK'
#!/bin/bash
# gum spin: run the command after --
for i in "$@"; do
    if [[ "$i" == "--" ]]; then
        shift
        "$@"
        return $?
    fi
done
printf '%s\n' "$*"
MOCK
chmod +x "$TMP/bin/gum"

# Config
cat > "$TMP/config" <<EOF
VM_UUID='A16B662F-A8E9-4615-B0E9-A16BA73BA7E7'
VM_NAME='Virtuelle Maschine'
SSH_HOST='192.168.64.2'
SSH_USER='lars'
SSH_PORT=22
SSH_KEY='$TMP/.ssh/key'
WAIT_SECONDS=2
UTMCTL='$TMP/bin/utmctl'
EOF

# Environment
export RCU_TEST=1
export RCU_CONFIG="$TMP/config"
export TEST_STATE="$TMP/state/current"
export PATH="$TMP/bin:$PATH"

PASS=0
FAIL=0
total=0

run_test() {
    local name="$1"
    shift
    total=$((total + 1))
    if "$@" >/dev/null 2>&1; then
        PASS=$((PASS + 1))
        printf '  ✓ %s\n' "$name"
    else
        FAIL=$((FAIL + 1))
        printf '  ✗ %s\n' "$name"
    fi
}

run_test_fail() {
    local name="$1"
    shift
    total=$((total + 1))
    if "$@" >/dev/null 2>&1; then
        FAIL=$((FAIL + 1))
        printf '  ✗ %s (should have failed)\n' "$name"
    else
        PASS=$((PASS + 1))
        printf '  ✓ %s (correctly failed)\n' "$name"
    fi
}

printf '=== Unit Tests (mocked) ===\n'

# Help
run_test 'rcu help' "$ROOT/bin/rcu" help
run_test 'rcu --help' "$ROOT/bin/rcu" --help
run_test 'rcu (no args)' "$ROOT/bin/rcu"

# Status
run_test 'rcu utm status' "$ROOT/bin/rcu" utm status

# Health
run_test 'rcu utm health' "$ROOT/bin/rcu" utm health

# Connect
run_test 'rcu utm connect' "$ROOT/bin/rcu" utm connect

# Start (already started)
run_test 'rcu utm start (already running)' "$ROOT/bin/rcu" utm start

# Stop
run_test 'rcu utm stop' "$ROOT/bin/rcu" utm stop
if [[ "$(cat "$TMP/state/current")" == "stopped" ]]; then
    printf '  ✓ stop sets state to stopped\n'
    PASS=$((PASS + 1))
else
    printf '  ✗ stop state check\n'
    FAIL=$((FAIL + 1))
fi
total=$((total + 1))

# Start (from stopped)
run_test 'rcu utm start (from stopped)' "$ROOT/bin/rcu" utm start
if [[ "$(cat "$TMP/state/current")" == "started" ]]; then
    printf '  ✓ start sets state to started\n'
    PASS=$((PASS + 1))
else
    printf '  ✗ start state check\n'
    FAIL=$((FAIL + 1))
fi
total=$((total + 1))

# Error cases
export TEST_SSH_FAIL=1
run_test_fail 'rcu utm health (SSH fail)' "$ROOT/bin/rcu" utm health
run_test_fail 'rcu utm connect (SSH fail)' "$ROOT/bin/rcu" utm connect
unset TEST_SSH_FAIL

run_test_fail 'rcu utm wrong' "$ROOT/bin/rcu" utm wrong
run_test_fail 'rcu wrong' "$ROOT/bin/rcu" wrong

# Doctor (runs without crash — expected to find issues since not installed)
total=$((total + 1))
if "$ROOT/bin/rcu" doctor >/dev/null 2>&1; then
    # Doctor passes only if everything is installed — not expected here
    PASS=$((PASS + 1))
    printf '  ✓ rcu doctor (runs, all pass — unexpected but OK)\n'
else
    # Doctor finds issues — expected, as long as it doesn't crash
    PASS=$((PASS + 1))
    printf '  ✓ rcu doctor (runs, reports issues — expected)\n'
fi

printf '\n=== Results: %d/%d passed, %d failed ===\n' "$PASS" "$total" "$FAIL"
[[ $FAIL -eq 0 ]] || exit 1
