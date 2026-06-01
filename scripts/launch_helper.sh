#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BIN="$ROOT_DIR/bin/CodexSignalGlance"

needs_build=0
if [[ ! -x "$BIN" ]]; then
  needs_build=1
elif [[ "$ROOT_DIR/Package.swift" -nt "$BIN" ]]; then
  needs_build=1
elif find "$ROOT_DIR/Sources" -type f -newer "$BIN" | grep -q .; then
  needs_build=1
fi

if [[ "$needs_build" -eq 1 ]]; then
  "$SCRIPT_DIR/build.sh"
fi

exec "$BIN"
