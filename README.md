# rcu — Remote Control Unit

Portable, modular macOS command interface for existing UTM installations. Does not modify the Debian guest or install additional SSH keys.

## Installation (macOS host)

Unpack this repository; inspect `install.sh`; run `./install.sh` from its root. Requires UTM already installed. Homebrew is installed via its official interactive installer only if missing; `gum` is installed only if absent. No password is requested unless the installation of a dependency genuinely requires it. `~/.zshrc` receives a single managed PATH line. The only shell command added is `rcu`.

Installation is atomic: a staging directory is prepared, validated, and then activated via a filesystem rename. If activation fails, the previous version is automatically restored. Foreign files at the install path are never overwritten.

A new terminal session should expose `rcu help`.

## Commands (macOS host)

### VM commands

- `rcu utm start`: request a VM start if stopped, check SSH authentication and state.
- `rcu utm connect`: verify SSH connectivity without opening a shell.
- `rcu utm shell`: open an interactive Debian SSH session. Type `exit` to return to macOS.
- `rcu utm stop`: request graceful shutdown; never force stop.
- `rcu utm health`: verify UTM and SSH availability.
- `rcu utm status`: show VM list and SSH target details.

### Management commands

- `rcu update`: reinstall or update rcu from the source directory.
- `rcu rollback`: restore the last working version from backup.
- `rcu uninstall`: remove the `rcu` symlink and PATH entry; preserves config and data.

Progress percentages reflect completed check milestones, NOT actual OS boot percentages; UTM does not expose a validated numerical boot-progress metric.

## Configuration

`~/.config/rcu/config` is copied on the first installation and is private to each Mac. Change VM name, IP, identity key and user per Mac. The configuration file is parsed by a strict validator — no shell code is executed from config values. Only known keys are accepted. The file must have `0600` permissions and must not be a symlink.

The SSH host fingerprint MUST be verified by the operator before initial connection. No automatic host key acceptance is enabled.

For another Mac with the same VM, install the repository and use an authorized SSH identity on that Mac. The existing VM disk is never copied by this installer.

## Safety and rollback

Run `./install.sh --uninstall` or `rcu uninstall` from the project directory to remove the managed `rcu` symlink and `~/.zshrc` PATH block. It preserves your config, VM, keys, and installed dependencies.

Updates automatically back up the previous managed installation. If an update fails, the previous version is restored. Use `rcu rollback` to manually restore the last backup.

## Security properties

- **No force-stop fallback**: `rcu utm stop` uses only `utmctl stop --request`. If graceful shutdown fails, the VM state is left unchanged and an error is reported.
- **Atomic updates**: Staging, integrity check, and atomic rename. Rollback on failure.
- **Safe uninstall**: Only removes rcu-managed artifacts. Never deletes foreign files or user config.
- **Config parser**: No `source` or `eval` on config files. Values are validated against a whitelist of allowed keys and safe characters.
- **Installer conflicts**: Foreign files at the install path are detected and never overwritten.
- **PATH safety**: Never uses Zsh's `path` special variable. Existing shell configuration is preserved.

## Testing

Run `bash tests/smoke.sh` for isolated mock tests (PASS/FAIL/SKIP semantics). Tests verify UTM commands, config parser security, installer safety, and shutdown behavior without requiring a real VM or macOS-specific services.
