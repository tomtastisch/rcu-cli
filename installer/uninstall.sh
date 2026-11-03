#!/bin/bash
# Archive the installation without touching the host profile.
set -euo pipefail
source "$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/common.sh"
rcu_check_platform
rcu_check_base
rcu_check_launcher
rcu_user 'RCU-Installation wird archiviert. Konfiguration und Host-Keys bleiben erhalten.'
archive="$RCU_BASE/archive-$(date +%Y%m%dT%H%M%S)"
mv -f "$RCU_RELEASES" "$archive" 2>/dev/null || true
rm -f "$RCU_CURRENT" "$RCU_PREVIOUS" "$HOME/.local/bin/rcu"
rm -f "$RCU_BASE/.rcu-managed"
rcu_info 'Deinstallation abgeschlossen. Konfiguration unter ~/.config/rcu/ erhalten.'
rcu_user 'Zum Wiederherstellen: rcu aus dem Archiv neu installieren oder git pull + ./install.sh.'
