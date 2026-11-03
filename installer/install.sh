#!/bin/bash
# Install immutable releases, then switch the active pointer atomically.
set -euo pipefail
src="${1:?Source directory required}"
# shellcheck source=installer/common.sh
source "$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/common.sh"
rcu_check_platform
rcu_check_base
rcu_check_launcher
[[ -f "$src/VERSION" ]] || rcu_die 'VERSION is missing.'
version="$(cat "$src/VERSION")"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || rcu_die 'Invalid semantic version.'
required=(bin/rcu lib/core.sh lib/backends/utm.sh install.sh VERSION installer/common.sh installer/install.sh installer/uninstall.sh installer/rollback.sh config/config.example)
for file in "${required[@]}"; do
  [[ -f "$src/$file" && ! -L "$src/$file" ]] || rcu_die "Missing or symlinked source file: $file"
  case "$file" in *.sh|bin/rcu) /bin/bash -n "$src/$file" || rcu_die "Invalid shell syntax: $file" ;; esac
done
utmctl="${RCU_UTMCTL_PATH:-/Applications/UTM.app/Contents/MacOS/utmctl}"
[[ -x "$utmctl" ]] || rcu_die 'UTM/utmctl is not installed or not executable.'
rcu_info 'UTM found.'
if ! command -v brew >/dev/null 2>&1; then
  [[ "${RCU_TEST:-0}" != 1 ]] || rcu_die 'Homebrew missing in isolated test; refusing network installation.'
  rcu_user 'macOS-Host: Homebrew is missing. Its official installer may request your macOS password; follow the displayed prompts.'
  NONINTERACTIVE=0 /bin/bash -c "$(/usr/bin/curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || rcu_die 'Homebrew setup failed.'
  for brew_file in /opt/homebrew/bin/brew /usr/local/bin/brew; do
    if [[ -x "$brew_file" ]]; then eval "$("$brew_file" shellenv)"; break; fi
  done
fi
command -v brew >/dev/null 2>&1 || rcu_die 'Homebrew unavailable.'
rcu_info 'Homebrew found.'
if ! command -v gum >/dev/null 2>&1; then
  [[ "${RCU_TEST:-0}" != 1 ]] || rcu_die 'gum missing in isolated test; refusing host package installation.'
  rcu_user 'macOS-Host: Installing missing gum via Homebrew; no global sudo invocation.'
  brew install gum || rcu_die 'gum setup failed.'
fi
command -v gum >/dev/null 2>&1 || rcu_die 'gum unavailable.'
rcu_info 'gum found.'
[[ ! -L "$RCU_ZSHRC" ]] || rcu_die 'Refusing to change symlinked .zshrc.'
[[ ! -L "$RCU_CONFIG_DIR" ]] || rcu_die 'Refusing symlinked config directory.'

mkdir -p "$RCU_RELEASES" "$HOME/.local/bin" "$RCU_CONFIG_DIR"
[[ ! -L "$RCU_RELEASES" ]] || rcu_die 'Releases directory must not be a symlink.'
printf 'rcu-cli\n' > "$RCU_BASE/.rcu-managed"
release="$RCU_RELEASES/$version"
stage="$(mktemp -d "$RCU_RELEASES/.rcu-stage.XXXXXX")"
trap '[[ -z "${stage:-}" ]] || rm -rf "$stage"' EXIT
cp -R "$src/bin" "$src/lib" "$src/installer" "$src/config" "$stage/"
cp "$src/install.sh" "$src/VERSION" "$stage/"
printf 'rcu-cli release %s\n' "$version" > "$stage/.rcu-managed"
# Verify staged bundle; fail if reusing a version with different content.
for file in "${required[@]}"; do
  cmp -s "$src/$file" "$stage/$file" || rcu_die "Staging integrity check failed: $file"
done
if [[ -e "$release" || -L "$release" ]]; then
  rcu_owned_release "$release" || rcu_die 'Version directory collision.'
  for file in "${required[@]}"; do
    cmp -s "$stage/$file" "$release/$file" || rcu_die 'Version already exists with different content. Bump VERSION.'
  done
else
  mv "$stage" "$release" || rcu_die 'Cannot publish release.'
  stage=''
fi

# Prepare config and PATH before switching runtime versions.
if [[ ! -e "$RCU_CONFIG_DIR/config" && ! -L "$RCU_CONFIG_DIR/config" ]]; then
  cp "$src/config/config.example" "$RCU_CONFIG_DIR/config"
  chmod 600 "$RCU_CONFIG_DIR/config"
fi
[[ ! -L "$RCU_CONFIG_DIR/config" ]] || rcu_die 'Refusing symlinked config file.'
if [[ ! -e "$RCU_LAUNCHER" && ! -L "$RCU_LAUNCHER" ]]; then
  rcu_atomic_link "$RCU_LAUNCHER" "$RCU_CURRENT/bin/rcu" || rcu_die 'Could not install launcher.'
fi
# Check persistent Zsh configuration rather than relying on this subprocess PATH.
# macOS may pass a transient PATH that a future shell will not inherit.
if [[ ! -f "$RCU_ZSHRC" ]] || ! grep -Fxq "$RCU_PATH_MARKER" "$RCU_ZSHRC"; then
  if [[ ! -f "$RCU_ZSHRC" ]] || ! grep -Eq '^[[:space:]]*(export[[:space:]]+)?PATH=.*\.local/bin' "$RCU_ZSHRC"; then
    if [[ -f "$RCU_ZSHRC" ]]; then
      cp -p "$RCU_ZSHRC" "$RCU_ZSHRC.rcu-backup.$(date +%Y%m%d%H%M%S)"
    fi
    printf '\n%s\n%s\n' "$RCU_PATH_MARKER" "$RCU_PATH_LINE" >> "$RCU_ZSHRC"
  fi
fi

old=''
old="$(rcu_current_target)" || true
if [[ "$old" != "$release" ]]; then
  if [[ -n "$old" ]]; then
    rcu_atomic_link "$RCU_PREVIOUS" "$old" || rcu_die 'Cannot record previous release.'
  fi
  rcu_atomic_link "$RCU_CURRENT" "$release" || rcu_die 'Could not activate release.'
fi
# Runtime verification via installed launcher. Do not assume success from syntax checks alone.
if ! "$RCU_LAUNCHER" help >/dev/null; then
  if [[ -n "$old" && "$old" != "$release" ]]; then
    rcu_atomic_link "$RCU_CURRENT" "$old" || rcu_die 'Runtime check failed AND rollback failed.'
  fi
  rcu_die 'Runtime verification failed. Active release restored when available.'
fi
rcu_info "RCU $version installed; runtime help verified."
rcu_info 'Commands: rcu utm {start|connect|shell|stop|health|status}; rcu update <source>; rcu rollback; rcu uninstall.'
rcu_info 'If rcu is not visible in this shell, open a new macOS terminal or source ~/.zshrc yourself.'
