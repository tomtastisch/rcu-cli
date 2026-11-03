#!/bin/bash
# Shared installer helpers — never modify user data outside the RCU tree.
rcu_die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
rcu_info() { printf '%s\n' "$*"; }
rcu_user() {
  if [[ -t 2 && -z "${NO_COLOR:-}" ]]; then printf '\033[33m%s\033[0m\n' "$*" >&2; else printf '%s\n' "$*" >&2; fi
}
rcu_check_platform() {
  [[ "$(uname -s)" == Darwin ]] || rcu_die 'RCU runs on macOS, not inside the guest VM.'
}
RCU_BASE="${HOME}/.local/share/utm/rcu"
RCU_RELEASES="$RCU_BASE/releases"
RCU_CURRENT="$RCU_BASE/current"
RCU_PREVIOUS="$RCU_BASE/previous"
RCU_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/rcu"
RCU_ZSHRC="$HOME/.zshrc"
rcu_check_base() {
  [[ ! -L "$RCU_BASE" ]] || rcu_die 'Refusing symlinked RCU base.'
  mkdir -p "$RCU_BASE"
}
rcu_check_launcher() {
  local launcher="$HOME/.local/bin/rcu"
  [[ ! -e "$launcher" ]] && { mkdir -p "$HOME/.local/bin"; ln -sfn "$RCU_CURRENT/bin/rcu" "$launcher"; }
  [[ -L "$launcher" ]] || rcu_die "$launcher exists but is not a symlink. Remove it and retry."
}
rcu_current_target() {
  [[ -L "$RCU_CURRENT" ]] && { local t; t="$(readlink "$RCU_CURRENT")"; [[ -d "$t" ]] && printf '%s\n' "$t"; }
  return 1
}
rcu_previous_target() {
  [[ -L "$RCU_PREVIOUS" ]] && { local t; t="$(readlink "$RCU_PREVIOUS")"; [[ -d "$t" ]] && printf '%s\n' "$t"; }
  return 1
}
rcu_atomic_link() {
  local name="$1" target="$2" tmp
  tmp="${name}.tmp.$$"
  ln -sfn "$target" "$tmp"
  mv -f "$tmp" "$name"
}
