#!/bin/bash
# installer/bootstrap.sh — One-shot bootstrap that validates and runs install.sh.
# Usage: ./bootstrap.sh

set -euo pipefail

# shellcheck disable=SC1007
SRC_ROOT=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
exec "$SRC_ROOT/installer/install.sh" "$@"
