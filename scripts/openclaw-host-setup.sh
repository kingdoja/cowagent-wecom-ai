#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/openclaw-common.sh"

case "${1:-status}" in
  status)
    fdesetup status
    pmset -g custom
    ;;
  power)
    sudo pmset -c sleep 0 displaysleep 10
    pmset -g custom
    ;;
  *)
    echo "Usage: $0 [status|power]" >&2
    exit 2
    ;;
esac
