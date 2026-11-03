#!/usr/bin/env python3
"""Drive the real first-run CLI through a PTY; all OS services are isolated fakes."""
import os
import pty
import select
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
choose) head -1 ;;
input) printf 'caseuser\\n' ;;
style) shift; printf '%s\\n' "$@" ;;
esac''',
        'security': '''printf 'security %s\\n' "$*" >> "$TEST_LOG"
[[ "$1" == add-generic-password && "${!#}" == -w ]] || exit 70
printf 'NATIVE_PASSWORD: ' >&2
IFS= read -rs password
printf '\\n' >&2
printf '%s' "$password" > "$TEST_SECRET_STORE"
chmod 600 "$TEST_SECRET_STORE"''',
        'nc': 'exit 0',
        'ssh-keyscan': "printf '10.33.44.55 ssh-ed25519 AAAAsyntheticfixture\\n'",
        'ssh-keygen': '''case "$1" in
-F) grep -q 'rcu-' "${@: -1}" ;;
-lf) cat >/dev/null; printf '256 SHA256:synthetic-test-fingerprint (ED25519)\\n' ;;
esac''',
        'ssh': '''printf 'ssh %s\\n' "$*" >> "$TEST_LOG"
[[ "${SSH_ASKPASS_REQUIRE:-}" == force && -x "${SSH_ASKPASS:-}" ]] || exit 71
[[ "${RCU_KEYCHAIN_ACCOUNT:-}" == caseuser ]] || exit 72
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
    assert 'SSH_HOST=' not in profile.read_text()
    assert 'VM_NAME=' not in profile.read_text()
    assert sent_password and sent_trust
    assert (base / 'fake-keychain').read_text() == secret
    assert profile.stat().st_mode & 0o777 == 0o600
    assert 'rcu-' + UUID in (home / '.config/rcu/known_hosts').read_text()
    print('PASS first-run PTY: VM/user/auth choice, native secret prompt, explicit host trust, private profile')
    print('PASS fixture secret absent from output, argv log and config')
    result = subprocess.run(['/bin/bash', str(ROOT / 'bin/rcu')], stdin=subprocess.DEVNULL,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=env, timeout=8)
    assert result.returncode == 0, result.stderr.decode()
    assert (base / 'commands').read_text().count('security add-generic-password') == 1
    print('PASS second run reuses identity and keychain enrollment without onboarding')
    local = base / 'Files with spaces'
    local.mkdir()
    (local / 'example.c').write_text('int main(void) { return 0; }\n')
    for code in [0, 9]:
        result = subprocess.run(['/bin/bash', str(ROOT / 'bin/rcu'), 'upload', str(local), '~/course files/'],
                                stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                env=dict(env, TEST_SCP_EXIT=str(code)), timeout=8)
        assert result.returncode == code, result.stderr.decode()
    assert 'scp -s -P 22 ' in (base / 'commands').read_text()
    assert 'ARG<-r>' in (base / 'commands').read_text()
    assert 'ARG<' + str(local) + '>' in (base / 'commands').read_text()
    assert 'ARG<caseuser@10.33.44.55:~/course files/>' in (base / 'commands').read_text()
    assert 'caseuser@10.33.44.55:~/course files/' in (base / 'commands').read_text()
    print('PASS upload: shared keychain auth, SFTP, uppercase -P, recursive paths with spaces, exit status')
    # Unknown askpass prompts (trust / MFA) must never release the password.
    for prompt in ['Are you sure you want to continue connecting?', 'Verification code:', 'Enter passphrase for key:']:
        result = subprocess.run([str(ROOT / 'lib/ssh-askpass'), prompt], env=env,
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=3)
        assert result.returncode != 0 and not result.stdout
    print('PASS askpass rejects host trust, MFA and private-key passphrase prompts')
