#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
OUTPUT_DIR="$ROOT_DIR/build/release/helper"
CONFIGURATION="release"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --output-dir)
      OUTPUT_DIR="$2"
      shift 2
      ;;
    --configuration)
      CONFIGURATION="$2"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

mkdir -p "$OUTPUT_DIR"

swift build --package-path "$ROOT_DIR" -c "$CONFIGURATION" --product lookin-mcp

SOURCE_BINARY="$ROOT_DIR/.build/$CONFIGURATION/lookin-mcp"
TARGET_BINARY="$OUTPUT_DIR/lookin-mcp"

if [[ ! -f "$SOURCE_BINARY" ]]; then
  echo "Missing built helper: $SOURCE_BINARY" >&2
  exit 1
fi

cp "$SOURCE_BINARY" "$TARGET_BINARY"
chmod 755 "$TARGET_BINARY"

echo "$TARGET_BINARY"
