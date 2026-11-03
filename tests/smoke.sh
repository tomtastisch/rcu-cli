#!/bin/bash
# End-to-end lifecycle tests with fully isolated HOME and mocked external services.
set -euo pipefail
src="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
case_dir="$(mktemp -d)"
trap 'rm -rf "$case_dir"' EXIT
export HOME="$case_dir/home" XDG_CONFIG_HOME="$case_dir/home/.config" RCU_TEST=1
mkdir -p "$HOME/.ssh" "$case_dir/mock" "$case_dir/vm"
printf 'fake-identity\n' > "$HOME/.ssh/optional-test-key"
chmod 600 "$HOME/.ssh/optional-test-key"
printf 'started\n' > "$case_dir/vm/state"
export TEST_VM_STATE="$case_dir/vm/state" TEST_VM_LOG="$case_dir/vm/log" TEST_VM_FAIL=0 TEST_SSH_FAIL=0
: > "$TEST_VM_LOG"
cat > "$case_dir/mock/utmctl" <<'MOCK'
#!/bin/bash
printf '%s\n' "$*" >> "$TEST_VM_LOG"
case "$1" in
  list) printf 'UUID Status Name\n23456789-1234-4567-8910-123456789ABC %s Sample VM\n' "$(cat "$TEST_VM_STATE")" ;;
  start) printf 'started\n' > "$TEST_VM_STATE" ;;
  stop)
    [[ "$2" == --request ]] || exit 19
    [[ "${TEST_VM_FAIL:-0}" == 0 ]] || exit 20
    printf 'stopped\n' > "$TEST_VM_STATE" ;;
  *) exit 21 ;;
esac
MOCK
cat > "$case_dir/mock/ssh" <<'MOCK'
#!/bin/bash
[[ "${TEST_SSH_FAIL:-0}" == 0 ]] || exit 255
for word in "$@"; do
  if [[ "$word" == 'id -un' ]]; then printf 'guesttest\n'; break; fi
