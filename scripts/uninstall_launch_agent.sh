#!/bin/zsh
set -euo pipefail

AGENT_ID_PREFIX="com.wendy.codex-signal-glance"
LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"
APP_HOME_PREFIX="$HOME/.codex-signal-glance"
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

  grep -q "CodexSignalGlance" "$plist" 2>/dev/null && grep -q ".codex-signal-glance" "$plist" 2>/dev/null
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
  echo "No Codex Quota Widget LaunchAgents found."
else
  for plist in "${plists[@]}"; do
    label="$(plist_label "$plist")"
    program="$(plist_program "$plist")"

    launchctl bootout "$DOMAIN/$label" >/dev/null 2>&1 || true
    launchctl bootout "$DOMAIN" "$plist" >/dev/null 2>&1 || true
    launchctl unload "$plist" >/dev/null 2>&1 || true

    rm -f "$plist"
    echo "Removed LaunchAgent: $plist"

    if [[ "$program" == "$APP_HOME_PREFIX"* && "$(basename "$program")" == "CodexSignalGlance" ]]; then
      rm -f "$program"
      rmdir "$(dirname "$program")" >/dev/null 2>&1 || true
      rmdir "$(dirname "$(dirname "$program")")" >/dev/null 2>&1 || true
    fi
  done
fi

for app_home in "$APP_HOME_PREFIX"*(N-/); do
  rm -rf "$app_home"
  echo "Removed install directory: $app_home"
done

pkill -f "$APP_HOME_PREFIX.*/CodexSignalGlance" >/dev/null 2>&1 || true
