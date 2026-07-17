#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/openclaw-common.sh"

filevault_enabled || die "FileVault must be enabled first"
[[ -f "$ROOT_DIR/openclaw/test-results/READY_FOR_WEIXIN" ]] \
  || die "acceptance gates have not produced READY_FOR_WEIXIN"

echo "Scan the next QR code with the SECOND WeChat account only."
openclaw channels login --channel openclaw-weixin
openclaw gateway restart