done
exit 0
MOCK
cat > "$case_dir/mock/brew" <<'MOCK'
#!/bin/bash
printf 'mock brew\n'
MOCK
cat > "$case_dir/mock/gum" <<'MOCK'
#!/bin/bash
# Real gum spin executes the command after -- and forwards its exit status.
# A no-op mock made TTY tests falsely report success without running utmctl.
case "${1:-}" in
  spin)
    while (( $# > 0 )); do
      if [[ "$1" == '--' ]]; then
        shift
        (( $# > 0 )) || exit 64
        exec "$@"
      fi
      shift
    done
    printf 'mock gum: missing -- command separator\n' >&2
    exit 64
    ;;
  style)
    shift
    while (( $# > 1 )); do shift; done
    printf '%s\n' "${1:-}"
    ;;
  *)
    printf 'mock gum: unexpected subcommand %s\n' "${1:-}" >&2
    exit 64
    ;;
esac
MOCK
cat > "$case_dir/mock/nc" <<'MOCK'
#!/bin/bash
exit 0
MOCK
cat > "$case_dir/mock/ssh-keygen" <<'MOCK'
#!/bin/bash
exit 0
MOCK
chmod +x "$case_dir/mock/"*
export PATH="$case_dir/mock:/usr/bin:/bin"
export RCU_UTMCTL_PATH="$case_dir/mock/utmctl"
export RCU_CONFIG="$HOME/.config/rcu/config"
mkdir -p "$(dirname "$RCU_CONFIG")"
cat > "$RCU_CONFIG" <<EOF2
CONFIG_VERSION=1
ADDRESS_MODE=manual
AUTH_MODE=agent
VM_UUID='23456789-1234-4567-8910-123456789ABC'
VM_NAME='Sample VM'
UTMCTL='$case_dir/mock/utmctl'
SSH_KEY='$HOME/.ssh/optional-test-key'
SSH_HOST='10.19.23.41'
SSH_USER='guesttest'
WAIT_SECONDS=2
EOF2
chmod 600 "$RCU_CONFIG"
printf 'test-pinned-key\n' > "$(dirname "$RCU_CONFIG")/known_hosts"
PASS=0
FAIL=0
pass() { PASS=$((PASS+1)); printf 'PASS %s\n' "$1"; }
fail() { FAIL=$((FAIL+1)); printf 'FAIL %s\n' "$1" >&2; }
expect() { local label="$1"; shift; if "$@"; then pass "$label"; else fail "$label"; fi; }
check_link() { [[ -L "$HOME/.local/bin/rcu" && "$(readlink "$HOME/.local/bin/rcu")" == "$HOME/.local/share/utm/rcu/current/bin/rcu" ]]; }
current_version() { basename "$(readlink "$HOME/.local/share/utm/rcu/current")"; }
previous_version() { basename "$(readlink "$HOME/.local/share/utm/rcu/previous")"; }

expect 'first install' /bin/bash "$src/install.sh"
expect 'launcher target points into bundle' check_link
expect 'installed launcher can load modules and show help' "$HOME/.local/bin/rcu" help
expect 'install adds managed zsh PATH once' grep -Fxq '# rcu-cli: managed PATH' "$HOME/.zshrc"
expect 'first install is idempotent' /bin/bash "$src/install.sh"
expect 'no duplicate zsh marker' test "$(grep -Fc '# rcu-cli: managed PATH' "$HOME/.zshrc")" -eq 1
expect 'initial version selected' test "$(current_version)" = 0.4.0
expect 'health with mocked guest' "$HOME/.local/bin/rcu" utm health
expect 'connect with mocked guest' "$HOME/.local/bin/rcu" utm connect
connect_output="$("$HOME/.local/bin/rcu" utm connect 2>&1)"
expect 'connect reports elapsed UTM and SSH state' grep -Eq 'elapsed=[0-9]+s UTM=started SSH=authenticated' <<<"$connect_output"
expect 'status with mocked guest' "$HOME/.local/bin/rcu" utm status
expect 'shell command exits with SSH mock' "$HOME/.local/bin/rcu" utm shell
printf 'stopped\n' > "$TEST_VM_STATE"
: > "$TEST_VM_LOG"
if "$HOME/.local/bin/rcu" >/dev/null 2>&1 &&
  [[ "$(cat "$TEST_VM_STATE")" == started ]] &&
  [[ "$(grep -c '^start ' "$TEST_VM_LOG")" -eq 1 ]]; then
  pass 'direct launcher starts stopped VM and opens shell'
else
  fail 'direct launcher starts stopped VM and opens shell'
fi
expect 'direct launcher issued one VM start' test "$(grep -c '^start ' "$TEST_VM_LOG")" -eq 1
expect 'direct launcher leaves VM started' test "$(cat "$TEST_VM_STATE")" = started
 : > "$TEST_VM_LOG"
if "$HOME/.local/bin/rcu" >/dev/null 2>&1 &&
  [[ "$(cat "$TEST_VM_STATE")" == started ]] &&
  [[ "$(grep -c '^start ' "$TEST_VM_LOG")" -eq 0 ]]; then
  pass 'direct launcher reuses running VM'
else
  fail 'direct launcher reuses running VM'
fi

export TEST_VM_FAIL=1
: > "$TEST_VM_LOG"
if "$HOME/.local/bin/rcu" utm stop >/dev/null 2>&1; then fail 'failed graceful stop returns nonzero'; else pass 'failed graceful stop returns nonzero'; fi
expect 'exactly one graceful stop request' test "$(grep -c '^stop --request ' "$TEST_VM_LOG")" -eq 1
expect 'no force-stop fallback' test "$(grep -c '^stop ' "$TEST_VM_LOG")" -eq 1
expect 'VM unchanged after failed shutdown' test "$(cat "$TEST_VM_STATE")" = started
export TEST_VM_FAIL=0
expect 'graceful stop succeeds' "$HOME/.local/bin/rcu" utm stop
expect 'guest state is stopped' test "$(cat "$TEST_VM_STATE")" = stopped
expect 'VM start succeeds' "$HOME/.local/bin/rcu" utm start
export TEST_SSH_FAIL=1
if "$HOME/.local/bin/rcu" utm connect >/dev/null 2>&1; then fail 'SSH failures propagate'; else pass 'SSH failures propagate'; fi
export TEST_SSH_FAIL=0

# Reject untrusted configuration strings; no `source` or eval used.
cp "$RCU_CONFIG" "$case_dir/good-config"
cat > "$RCU_CONFIG" <<'MAL'
VM_NAME='Sample VM'; false
MAL
chmod 600 "$RCU_CONFIG"
if "$HOME/.local/bin/rcu" utm health >/dev/null 2>&1; then fail 'malicious configuration rejected'; else pass 'malicious configuration rejected'; fi
cp "$case_dir/good-config" "$RCU_CONFIG"

# Prepare another tested release and switch by the installed update command.
cp -R "$src" "$case_dir/version2"
printf '0.4.1\n' > "$case_dir/version2/VERSION"
expect 'update command installs new release' "$HOME/.local/bin/rcu" update "$case_dir/version2"
expect 'new version selected' test "$(current_version)" = 0.4.1
expect 'previous release retained' test "$(previous_version)" = 0.4.0
expect 'rollback switches version (current test shell)' "$HOME/.local/bin/rcu" rollback
expect 'rollback selects earlier release' test "$(current_version)" = 0.4.0

# Failed update must leave the active release unchanged.
cp -R "$src" "$case_dir/bad-bundle"
printf '0.4.2\n' > "$case_dir/bad-bundle/VERSION"
printf 'syntax(\n' >> "$case_dir/bad-bundle/lib/backends/utm.sh"
if "$HOME/.local/bin/rcu" update "$case_dir/bad-bundle" >/dev/null 2>&1; then fail 'corrupt update rejected'; else pass 'corrupt update rejected'; fi
expect 'current release unchanged after failed update' test "$(current_version)" = 0.4.0

# Foreign launcher collisions must not overwrite the foreign file.
expect 'uninstall through installed CLI' "$HOME/.local/bin/rcu" uninstall
expect 'launcher deactivated' test ! -e "$HOME/.local/bin/rcu"
expect 'managed PATH line removed' test "$(grep -Fc '# rcu-cli: managed PATH' "$HOME/.zshrc" || true)" -eq 0
expect 'user config preserved' test -f "$RCU_CONFIG"
expect 'bundle removed from active install path' test ! -e "$HOME/.local/share/utm/rcu"
expect 'old releases archived' test -d "$(find "$HOME/.local/share/utm" -maxdepth 1 -name 'rcu.uninstalled.*' -type d | head -1)"
printf 'foreign launcher\n' > "$HOME/.local/bin/rcu"
if /bin/bash "$src/install.sh" >/dev/null 2>&1; then fail 'foreign launcher prevents reinstall'; else pass 'foreign launcher prevents reinstall'; fi
expect 'foreign launcher contents preserved' grep -Fxq 'foreign launcher' "$HOME/.local/bin/rcu"

printf 'RESULT: %d PASS, %d FAIL\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
