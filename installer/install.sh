#!/bin/bash
# Install immutable releases, then switch the active pointer atomically.
set -euo pipefail
src="${1:?Source directory required}"
# shellcheck source=installer/common.sh
source "$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/common.sh"
rcu_check_platform
rcu_check_base
rcu_check_launcher
[[ -f "$src/VERSION" ]] || rcu_die 'VERSION is missing.'
version="$(cat "$src/VERSION")"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || rcu_die 'Invalid semantic version.'
required=(bin/rcu lib/core.sh lib/setup.sh lib/network.sh lib/ssh-askpass lib/backends/utm.sh install.sh VERSION installer/common.sh installer/install.sh installer/uninstall.sh installer/rollback.sh config/config.example)
for file in "${required[@]}"; do
  [[ -f "$src/$file" && ! -L "$src/$file" ]] || rcu_die "Missing or symlinked source file: $file"
  case "$file" in *.sh|bin/rcu|lib/ssh-askpass) /bin/bash -n "$src/$file" || rcu_die "Invalid shell syntax: $file" ;; esac
done
utmctl="${RCU_UTMCTL_PATH:-}"
if [[ -z "$utmctl" ]]; then
  utmctl="$(command -v utmctl || true)"
  if [[ -z "$utmctl" ]]; then
    for utmctl in /Applications/UTM.app/Contents/MacOS/utmctl "$HOME/Applications/UTM.app/Contents/MacOS/utmctl"; do
      [[ ! -x "$utmctl" ]] || break
    done
  fi
fi
[[ -x "$utmctl" ]] || rcu_die 'UTM/utmctl is not installed or not executable.'
rcu_info 'UTM found.'
if ! command -v brew >/dev/null 2>&1; then
  [[ "${RCU_TEST:-0}" != 1 ]] || rcu_die 'Homebrew missing in isolated test; refusing network installation.'
  rcu_user 'macOS-Host: Homebrew is missing. Its official installer may request your macOS password; follow the displayed prompts.'
  NONINTERACTIVE=0 /bin/bash -c "$(/usr/bin/curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || rcu_die 'Homebrew setup failed.'
  for brew_file in /opt/homebrew/bin/brew /usr/local/bin/brew; do
    if [[ -x "$brew_file" ]]; then eval "$("$brew_file" shellenv)"; break
    fi
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
chmod +x "$stage/bin/rcu" "$stage/lib/ssh-askpass"
printf 'rcu-cli release %s\n' "$version" > "$stage/.rcu-managed"
# Verify staged bundle; fail if reusing a version with different content.
for file in "${required[@]}"; do
  [[ -f "$stage/$file" ]] || rcu_die "Staged file missing: $file"
done
if [[ -d "$release" ]]; then
  for file in "${required[@]}"; do
    cmp -s "$stage/$file" "$release/$file" || rcu_die "Version $version already installed with different content. Bump the version or fix the source."
  done
  rcu_info "Version $version already installed; nothing to do."
  rcu_atomic_link "$RCU_CURRENT" "$release"
else
  mv -f "$stage" "$release"
  stage=''
fi
rcu_atomic_link "$RCU_CURRENT" "$release"
rcu_atomic_link "$RCU_PREVIOUS" "$release"
rcu_info "RCU $version installed; runtime help verified."
rcu_info "Commands: rcu; rcu setup; rcu upload; rcu utm {start|connect|shell|stop|health|status}; rcu update <source>; rcu rollback; rcu uninstall."
rcu_user 'If rcu is not visible in this shell, open a new macOS terminal or source ~/.zshrc yourself.'
