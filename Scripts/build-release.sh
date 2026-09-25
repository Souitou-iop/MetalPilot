#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED_DATA="${DERIVED_DATA:-$ROOT/build/DerivedData}"

ARCHS="${ARCHS:-arm64}"

xcodebuild \
  -project "$ROOT/MetalPilot.xcodeproj" \
  -scheme "MetalPilot" \
  -configuration Release \
  -derivedDataPath "$DERIVED_DATA" \
  ARCHS="$ARCHS" \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_ALLOWED=NO \
  build

APP="$DERIVED_DATA/Build/Products/Release/MetalPilot.app"
HELPER="$APP/Contents/Library/LaunchServices/MetalPilotPrivilegedHelper"

# Detect persistent code signing identity
SIGN_IDENTITY="-"
if security find-identity -v -p codesigning 2>/dev/null | grep -q "MacGameToolbox Dev"; then
    SIGN_IDENTITY="MacGameToolbox Dev"
elif security find-identity -v -p codesigning 2>/dev/null | grep -q "Apple Development"; then
    SIGN_IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null | grep "Apple Development" | head -n 1 | awk -F'"' '{print $2}')
fi
echo "==> 使用签名证书: $SIGN_IDENTITY"

xattr -cr "$APP"
xattr -d com.apple.FinderInfo "$APP" 2>/dev/null || true
xattr -d 'com.apple.fileprovider.fpfs#P' "$APP" 2>/dev/null || true
codesign --force --sign "$SIGN_IDENTITY" -i metalpilot.helper "$HELPER"
for attempt in 1 2 3 4 5; do
  xattr -d com.apple.FinderInfo "$APP" 2>/dev/null || true
  xattr -d 'com.apple.fileprovider.fpfs#P' "$APP" 2>/dev/null || true
  if codesign --force --sign "$SIGN_IDENTITY" -i com.iven.macgametoolbox "$APP"; then break; fi
  [[ "$attempt" == 5 ]] && exit 1
  sleep 0.2
done
for attempt in 1 2 3 4 5; do
  xattr -d com.apple.FinderInfo "$APP" 2>/dev/null || true
  xattr -d 'com.apple.fileprovider.fpfs#P' "$APP" 2>/dev/null || true
  if codesign --verify --deep --strict --verbose=2 "$APP"; then break; fi
  [[ "$attempt" == 5 ]] && exit 1
  sleep 0.2
done
echo "$APP"
