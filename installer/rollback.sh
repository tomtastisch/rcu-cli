#!/bin/bash
# Switch back to the previous verified release; do not remove any files.
set -euo pipefail
source "$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/common.sh"
rcu_check_platform
rcu_check_base
rcu_check_launcher
current="$(rcu_current_target)" || rcu_die 'No valid current release.'
previous="$(rcu_previous_target)" || rcu_die 'No previous release available.'
for file in bin/rcu lib/core.sh lib/backends/utm.sh installer/common.sh installer/install.sh installer/uninstall.sh installer/rollback.sh; do
  [[ -f "$previous/$file" ]] || rcu_die "Previous release incomplete: $file"
  case "$file" in *.sh|bin/rcu) /bin/bash -n "$previous/$file" || rcu_die "Previous release syntax invalid: $file" ;; esac
done
rcu_atomic_link "$RCU_CURRENT" "$previous" || rcu_die 'Cannot activate previous release.'
rcu_atomic_link "$RCU_PREVIOUS" "$current" || rcu_die 'Rolled back, but could not record former current release.'
rcu_info "RCU rolled back to ${previous##*/}; former release retained."
