#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
AGENT_ID="com.wendy.codex-signal-glance"
PLIST_PATH="$HOME/Library/LaunchAgents/$AGENT_ID.plist"
APP_HOME="$HOME/.codex-signal-glance"
INSTALL_BIN="$APP_HOME/bin/CodexSignalGlance"
LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"
UID_VALUE="$(id -u)"
DOMAIN="gui/$UID_VALUE"
PLIST_BUDDY="/usr/libexec/PlistBuddy"

plist_label() {
  local plist="$1"
  "$PLIST_BUDDY" -c "Print :Label" "$plist" 2>/dev/null || basename "$plist" .plist
}

plist_program() {
  local plist="$1"
  "$PLIST_BUDDY" -c "Print :ProgramArguments:0" "$plist" 2>/dev/null || true
}

is_widget_plist() {
  local plist="$1"
  local label
  label="$(plist_label "$plist")"

  if [[ "$label" == "$AGENT_ID"* ]]; then
    return 0
  fi

  if [[ "$(basename "$plist")" == *codex-signal-glance*.plist ]]; then
    return 0
  fi

  grep -q "CodexSignalGlance" "$plist" 2>/dev/null && grep -q ".codex-signal-glance" "$plist" 2>/dev/null
}

remove_existing_agents() {
  mkdir -p "$LAUNCH_AGENTS_DIR"

  typeset -A seen_plists
  local plists=()
  local plist label program

  for plist in "$LAUNCH_AGENTS_DIR"/"$AGENT_ID"*.plist(N) "$LAUNCH_AGENTS_DIR"/*codex-signal-glance*.plist(N); do
    [[ -f "$plist" ]] || continue
    is_widget_plist "$plist" || continue
    [[ -n "${seen_plists[$plist]:-}" ]] && continue
    seen_plists[$plist]=1
    plists+=("$plist")
  done

  for plist in "${plists[@]}"; do
    label="$(plist_label "$plist")"
    program="$(plist_program "$plist")"

    launchctl bootout "$DOMAIN/$label" >/dev/null 2>&1 || true
    launchctl bootout "$DOMAIN" "$plist" >/dev/null 2>&1 || true
    launchctl unload "$plist" >/dev/null 2>&1 || true

    if [[ "$program" == "$APP_HOME"* && "$(basename "$program")" == "CodexSignalGlance" ]]; then
      pkill -f "$program" >/dev/null 2>&1 || true
    fi

    rm -f "$plist"
  done

  pkill -f "$APP_HOME.*/CodexSignalGlance" >/dev/null 2>&1 || true
}

"$SCRIPT_DIR/build.sh"
remove_existing_agents
mkdir -p "$APP_HOME/bin"
cp "$ROOT_DIR/bin/CodexSignalGlance" "$INSTALL_BIN"
chmod +x "$INSTALL_BIN"
mkdir -p "$LAUNCH_AGENTS_DIR"

cat > "$PLIST_PATH" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$AGENT_ID</string>
  <key>ProgramArguments</key>
  <array>
    <string>$INSTALL_BIN</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>ProcessType</key>
  <string>Interactive</string>
  <key>StandardOutPath</key>
  <string>$APP_HOME/launch-agent.log</string>
  <key>StandardErrorPath</key>
  <string>$APP_HOME/launch-agent.err.log</string>
</dict>
</plist>
EOF

"$SCRIPT_DIR/restart_helper.sh"

echo "Installed LaunchAgent at $PLIST_PATH"
echo "Installed binary at $INSTALL_BIN"
