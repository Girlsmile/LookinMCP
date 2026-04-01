#!/bin/bash

set -euo pipefail

APP_PATH=""
SKIP_CODESIGN=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --app)
      APP_PATH="$2"
      shift 2
      ;;
    --skip-codesign)
      SKIP_CODESIGN=1
      shift
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

if [[ -z "$APP_PATH" ]]; then
  echo "Usage: $0 --app <Lookin.app>" >&2
  exit 1
fi

HELPER_PATH="$APP_PATH/Contents/PlugIns/lookin-mcp"

if [[ ! -d "$APP_PATH" ]]; then
  echo "App bundle not found: $APP_PATH" >&2
  exit 1
fi

if [[ ! -f "$HELPER_PATH" ]]; then
  echo "Embedded helper missing: $HELPER_PATH" >&2
  exit 1
fi

if [[ ! -x "$HELPER_PATH" ]]; then
  echo "Embedded helper is not executable: $HELPER_PATH" >&2
  exit 1
fi

if [[ "$SKIP_CODESIGN" -eq 0 ]]; then
  codesign --verify --deep --strict "$APP_PATH"
fi

echo "Verified embedded helper: $HELPER_PATH"
