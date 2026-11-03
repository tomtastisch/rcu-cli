#!/bin/bash
# Bootstrap. Installation logic lives in installer/.
set -euo pipefail
root="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
case "${1:-}" in
  --uninstall) shift; exec /bin/bash "$root/installer/uninstall.sh" "$@" ;;
  --rollback) shift; exec /bin/bash "$root/installer/rollback.sh" "$@" ;;
  "") exec /bin/bash "$root/installer/install.sh" "$root" ;;
  *) printf 'Usage: ./install.sh [--uninstall|--rollback]\n' >&2; exit 2 ;;
esac
