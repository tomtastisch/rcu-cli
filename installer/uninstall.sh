#!/bin/bash
# Deactivate only managed RCU artifacts. Archive rather than delete releases.
set -euo pipefail
source "$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/common.sh"
rcu_check_platform
[[ $# -eq 0 ]] || rcu_die 'No purge flags accepted. Configuration/backups are always preserved.'
rcu_check_launcher
if [[ -e "$RCU_BASE" || -L "$RCU_BASE" ]]; then
  rcu_check_base
  rcu_check_no_foreign_release || rcu_die 'Unknown files in installation; refusing uninstall.'
fi
# Validate expected managed block before modifying a user shell file.
if [[ -f "$RCU_ZSHRC" ]] && grep -Fxq "$RCU_PATH_MARKER" "$RCU_ZSHRC"; then
  awk -v m="$RCU_PATH_MARKER" -v v="$RCU_PATH_LINE" '
    $0 == m { if (getline nextline <= 0 || nextline != v) exit 13; next }
  ' "$RCU_ZSHRC" || rcu_die 'Malformed PATH marker; refusing to edit .zshrc.'
fi
if [[ -e "$RCU_BASE" || -L "$RCU_BASE" ]]; then
  archive="$RCU_BASE.uninstalled.$(date +%Y%m%d%H%M%S)"
  [[ ! -e "$archive" ]] || rcu_die 'Archive path collision.'
  mv "$RCU_BASE" "$archive" || rcu_die 'Cannot archive managed installation.'
  rcu_info "RCU release archive: $archive"
fi
if [[ -L "$RCU_LAUNCHER" ]]; then
  unlink "$RCU_LAUNCHER" || rcu_die 'Cannot unlink managed launcher.'
fi
if [[ -f "$RCU_ZSHRC" ]] && grep -Fxq "$RCU_PATH_MARKER" "$RCU_ZSHRC"; then
  tmp="$(mktemp "$HOME/.zshrc.rcu.XXXXXX")"
  awk -v m="$RCU_PATH_MARKER" -v v="$RCU_PATH_LINE" '
    $0 == m { getline nextline; next }
    { print }
  ' "$RCU_ZSHRC" > "$tmp" || rcu_die 'Cannot prepare .zshrc cleanup.'
  chmod 600 "$tmp"
  mv "$tmp" "$RCU_ZSHRC" || rcu_die 'Cannot update .zshrc.'
fi
rcu_info 'RCU launcher removed; previous versions archived; configuration and backups preserved.'
