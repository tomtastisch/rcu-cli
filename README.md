# rcu — Remote Control Unit

Portable, modular macOS CLI for managing an existing UTM virtual machine via SSH.

## Architecture

```
bin/rcu                  # Main entry point — modular dispatcher
core/config.sh           # Configuration loading and validation
core/utm.sh              # UTM/utmctl operations (VM by UUID)
core/ssh.sh              # SSH transport (probe, wait, terminal)
core/progress.sh         # Terminal UI (gum integration, status display)
commands/start.sh        # rcu utm start
commands/connect.sh      # rcu utm connect
commands/shell.sh        # rcu utm shell
commands/stop.sh         # rcu utm stop
commands/health.sh       # rcu utm health
commands/status.sh       # rcu utm status
commands/doctor.sh       # rcu doctor
installer/install.sh     # Bundle installer (idempotent, atomic)
installer/update.sh      # Atomic version update with rollback backup
installer/rollback.sh    # Roll back to previous verified version
installer/uninstall.sh   # Safe uninstall (preserves config by default)
installer/bootstrap.sh   # One-shot bootstrap → install.sh
config/config.example    # Configuration template
tests/unit/              # Mocked unit tests (Colima-compatible)
tests/integration/       # Installer lifecycle tests (macOS, isolated HOME)
tests/e2e/               # Read-only UTM/SSH integration tests
```

Each module has a single responsibility. No duplicated SSH or UTM logic. No monolithic files.

## Installation (macOS host)

```bash
./installer/install.sh
```

The installer:
1. Verifies macOS and Apple Silicon
2. Checks UTM and utmctl
3. Installs Homebrew if missing (official interactive installer)
4. Installs `gum` via Homebrew if missing
5. Validates bundle integrity (syntax check)
6. Stages installation in a temporary directory
7. Activates the version atomically via symlink
8. Installs the launcher at `~/.local/bin/rcu`
9. Adds a managed PATH entry to `~/.zshrc` only if needed
10. Creates `~/.config/rcu/config` from template

Installation is idempotent — running it again is safe.

### Bundle structure

```
~/.local/share/utm/rcu/
├── releases/
│   └── 0.1.0/          # Versioned bundle
│       ├── bin/rcu
│       ├── core/
│       ├── commands/
│       └── install-manifest
└── current -> releases/0.1.0

~/.local/bin/rcu         # Launcher (resolves bundle via symlink)
~/.config/rcu/config     # Personal configuration
```

## Commands

### UTM Commands

| Command | Description |
|---------|-------------|
| `rcu utm start` | Start VM if stopped, await SSH readiness |
| `rcu utm connect` | Verify SSH connectivity without opening a shell |
| `rcu utm shell` | Open interactive Debian SSH session (`exit` returns to macOS) |
| `rcu utm stop` | Request graceful shutdown; never force stop |
| `rcu utm health` | Verify UTM, VM state, and SSH authentication |
| `rcu utm status` | Show VM details, SSH target, guest identity |

### System Commands

| Command | Description |
|---------|-------------|
| `rcu help` | Show help |
| `rcu doctor` | Diagnose installation and environment (read-only) |
| `rcu update` | Update to new version (via installer/update.sh) |
| `rcu rollback` | Roll back to previous version (via installer/rollback.sh) |
| `rcu uninstall` | Remove RCU safely (via installer/uninstall.sh) |

## Configuration

`~/.config/rcu/config` — trusted shell assignments, private to each Mac:

```bash
VM_UUID='A16B662F-A8E9-4615-B0E9-A16BA73BA7E7'
VM_NAME='Virtuelle Maschine'
SSH_HOST='192.168.64.2'
SSH_USER='lars'
SSH_PORT=22
SSH_KEY="$HOME/.ssh/thi-clion-ed25519"
WAIT_SECONDS=120
UTMCTL='/Applications/UTM.app/Contents/MacOS/utmctl'
```

**Security**: The SSH host fingerprint must be verified by the operator before initial connection. No automatic host key acceptance is enabled.

## Update and Rollback

```bash
# Update (creates rollback backup automatically)
RCU_NEW_VERSION=0.2.0 ./installer/update.sh /path/to/new/bundle

# Roll back to previous version
./installer/rollback.sh
```

## Uninstall

```bash
# Remove RCU, preserve config
./installer/uninstall.sh

# Remove RCU and config
./installer/uninstall.sh --purge-data
```

## Testing

```bash
# Unit tests (mocked — works in Colima)
RCU_TEST=1 bash tests/unit/test_commands.sh

# Integration tests (macOS, isolated HOME)
bash tests/integration/test_installer.sh

# E2E read-only tests (real UTM/SSH)
bash tests/e2e/test_readonly.sh
```

## Safety

- PATH is never overwritten
- No private keys in the repository
- No uncontrolled execution of config contents
- No symlink path traversal
- No installation in unauthorized paths
- No overwriting of unknown existing files
- No global sudo requirement
- Atomic updates preserve the previous working version
- Correct exit codes and error messages

## Notes

Progress percentages reflect only completed, verifiable check phases. UTM does not expose a validated numerical boot-progress metric.
