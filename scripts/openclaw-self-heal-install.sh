#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/openclaw-common.sh"

label="ai.openclaw.self-heal"
plist="$HOME/Library/LaunchAgents/$label.plist"
log_dir="$HOME/Library/Logs/openclaw"
uid="$(id -u)"

mkdir -p "$log_dir"
chmod 700 "$log_dir"

temporary="$(mktemp "${plist}.tmp.XXXXXX")"
cat > "$temporary" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$label</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>$ROOT_DIR/scripts/openclaw-self-heal-watch.sh</string>
  </array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>ProcessType</key><string>Background</string>
  <key>StandardOutPath</key><string>$log_dir/self-heal-launchd.log</string>
  <key>StandardErrorPath</key><string>$log_dir/self-heal-launchd.log</string>
  <key>EnvironmentVariables</key>
  <dict>
    <key>PATH</key><string>/Applications/Rancher Desktop.app/Contents/Resources/resources/darwin/bin:$HOME/.rd/bin:$HOME/.hermes/node/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
  </dict>
  <key>Umask</key><integer>63</integer>
</dict>
</plist>
EOF
plutil -lint "$temporary" >/dev/null
chmod 600 "$temporary"
mv "$temporary" "$plist"

launchctl bootout "gui/$uid/$label" >/dev/null 2>&1 || true
launchctl bootstrap "gui/$uid" "$plist"
echo "Installed $label (Gateway failure-event watcher)."
