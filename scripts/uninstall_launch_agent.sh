#!/bin/zsh
set -euo pipefail

AGENT_ID_PREFIX="com.wendy.codex-signal-glance"
LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"
APP_HOME_PREFIXES=(
  "$HOME/.codex-quota-widget"
  "$HOME/.codex-signal-glance"
)
APP_BUNDLES=(
  "$HOME/Applications/Codex Signal Glance.app"
  "$HOME/.codex-signal-glance/CodexSignalGlance.app"
)
LOGIN_ITEM_NAMES=(
  "Codex Signal Glance"
  "CodexSignalGlance"
)
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

  if [[ "$label" == "$AGENT_ID_PREFIX"* ]]; then
    return 0
  fi

  if [[ "$(basename "$plist")" == *codex-signal-glance*.plist ]]; then
    return 0
  fi

  grep -q "CodexSignalGlance" "$plist" 2>/dev/null \
    && { grep -q ".codex-quota-widget" "$plist" 2>/dev/null || grep -q ".codex-signal-glance" "$plist" 2>/dev/null || grep -q "Codex Signal Glance.app" "$plist" 2>/dev/null; }
}

remove_login_items() {
  local name app

  for name in "${LOGIN_ITEM_NAMES[@]}"; do
    osascript <<EOF >/dev/null 2>&1 || true
tell application "System Events"
  if exists login item "$name" then
    delete login item "$name"
  end if
end tell
EOF
  done

  for app in "${APP_BUNDLES[@]}"; do
    osascript <<EOF >/dev/null 2>&1 || true
tell application "System Events"
  repeat with itemRef in (get login items)
    if (path of itemRef is "$app") then
      delete itemRef
    end if
  end repeat
end tell
EOF
  done
}

typeset -A seen_plists
plists=()
for plist in "$LAUNCH_AGENTS_DIR"/"$AGENT_ID_PREFIX"*.plist(N) "$LAUNCH_AGENTS_DIR"/*codex-signal-glance*.plist(N); do
  [[ -f "$plist" ]] || continue
  is_widget_plist "$plist" || continue
  [[ -n "${seen_plists[$plist]:-}" ]] && continue
  seen_plists[$plist]=1
  plists+=("$plist")
done

if [[ ${#plists[@]} -eq 0 ]]; then
  echo "No Codex Signal Glance LaunchAgents found."
else
  for plist in "${plists[@]}"; do
    label="$(plist_label "$plist")"
    program="$(plist_program "$plist")"

    launchctl bootout "$DOMAIN/$label" >/dev/null 2>&1 || true
    launchctl bootout "$DOMAIN" "$plist" >/dev/null 2>&1 || true
    launchctl unload "$plist" >/dev/null 2>&1 || true

    if [[ -n "$program" && "$(basename "$program")" == "CodexSignalGlance" ]]; then
      pkill -f "$program" >/dev/null 2>&1 || true
    fi

    rm -f "$plist"
    echo "Removed LaunchAgent: $plist"
  done
fi

remove_login_items

# Also stop local development/manual launches, for example:
#   launch.command -> scripts/run_local.sh -> bin/CodexSignalGlance
# Those processes are not managed by LaunchAgent and do not live under the
# install directory, so path-based cleanup above will not find them.
pkill -x "CodexSignalGlance" >/dev/null 2>&1 || true
pkill -f "/bin/CodexSignalGlance" >/dev/null 2>&1 || true

for app in "${APP_BUNDLES[@]}"; do
  pkill -f "$app/Contents/MacOS/CodexSignalGlance" >/dev/null 2>&1 || true
  if [[ -d "$app" ]]; then
    rm -rf "$app"
    echo "Removed app: $app"
  fi
done

for app_home in "${APP_HOME_PREFIXES[@]}"; do
  pkill -f "$app_home.*/CodexSignalGlance" >/dev/null 2>&1 || true
  if [[ -d "$app_home" ]]; then
    rm -rf "$app_home"
    echo "Removed install directory: $app_home"
  fi
done

echo "Uninstalled Codex Signal Glance."
