#!/usr/bin/env bash
# Thin wrapper around verify_receipt() for direct CLI invocation.
# Exit 0 on pass, 1 on missing receipt, 2 on usage error.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/receipt.sh
source "$HERE/lib/receipt.sh"

verify_receipt "${1:-}"
