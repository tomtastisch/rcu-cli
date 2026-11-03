#!/usr/bin/env python3
"""Drive the real first-run CLI through a PTY; all OS services are isolated fakes."""
import os
import pty
import select
import shutil
import subprocess
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
UUID = '34567890-1234-4567-8910-123456789ABC'
with tempfile.TemporaryDirectory() as directory:
    base = Path(directory)
    home = base / 'home'
    mock = base / 'mock'
    home.mkdir()
    mock.mkdir()
    env = dict(os.environ, HOME=str(home), XDG_CONFIG_HOME=str(home / '.config'),
               RCU_TEST='1', TERM='xterm-256color', PATH=str(mock) + os.pathsep + os.environ['PATH'],
               TEST_LOG=str(base / 'commands'), TEST_SECRET_STORE=str(base / 'fake-keychain'))
    # Synthetic fixture only, never a user's credential.
    secret = 'synthetic-rcu-test-only'
    scripts = {
        'utmctl': f'''case "$1" in
list) printf 'UUID Status Name\\n{UUID} started Renamed VM On Another Mac\\n' ;;
ip-address) printf '10.33.44.55\\n' ;;
esac''',
        'gum': '''case "$1" in
choose) printf 'AUTH_CHOICE\\n' >> "$TEST_LOG"; head -1 ;;
input) printf 'caseuser\\n' ;;
style) shift; printf '%s\\n' "$@" ;;
esac''',
        'security': '''printf 'security %s\\n' "$*" >> "$TEST_LOG"
service=''
for ((i=1; i<=$#; i++)); do
    if [[ "${!i}" == -s ]]; then next=$((i+1)); service="${!next}"; fi
done
[[ -n "$service" ]] || exit 69
if [[ "$1" == delete-generic-password ]]; then rm -f "$TEST_SECRET_STORE.$service"; exit 0; fi
[[ "$1" == add-generic-password && "${!#}" == -w ]] || exit 70
stty -echo
trap 'stty echo' EXIT
printf 'NATIVE_PASSWORD: ' >&2
# Deliberately expose the scheduling gap; echo must be off before the prompt.
sleep 0.1
IFS= read -rs password
printf '\\n' >&2
printf '%s' "$password" > "$TEST_SECRET_STORE.$service"
chmod 600 "$TEST_SECRET_STORE.$service"''',
        'nc': 'exit 0',
        'ssh-keyscan': "printf '10.33.44.55 ssh-ed25519 AAAAsyntheticfixture\\n'",
        'ssh-keygen': '''case "$1" in
-F) grep -q 'rcu-' "${@: -1}" ;;
-lf) cat >/dev/null; printf '256 SHA256:synthetic-test-fingerprint (ED25519)\\n' ;;
esac''',
        'ssh': '''[[ "${TEST_AUTH_FAIL:-0}" == 0 ]] || exit 255
printf 'ssh %s\\n' "$*" >> "$TEST_LOG"
[[ "${SSH_ASKPASS_REQUIRE:-}" == force && -x "${SSH_ASKPASS:-}" ]] || exit 71
[[ "${RCU_KEYCHAIN_ACCOUNT:-}" == caseuser ]] || exit 72
[[ -f "$TEST_SECRET_STORE.$RCU_KEYCHAIN_SERVICE" ]] || exit 74
for arg in "$@"; do [[ "$arg" != 'id -un' ]] || printf 'caseuser\\n'; done''',
        'scp': '''printf 'scp %s\\n' "$*" >> "$TEST_LOG"
printf 'ARG<%s>\\n' "$@" >> "$TEST_LOG"
[[ "${SSH_ASKPASS_REQUIRE:-}" == force ]] || exit 73
exit "${TEST_SCP_EXIT:-0}"'''
    }
    for name, body in scripts.items():
        file = mock / name
        file.write_text('#!/bin/bash\nset -euo pipefail\n' + body + '\n')
        file.chmod(0o700)
    master, slave = pty.openpty()
    process = subprocess.Popen(['/bin/bash', str(ROOT / 'bin/rcu')], stdin=slave,
                               stdout=slave, stderr=slave, env=env)
    os.close(slave)
    transcript = b''
    sent_password = sent_trust = False
    deadline = time.monotonic() + 12
    try:
        while time.monotonic() < deadline:
            if select.select([master], [], [], .1)[0]:
                try:
                    data = os.read(master, 65536)
                except OSError:
                    break
                if not data:
                    break
                transcript += data
                if b'NATIVE_PASSWORD:' in transcript and not sent_password:
                    os.write(master, (secret + '\n').encode())
                    sent_password = True
                if b'Nur bei' in transcript and not sent_trust:
                    os.write(master, b'yes\n')
                    sent_trust = True
            if process.poll() is not None:
                break
        if process.poll() is None:
            process.kill()
            raise AssertionError('Onboarding timed out: ' + transcript.decode(errors='replace'))
        assert process.wait() == 0, transcript.decode(errors='replace')
    finally:
        if process.poll() is None:
            process.kill()
        process.wait()
        os.close(master)
    profile = home / '.config/rcu/config'
    log = (base / 'commands').read_text()
    assert secret not in transcript.decode(errors='replace')
    assert secret not in log and secret not in profile.read_text()
    assert 'SSH_PASSWORD=' not in profile.read_text()
    assert 'KEYCHAIN_SERVICE=\'rcu.vm.' + UUID + '.' in profile.read_text(), 'Setup needs a fresh credential slot before verification'
    assert ' -U ' not in log, 'Setup must not overwrite the working credential before verifying'
    assert 'SSH_HOST=' not in profile.read_text()
    assert 'VM_NAME=' not in profile.read_text()
    assert sent_password and sent_trust
    assert 'AUTH_CHOICE' not in log, 'Default setup must only request username and password'
    assert log.count('ssh ') >= 3, 'Setup must authenticate before saving the profile'
    enrolled = list(base.glob('fake-keychain.*'))
    assert len(enrolled) == 1 and enrolled[0].read_text() == secret
    assert profile.stat().st_mode & 0o777 == 0o600
    assert 'rcu-' + UUID in (home / '.config/rcu/known_hosts').read_text()
    print('PASS first-run PTY: VM/user/password, native secret prompt, explicit host trust, private profile')
    print('PASS fixture secret absent from output, argv log and config')
    result = subprocess.run(['/bin/bash', str(ROOT / 'bin/rcu')], stdin=subprocess.DEVNULL,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=env, timeout=8)
    assert result.returncode == 0, result.stderr.decode()
    assert (base / 'commands').read_text().count('security add-generic-password') == 1
    print('PASS second run reuses identity and keychain enrollment without onboarding')
    local = base / 'Files with spaces'
    local.mkdir()
    (local / 'example.c').write_text('int main(void) { return 0; }\n')
    # macOS temporary paths include /var -> /private/var. Exercise the same
    # canonical-parent behavior on every OS instead of relying on that layout.
    linked_parent = base / 'linked-downloads'
    linked_parent.symlink_to(base, target_is_directory=True)
    local = linked_parent / local.name
    for code in [0, 9]:
        result = subprocess.run(['/bin/bash', str(ROOT / 'bin/rcu'), 'upload', str(local), '~/course files/'],
                                stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                env=dict(env, TEST_SCP_EXIT=str(code)), timeout=8)
        assert result.returncode == code, result.stderr.decode()
    assert 'scp -s -P 22 ' in (base / 'commands').read_text()
    assert 'ARG<-r>' in (base / 'commands').read_text()
    assert 'ARG<' + str(local.resolve()) + '>' in (base / 'commands').read_text()
    assert 'ARG<caseuser@10.33.44.55:~/course files/>' in (base / 'commands').read_text()
    assert 'caseuser@10.33.44.55:~/course files/' in (base / 'commands').read_text()
    print('PASS upload: shared keychain auth, SFTP, uppercase -P, recursive paths with spaces, exit status')
    # Unknown askpass prompts (trust / MFA) must never release the password.
    for prompt in ['Are you sure you want to continue connecting?', 'Verification code:', 'Enter passphrase for key:']:
        result = subprocess.run([str(ROOT / 'lib/ssh-askpass'), prompt], env=env,
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=3)
        assert result.returncode != 0 and not result.stdout
    print('PASS askpass rejects host trust, MFA and private-key passphrase prompts')

    # Both first-run failure and failed reconfiguration must be transactional.
    for existing in [False, True]:
        rejected_home = base / ('rejected-existing' if existing else 'rejected-fresh')
        rejected_home.mkdir()
        if existing:
            shutil.copytree(home / '.config', rejected_home / '.config')
        rejected_profile = rejected_home / '.config/rcu/config'
        previous = rejected_profile.read_bytes() if existing else None
        previous_items = {f.name: f.read_bytes() for f in base.glob('fake-keychain.*')}
        master, slave = pty.openpty()
        process = subprocess.Popen(['/bin/bash', str(ROOT / 'bin/rcu')], stdin=slave,
            stdout=slave, stderr=slave, env=dict(env, HOME=str(rejected_home),
            XDG_CONFIG_HOME=str(rejected_home / '.config'), TEST_AUTH_FAIL='1'))
        os.close(slave)
        transcript = b''
        password_sent = trust_sent = False
        deadline = time.monotonic() + 12
        try:
            while time.monotonic() < deadline:
                if select.select([master], [], [], .1)[0]:
                    try:
                        data = os.read(master, 65536)
                    except OSError:
                        break
                    if not data:
                        break
                    transcript += data
                    if b'NATIVE_PASSWORD:' in transcript and not password_sent:
                        os.write(master, (secret + '\n').encode())
                        password_sent = True
                    if b'Nur bei' in transcript and not trust_sent:
                        os.write(master, b'yes\n')
                        trust_sent = True
                if process.poll() is not None:
                    break
            assert process.wait(timeout=2) != 0, 'Rejected password was accepted'
            if existing:
                assert rejected_profile.read_bytes() == previous, 'Working profile replaced'
            else:
                assert not rejected_profile.exists(), 'Unverified profile saved'
            assert {f.name: f.read_bytes() for f in base.glob('fake-keychain.*')} == previous_items, 'Working credential changed or staging credential retained'
            assert 'Einrichtung gespeichert' not in transcript.decode(errors='replace')
            assert secret not in transcript.decode(errors='replace')
        finally:
            if process.poll() is None:
                process.kill()
            process.wait()
            os.close(master)
        print('PASS rejected password: profile and credentials preserved, failed enrollment removed')
