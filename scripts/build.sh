#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BIN_DIR="$ROOT_DIR/bin"
TARGET_BIN="$BIN_DIR/CodexSignalGlance"
BUILD_CACHE="$ROOT_DIR/.build-cache"

mkdir -p "$BIN_DIR"
mkdir -p "$BUILD_CACHE/clang/ModuleCache"

export CLANG_MODULE_CACHE_PATH="$BUILD_CACHE/clang/ModuleCache"

source_files=("$ROOT_DIR"/Sources/CodexSignalGlance/*.swift)
source_files=("${source_files[@]:#"$ROOT_DIR"/Sources/CodexSignalGlance/TouchBarController.swift}")

swiftc \
  -module-name CodexSignalGlance \
  -o "$TARGET_BIN" \
  "${source_files[@]}" \
  -framework AppKit

chmod +x "$TARGET_BIN"

echo "Built $TARGET_BIN"
