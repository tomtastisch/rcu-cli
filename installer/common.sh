#!/bin/bash
# Paths, ownership guards, and atomic symlink operations shared by lifecycle commands.
set -euo pipefail
umask 077
RCU_BASE="$HOME/.local/share/utm/rcu"
RCU_RELEASES="$RCU_BASE/releases"
RCU_CURRENT="$RCU_BASE/current"
RCU_PREVIOUS="$RCU_BASE/previous"
RCU_LAUNCHER="$HOME/.local/bin/rcu"
RCU_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/rcu"
RCU_ZSHRC="$HOME/.zshrc"
RCU_PATH_MARKER='# rcu-cli: managed PATH'
RCU_PATH_LINE='export PATH="$HOME/.local/bin:$PATH"'

rcu_die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
rcu_info() { printf '%s\n' "$*"; }
rcu_user() {
  if [[ -t 1 ]]; then
    printf '\033[1;33mUSER: %s\033[0m\n' "$*"
  else
    printf 'USER: %s\n' "$*"
  fi
}
rcu_check_platform() {
  [[ "${RCU_TEST:-0}" == 1 || "$(uname -s)" == Darwin ]] || rcu_die 'Install RCU on the macOS host, not inside Debian.'
}
rcu_is_owned_root() {
  [[ -d "$RCU_BASE" && ! -L "$RCU_BASE" && -f "$RCU_BASE/.rcu-managed" && ! -L "$RCU_BASE/.rcu-managed" ]]
}
rcu_owned_release() {
  local target="$1" leaf
  leaf="${target##*/}"
  [[ "$target" == "$RCU_RELEASES/$leaf" && "$leaf" != . && "$leaf" != .. && "$leaf" != *'/'* && -d "$target" && ! -L "$target" && -f "$target/.rcu-managed" ]]
}
rcu_current_target() {
  [[ -L "$RCU_CURRENT" ]] || return 1
  local target
  target="$(readlink "$RCU_CURRENT")"
  rcu_owned_release "$target" || return 1
  printf '%s' "$target"
}
rcu_previous_target() {
  [[ -L "$RCU_PREVIOUS" ]] || return 1
  local target
  target="$(readlink "$RCU_PREVIOUS")"
  rcu_owned_release "$target" || return 1
  printf '%s' "$target"
}
rcu_check_launcher() {
  if [[ -e "$RCU_LAUNCHER" || -L "$RCU_LAUNCHER" ]]; then
    [[ -L "$RCU_LAUNCHER" ]] || rcu_die "Foreign executable exists: $RCU_LAUNCHER"
    [[ "$(readlink "$RCU_LAUNCHER")" == "$RCU_CURRENT/bin/rcu" ]] || rcu_die "Foreign launcher symlink: $RCU_LAUNCHER"
  fi
}
rcu_check_base() {
  if [[ -e "$RCU_BASE" || -L "$RCU_BASE" ]]; then
    rcu_is_owned_root || rcu_die "Existing unowned installation path: $RCU_BASE"
  fi
  if [[ -e "$RCU_CURRENT" || -L "$RCU_CURRENT" ]]; then
    rcu_current_target >/dev/null || rcu_die 'Current link is invalid or points outside the managed releases.'
  fi
  if [[ -e "$RCU_PREVIOUS" || -L "$RCU_PREVIOUS" ]]; then
    rcu_previous_target >/dev/null || rcu_die 'Previous link is invalid or points outside the managed releases.'
  fi
}
# Replace a symlink via one rename on its filesystem. Never follow the destination.
rcu_atomic_link() {
  local destination="$1" target="$2" dir tmp
  dir="$(dirname "$destination")"
  [[ ! -e "$destination" || -L "$destination" ]] || return 1
  tmp="$(mktemp -d "$dir/.rcu-link.XXXXXX")" || return 1
  if ! ln -s "$target" "$tmp/link"; then rmdir "$tmp"; return 1; fi
  if [[ "$(uname -s)" == Darwin ]]; then
    /bin/mv -fh "$tmp/link" "$destination" || return 1
  else
    /bin/mv -fT "$tmp/link" "$destination" || return 1
  fi
  rmdir "$tmp"
}
rcu_check_no_foreign_release() {
  local item
  [[ -d "$RCU_RELEASES" && ! -L "$RCU_RELEASES" ]] || return 1
  for item in "$RCU_RELEASES"/* "$RCU_RELEASES"/.*; do
    [[ -e "$item" || -L "$item" ]] || continue
    case "${item##*/}" in .|..) continue ;; esac
    rcu_owned_release "$item" || return 1
  done
  for item in "$RCU_BASE"/* "$RCU_BASE"/.*; do
    [[ -e "$item" || -L "$item" ]] || continue
    case "${item##*/}" in .|..|.rcu-managed|releases|current|previous) continue ;; *) return 1 ;; esac
  done
}
