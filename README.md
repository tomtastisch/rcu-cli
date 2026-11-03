# rcu — Remote Control Unit

Portable, modular macOS command interface for existing UTM installations. Does not modify the Debian guest or install additional SSH keys.

## Installation (macOS host)

Unpack this repository; inspect `install.sh`; run `./install.sh` from its root. Requires UTM already installed. Homebrew is installed via its official interactive installer only if missing; `gum` is installed only if absent. No password is requested unless the installation of a dependency genuinely requires it. `~/.zshrc` receives a single managed PATH line. The only shell command added is `rcu`.

A new terminal session should expose `rcu help`.

## Commands (macOS host)

- `rcu utm start`: request a VM start if stopped, check SSH authentication and state.
- `rcu utm connect`: verify SSH connectivity without opening a shell.
- `rcu utm shell`: open an interactive Debian SSH session. Type `exit` to return to macOS.
- `rcu utm stop`: request graceful shutdown; never force stop.
- `rcu utm health`: verify UTM and SSH availability.
- `rcu utm status`: show VM list and SSH target details.

Progress percentages reflect completed check milestones, NOT actual OS boot percentages; UTM does not expose a validated numerical boot-progress metric.

## Configuration

`~/.config/rcu/config` is copied on the first installation and is private to each Mac. Change VM name, IP, identity key and user per Mac. The configuration is a trusted Bash file: do not copy values from untrusted sources. The SSH host fingerprint MUST be verified by the operator before initial connection. No automatic host key acceptance is enabled.

For another Mac with the same VM, install the repository and use an authorized SSH identity on that Mac. The existing VM disk is never copied by this installer.

## Safety and rollback

Run `./install.sh --uninstall` from the project directory to remove the managed `rcu` symlink and `~/.zshrc` PATH block. It preserves your config, VM, keys, and installed dependencies. Updates back up a previous managed code directory. Exit SSH with `exit`.

This implementation was validated via syntax and simulated terminal checks; validation against the user's own host must be done there.
