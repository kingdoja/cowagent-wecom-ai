#!/usr/bin/env bash
set -euo pipefail

config_path="${COW_DATA_DIR:-/home/agent/cow}/config.json"
python /opt/cowagent/init_config.py "$config_path" /app/config-template.json

exec python /opt/cowagent/run_cowagent.py
