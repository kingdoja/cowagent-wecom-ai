#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/openclaw-common.sh"
load_openclaw_env

action="${1:-status}"
case "$action" in
  install)
    rm -f "$OPENCLAW_HOME/agents/main/agent/models.json"
    "$ROOT_DIR/scripts/openclaw-preflight.sh"
    openclaw gateway install --force --wrapper "$ROOT_DIR/scripts/openclaw-gateway-wrapper.sh"
    openclaw gateway start
    wait_and_scrub_openclaw_models_snapshot
    ;;
  restart)
    rm -f "$OPENCLAW_HOME/agents/main/agent/models.json"
    # Refresh launchd's managed environment after credential or provider changes.
    openclaw gateway install --force --wrapper "$ROOT_DIR/scripts/openclaw-gateway-wrapper.sh"
    openclaw gateway "$action"
    wait_and_scrub_openclaw_models_snapshot
    ;;
  start)
    scrub_openclaw_models_snapshot
    openclaw gateway "$action"
    wait_and_scrub_openclaw_models_snapshot
    ;;
  stop|status|uninstall)
    openclaw gateway "$action"
    ;;
  *)
    echo "Usage: $0 [install|start|stop|restart|status|uninstall]" >&2
    exit 2
    ;;
esac
