#!/bin/bash
# installer/install.sh — Install RCU bundle to ~/.local/share/utm/rcu/
# Idempotent, atomic, preserves previous versions.
# Usage: ./install.sh

set -euo pipefail

RCU_VERSION="${RCU_VERSION:-0.1.0}"
RCU_BUNDLE_DIR="$HOME/.local/share/utm/rcu"
RCU_RELEASES_DIR="$RCU_BUNDLE_DIR/releases"
RCU_CURRENT_LINK="$RCU_BUNDLE_DIR/current"
RCU_LAUNCHER="$HOME/.local/bin/rcu"
RCU_CONF_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/rcu"
RCU_ZSHRC="$HOME/.zshrc"
RCU_PATH_MARKER='# rcu-cli: managed PATH'

msg() {
    if [[ -t 1 ]] && command -v gum >/dev/null 2>&1; then
        gum style --foreground 39 "$*"
    else
        printf '%s\n' "$*"
    fi
}

fail() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

# Resolve the source directory (where install.sh lives)
# shellcheck disable=SC1007
SRC_ROOT=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)

# --- Pre-flight checks ---
msg '=== RCU Installer v%s ===' "$RCU_VERSION"

# 1. Check macOS
[[ "$(uname -s)" == Darwin ]] || fail 'RCU requires macOS (Apple Silicon). Run on macOS host.'

# 2. Check UTM
[[ -d /Applications/UTM.app && -x /Applications/UTM.app/Contents/MacOS/utmctl ]] \
    || fail 'UTM not found at /Applications/UTM.app. Install UTM first.'
msg '✓ UTM found'

# 3. Check Homebrew
if ! command -v brew >/dev/null 2>&1; then
    msg 'USER: macOS-Host — Homebrew is missing. The official installer may ask for your password.'
    NONINTERACTIVE=0 /bin/bash -c "$(/usr/bin/curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" \
        || fail 'Homebrew installation failed'
    # Load brew env
    for brew_path in /opt/homebrew/bin/brew /usr/local/bin/brew; do
        if [[ -x "$brew_path" ]]; then
            eval "$("$brew_path" shellenv)" 2>/dev/null || true
            break
        fi
    done
fi
command -v brew >/dev/null 2>&1 || fail 'Homebrew unavailable after installation attempt'
msg '✓ Homebrew found'

# 4. Check gum
if ! command -v gum >/dev/null 2>&1; then
    msg 'Installing gum via Homebrew...'
    brew install gum || fail 'gum installation failed'
fi
msg '✓ gum found'

# 5. Check SSH
[[ -x /usr/bin/ssh ]] || fail 'SSH not found'
msg '✓ SSH found'

# --- Validate bundle integrity ---
msg 'Validating bundle...'
for f in bin/rcu core/config.sh core/utm.sh core/ssh.sh core/progress.sh \
         commands/start.sh commands/connect.sh commands/shell.sh \
         commands/stop.sh commands/health.sh commands/status.sh; do
    [[ -f "$SRC_ROOT/$f" ]] || fail "Missing bundle file: $f"
done

# Syntax check all shell files
for f in "$SRC_ROOT"/bin/rcu "$SRC_ROOT"/core/*.sh "$SRC_ROOT"/commands/*.sh; do
    /bin/bash -n "$f" 2>/dev/null || { fail "Syntax error in $f"; }
done
msg '✓ Bundle syntax valid'

# --- Stage installation ---
mkdir -p "$HOME/.local/share"
STAGING=$(mktemp -d "$HOME/.local/share/.rcu-stage.XXXXXX")
trap 'rm -rf "$STAGING"' EXIT

# Copy bundle to staging
cp -R "$SRC_ROOT/bin" "$SRC_ROOT/core" "$SRC_ROOT/commands" "$SRC_ROOT/config" "$STAGING/"

# Create install manifest
cat > "$STAGING/install-manifest" <<MANIFEST
# RCU Install Manifest — do not edit
version=$RCU_VERSION
installed_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
files=bin/rcu
files=core/config.sh
files=core/utm.sh
files=core/ssh.sh
files=core/progress.sh
files=commands/start.sh
files=commands/connect.sh
files=commands/shell.sh
files=commands/stop.sh
files=commands/health.sh
files=commands/status.sh
MANIFEST

# --- Atomic activation ---
mkdir -p "$RCU_RELEASES_DIR" "$HOME/.local/bin" "$RCU_CONF_DIR"

# Place in versioned directory
VERSION_DIR="$RCU_RELEASES_DIR/$RCU_VERSION"
if [[ -d "$VERSION_DIR" ]]; then
    # Already installed — idempotent, skip copy
    msg 'Version %s already installed, skipping copy.' "$RCU_VERSION"
else
    mv "$STAGING" "$VERSION_DIR"
fi
trap - EXIT

# Update current symlink atomically
if [[ -L "$RCU_CURRENT_LINK" ]]; then
    rm "$RCU_CURRENT_LINK"
fi
ln -s "$VERSION_DIR" "$RCU_CURRENT_LINK"

# --- Install launcher ---
# The launcher resolves the bundle via the current symlink
cat > "$RCU_LAUNCHER" <<'LAUNCHER'
#!/bin/bash
# RCU Launcher — resolves bundle via ~/.local/share/utm/rcu/current
set -euo pipefail
RCU_BUNDLE="$HOME/.local/share/utm/rcu/current"
if [[ ! -d "$RCU_BUNDLE" ]]; then
    printf 'ERROR: RCU bundle not found at %s\n' "$RCU_BUNDLE" >&2
    exit 1
fi
export RCU_BUNDLE_ROOT="$RCU_BUNDLE"
exec "$RCU_BUNDLE/bin/rcu" "$@"
LAUNCHER
chmod +x "$RCU_LAUNCHER"

# --- Config ---
if [[ ! -f "$RCU_CONF_DIR/config" ]]; then
    cp "$SRC_ROOT/config/config.example" "$RCU_CONF_DIR/config"
    chmod 600 "$RCU_CONF_DIR/config"
    msg 'Configuration created at ~/.config/rcu/config'
fi

# --- PATH in ~/.zshrc ---
# Only add if ~/.local/bin is not already covered
if [[ ! -f "$RCU_ZSHRC" ]] || ! grep -qF "$RCU_PATH_MARKER" "$RCU_ZSHRC" 2>/dev/null; then
    # shellcheck disable=SC2016
    printf '\n%s\nexport PATH="$HOME/.local/bin:$PATH"\n' "$RCU_PATH_MARKER" >> "$RCU_ZSHRC"
    msg 'Added managed PATH entry to ~/.zshrc'
else
    msg 'PATH entry already present in ~/.zshrc'
fi

# --- Final summary ---
msg ''
msg '=== RCU v%s installed successfully ===' "$RCU_VERSION"
msg ''
msg 'Bundle:   ~/.local/share/utm/rcu/releases/%s' "$RCU_VERSION"
msg 'Symlink:  ~/.local/share/utm/rcu/current -> releases/%s' "$RCU_VERSION"
msg 'Launcher: ~/.local/bin/rcu'
msg 'Config:   ~/.config/rcu/config'
msg ''
msg 'In a new terminal: rcu help'
msg 'In this terminal:  source ~/.zshrc && rcu help'
msg ''
msg 'Commands:'
msg '  rcu utm start    rcu utm connect    rcu utm shell'
msg '  rcu utm stop     rcu utm health     rcu utm status'
msg '  rcu help         rcu doctor         rcu uninstall'
