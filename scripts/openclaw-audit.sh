#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/openclaw-common.sh"

load_openclaw_env
openclaw config validate
openclaw doctor
openclaw security audit --deep
openclaw sandbox explain
