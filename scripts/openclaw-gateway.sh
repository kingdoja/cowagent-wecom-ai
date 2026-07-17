#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/openclaw-common.sh"

action="${1:-status}"
case "$action" in
  install)
    "$ROOT_DIR/scripts/openclaw-preflight.sh"
    openclaw gateway install
    openclaw gateway start
    ;;
  start|stop|restart|status|uninstall)
    openclaw gateway "$action"
    ;;
  *)
    echo "Usage: $0 [install|start|stop|restart|status|uninstall]" >&2
    exit 2
    ;;
esac
