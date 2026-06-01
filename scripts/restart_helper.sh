#!/bin/zsh
set -euo pipefail

AGENT_ID="com.wendy.codex-signal-glance"
PLIST_PATH="$HOME/Library/LaunchAgents/$AGENT_ID.plist"
INSTALL_BIN="$HOME/.codex-quota-widget/bin/CodexSignalGlance"
UID_VALUE="$(id -u)"
DOMAIN="gui/$UID_VALUE"
SERVICE="$DOMAIN/$AGENT_ID"

if [[ ! -f "$PLIST_PATH" ]]; then
  echo "LaunchAgent plist not found: $PLIST_PATH"
  echo "Run scripts/install_launch_agent.sh first."
  exit 1
fi

launchctl bootout "$SERVICE" >/dev/null 2>&1 || true

if ! launchctl bootstrap "$DOMAIN" "$PLIST_PATH" >/dev/null 2>&1; then
  launchctl unload "$PLIST_PATH" >/dev/null 2>&1 || true
  launchctl load "$PLIST_PATH" >/dev/null 2>&1 || true
fi

launchctl enable "$SERVICE" >/dev/null 2>&1 || true
launchctl kickstart -k "$SERVICE" >/dev/null 2>&1 || launchctl kickstart "$SERVICE" >/dev/null 2>&1 || true

if pgrep -af "$INSTALL_BIN" >/dev/null 2>&1; then
  echo "Helper restarted."
  exit 0
fi

if [[ -x "$INSTALL_BIN" ]]; then
  nohup "$INSTALL_BIN" >/tmp/codex-signal-glance.log 2>&1 &
fi

sleep 1
if pgrep -af "$INSTALL_BIN" >/dev/null 2>&1; then
  echo "Helper started via fallback run."
else
  echo "Failed to start helper. Check logs:"
  echo "  $HOME/.codex-quota-widget/launch-agent.err.log"
  echo "  /tmp/codex-signal-glance.log"
  exit 1
fi
