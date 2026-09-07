#!/usr/bin/env bash
set -euo pipefail

# launchd starts services with a minimal PATH. Rancher Desktop exposes the
# Docker CLI through Rancher Desktop's CLI directory, which OpenClaw needs
# for agent sandboxes. ~/.rd/bin is kept for normal Rancher installations.
RANCHER_DESKTOP_CLI_DIR="/Applications/Rancher Desktop.app/Contents/Resources/resources/darwin/bin"
export PATH="${RANCHER_DESKTOP_CLI_DIR}:${HOME}/.rd/bin:${PATH:-}"

exec "${HOME}/.hermes/node/bin/node" \
  "${HOME}/.hermes/node/lib/node_modules/openclaw/dist/index.js" \
  "$@"
