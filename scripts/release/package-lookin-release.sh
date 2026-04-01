#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

WORKSPACE_PATH="$ROOT_DIR/Lookin/Lookin.xcworkspace"
SCHEME="LookinClient"
CONFIGURATION="Release"
DERIVED_DATA_PATH="$ROOT_DIR/build/release/DerivedData"
OUTPUT_DIR="$ROOT_DIR/build/release/output"
APP_NAME="Lookin"
SKIP_DMG=0
SKIP_NOTARIZE=1
NOTARY_PROFILE="${LOOKIN_NOTARY_PROFILE:-}"
CODESIGN_IDENTITY="${LOOKIN_CODESIGN_IDENTITY:-}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --output-dir)
      OUTPUT_DIR="$2"
      shift 2
      ;;
    --derived-data-path)
      DERIVED_DATA_PATH="$2"
      shift 2
      ;;
    --codesign-identity)
      CODESIGN_IDENTITY="$2"
      shift 2
      ;;
    --notary-profile)
      NOTARY_PROFILE="$2"
      SKIP_NOTARIZE=0
      shift 2
      ;;
    --skip-dmg)
      SKIP_DMG=1
      shift
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

mkdir -p "$OUTPUT_DIR"

HELPER_PATH="$("$SCRIPT_DIR/build-lookin-mcp-release.sh" --output-dir "$OUTPUT_DIR/helper" --configuration release | tail -n 1)"

BUILD_SETTINGS="$(
  xcodebuild \
    -workspace "$WORKSPACE_PATH" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -showBuildSettings 2>/dev/null
)"

TARGET_BUILD_DIR="$(printf '%s\n' "$BUILD_SETTINGS" | sed -n 's/^[[:space:]]*TARGET_BUILD_DIR = //p' | tail -n 1)"
FULL_PRODUCT_NAME="$(printf '%s\n' "$BUILD_SETTINGS" | sed -n 's/^[[:space:]]*FULL_PRODUCT_NAME = //p' | tail -n 1)"

if [[ -z "$TARGET_BUILD_DIR" || -z "$FULL_PRODUCT_NAME" ]]; then
  echo "Unable to resolve Lookin build output path from xcodebuild settings." >&2
  exit 1
fi

xcodebuild \
  -workspace "$WORKSPACE_PATH" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  build

BUILT_APP="$TARGET_BUILD_DIR/$FULL_PRODUCT_NAME"
FINAL_APP="$OUTPUT_DIR/$APP_NAME.app"
DMG_PATH="$OUTPUT_DIR/${APP_NAME}MCP.dmg"

if [[ ! -d "$BUILT_APP" ]]; then
  echo "Built app not found: $BUILT_APP" >&2
  exit 1
fi

rm -rf "$FINAL_APP"
cp -R "$BUILT_APP" "$FINAL_APP"

ASSEMBLE_ARGS=(--app "$FINAL_APP" --helper "$HELPER_PATH")
if [[ -n "$CODESIGN_IDENTITY" ]]; then
  ASSEMBLE_ARGS+=(--codesign-identity "$CODESIGN_IDENTITY")
fi
"$SCRIPT_DIR/assemble-lookin-app.sh" "${ASSEMBLE_ARGS[@]}"

"$SCRIPT_DIR/verify-lookin-release.sh" --app "$FINAL_APP"

if [[ "$SKIP_DMG" -eq 0 ]]; then
  STAGE_DIR="$OUTPUT_DIR/dmg-root"
  rm -rf "$STAGE_DIR"
  mkdir -p "$STAGE_DIR"
  cp -R "$FINAL_APP" "$STAGE_DIR/"
  ln -s /Applications "$STAGE_DIR/Applications"
  rm -f "$DMG_PATH"
  hdiutil create -volname "${APP_NAME}MCP" -srcfolder "$STAGE_DIR" -ov -format UDZO "$DMG_PATH" >/dev/null
fi

if [[ "$SKIP_NOTARIZE" -eq 0 ]]; then
  if [[ -z "$NOTARY_PROFILE" ]]; then
    echo "Notary profile required when notarization is enabled." >&2
    exit 1
  fi
  if [[ "$SKIP_DMG" -eq 0 ]]; then
    xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$DMG_PATH"
  else
    ditto -c -k --keepParent "$FINAL_APP" "$OUTPUT_DIR/$APP_NAME.zip"
    xcrun notarytool submit "$OUTPUT_DIR/$APP_NAME.zip" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$FINAL_APP"
  fi
fi

echo "App: $FINAL_APP"
if [[ "$SKIP_DMG" -eq 0 ]]; then
  echo "DMG: $DMG_PATH"
fi
