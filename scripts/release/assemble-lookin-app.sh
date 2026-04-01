#!/bin/bash

set -euo pipefail

APP_PATH=""
HELPER_PATH=""
SKIP_CODESIGN=0
SKIP_VERIFY=0
CODESIGN_IDENTITY="${LOOKIN_CODESIGN_IDENTITY:-}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --app)
      APP_PATH="$2"
      shift 2
      ;;
    --helper)
      HELPER_PATH="$2"
      shift 2
      ;;
    --codesign-identity)
      CODESIGN_IDENTITY="$2"
      shift 2
      ;;
    --skip-codesign)
      SKIP_CODESIGN=1
      shift
      ;;
    --skip-verify)
      SKIP_VERIFY=1
      shift
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

if [[ -z "$APP_PATH" || -z "$HELPER_PATH" ]]; then
  echo "Usage: $0 --app <Lookin.app> --helper <lookin-mcp>" >&2
  exit 1
fi

if [[ ! -d "$APP_PATH" ]]; then
  echo "App bundle not found: $APP_PATH" >&2
  exit 1
fi

if [[ ! -f "$HELPER_PATH" ]]; then
  echo "Helper not found: $HELPER_PATH" >&2
  exit 1
fi

PLUGINS_DIR="$APP_PATH/Contents/PlugIns"
EMBEDDED_HELPER="$PLUGINS_DIR/lookin-mcp"

mkdir -p "$PLUGINS_DIR"
cp "$HELPER_PATH" "$EMBEDDED_HELPER"
chmod 755 "$EMBEDDED_HELPER"

if [[ "$SKIP_CODESIGN" -eq 0 ]]; then
  SIGN_IDENTITY="${CODESIGN_IDENTITY:--}"
  CODESIGN_ARGS=(--force --sign "$SIGN_IDENTITY" --timestamp=none)
  if [[ "$SIGN_IDENTITY" != "-" ]]; then
    CODESIGN_ARGS+=(--options runtime)
  fi

  xattr -cr "$APP_PATH" || true
  codesign "${CODESIGN_ARGS[@]}" "$EMBEDDED_HELPER"
  codesign "${CODESIGN_ARGS[@]}" --deep "$APP_PATH"
fi

if [[ "$SKIP_VERIFY" -eq 0 ]]; then
  "$(cd "$(dirname "$0")" && pwd)/verify-lookin-release.sh" --app "$APP_PATH" $([[ "$SKIP_CODESIGN" -eq 1 ]] && echo "--skip-codesign")
fi

echo "$EMBEDDED_HELPER"
