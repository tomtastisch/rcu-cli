#!/bin/bash
set -euo pipefail
[[ "$(uname -s)" == Darwin ]] || { printf 'USER: Run installer on macOS host.\n' >&2; exit 1; }
root=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
prefix="$HOME/.local/share/rcu"
link="$HOME/.local/bin/rcu"
conf_dir="${XDG_CONFIG_HOME:-$HOME/.config}/rcu"
zshrc="$HOME/.zshrc"
marker='# rcu-cli: managed PATH'
msg() { if [[ -t 1 ]] && command -v gum >/dev/null 2>&1; then gum style --foreground 39 "$*"; else printf '%s\n' "$*"; fi; }
fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
if [[ "${1:-}" == --uninstall ]]; then
  if [[ -L "$link" && "$(readlink "$link")" == "$prefix/bin/rcu" ]]; then unlink "$link"; fi
  if [[ -f "$zshrc" ]] && grep -Fxq "$marker" "$zshrc"; then
    tmp=$(mktemp "$HOME/.zshrc.rcu.XXXXXX") || exit 1
    awk -v m="$marker" '$0==m {skip=1;next} skip==1 {skip=0;next} {print}' "$zshrc" > "$tmp"
    chmod 600 "$tmp"; mv "$tmp" "$zshrc"
  fi
  msg 'Removed rcu link/PATH block; local configuration and data preserved.'; exit 0
fi
[[ $# -eq 0 ]] || fail 'Use ./install.sh or ./install.sh --uninstall'
[[ -d /Applications/UTM.app && -x /Applications/UTM.app/Contents/MacOS/utmctl ]] || fail 'UTM installation missing: install UTM first; existing VM will not be modified.'
msg 'UTM found.'
if ! command -v brew >/dev/null 2>&1; then
  msg 'USER: Homebrew is missing; the official Homebrew installer may ask for your macOS password. Follow its prompts.'
  NONINTERACTIVE=0 /bin/bash -c "$(/usr/bin/curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || fail 'Homebrew installation failed'
  for brew_path in /opt/homebrew/bin/brew /usr/local/bin/brew; do
    if [[ -x "$brew_path" ]]; then eval "$("$brew_path" shellenv)"; break; fi
  done
fi
command -v brew >/dev/null 2>&1 || fail 'Homebrew unavailable'
if ! command -v gum >/dev/null 2>&1; then
  msg 'Installing gum via Homebrew'; brew install gum || fail 'gum installation failed'
fi
[[ ! -e "$link" && ! -L "$link" || "$(readlink "$link" 2>/dev/null || :)" == "$prefix/bin/rcu" ]] || fail "Command collision: $link"
[[ ! -e "$prefix" ]] || { [[ -f "$prefix/.rcu-managed" ]] || fail "Directory collision: $prefix"; }
# Preserve existing installation until checks pass.
for p in bin/rcu lib/core.sh lib/backends/utm.sh config/config.example; do [[ -f "$root/$p" ]] || fail "Missing package file: $p"; done
/bin/bash -n "$root/bin/rcu" "$root/lib/core.sh" "$root/lib/backends/utm.sh" || fail 'Bash syntax validation failed'
mkdir -p "$HOME/.local/bin" "$HOME/.local/share" "$conf_dir"
work=$(mktemp -d "$HOME/.local/share/.rcu-stage.XXXXXX")
trap 'rm -rf "$work"' EXIT
cp -R "$root/bin" "$root/lib" "$work/"
touch "$work/.rcu-managed"
if [[ -d "$prefix" ]]; then mv "$prefix" "$prefix.backup.$(date +%Y%m%d%H%M%S)"; fi
mv "$work" "$prefix"
trap - EXIT
if [[ ! -f "$conf_dir/config" ]]; then
  cp "$root/config/config.example" "$conf_dir/config"; chmod 600 "$conf_dir/config"
fi
if [[ ! -L "$link" ]]; then ln -s "$prefix/bin/rcu" "$link"; fi
if [[ ! -f "$zshrc" ]] || ! grep -Fxq "$marker" "$zshrc"; then
  printf '\n%s\n%s\n' "$marker" 'export PATH="$HOME/.local/bin:$PATH"' >> "$zshrc"
fi
msg 'rcu installed. Open a new macOS terminal or run: source ~/.zshrc'
msg 'Commands: rcu utm start | connect | shell | stop | health | status'
msg 'Only real checks are counted as percentage milestones; not guest boot progress.'
