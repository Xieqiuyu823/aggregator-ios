#!/usr/bin/env bash
# Run on macOS with Xcode. This produces an unsigned IPA for later re-signing.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build"
ARCHIVE_PATH="$BUILD_DIR/AggregatorApp.xcarchive"
APP_PATH="$ARCHIVE_PATH/Products/Applications/AggregatorApp.app"
IPA_DIR="$BUILD_DIR/ipa"
IPA_PATH="$IPA_DIR/AggregatorApp-unsigned.ipa"

cd "$ROOT_DIR"
mkdir -p "$BUILD_DIR"
rm -rf "$ARCHIVE_PATH" "$IPA_DIR"

xcodebuild archive \
  -project AggregatorApp.xcodeproj \
  -scheme AggregatorApp \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE_PATH" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY= \
  DEVELOPMENT_TEAM= \
  PROVISIONING_PROFILE_SPECIFIER=

if [[ ! -d "$APP_PATH" || ! -f "$APP_PATH/AggregatorApp" || ! -f "$APP_PATH/Info.plist" ]]; then
  echo 'Archive does not contain the expected app, executable, and Info.plist.' >&2
  exit 1
fi
if [[ -n "$(find "$APP_PATH" \( -name _CodeSignature -o -name embedded.mobileprovision \) -print -quit)" ]]; then
  echo 'Archive contains a code signature or provisioning profile.' >&2
  exit 1
fi
lipo "$APP_PATH/AggregatorApp" -verify_arch arm64
/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP_PATH/Info.plist"

# A launch screen declaration opts the app into the device's full screen size.
if ! /usr/libexec/PlistBuddy -c 'Print :UILaunchScreen' "$APP_PATH/Info.plist" >/dev/null 2>&1; then
  echo 'Archive is missing the UILaunchScreen declaration.' >&2
  exit 1
fi
if [[ ! -f "$APP_PATH/Assets.car" ]]; then
  echo 'Archive is missing the compiled asset catalog.' >&2
  exit 1
fi
ICON_NAME=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIcons:CFBundlePrimaryIcon:CFBundleIconName' "$APP_PATH/Info.plist")
if [[ "$ICON_NAME" != 'AppIcon' ]]; then
  echo "Unexpected primary app icon: $ICON_NAME" >&2
  exit 1
fi
ASSET_INFO="$BUILD_DIR/asset-info.json"
assetutil --info "$APP_PATH/Assets.car" > "$ASSET_INFO"
if ! grep -q 'AppIcon' "$ASSET_INFO"; then
  echo 'Compiled asset catalog does not contain AppIcon.' >&2
  exit 1
fi

mkdir -p "$IPA_DIR/Payload"
cp -R "$APP_PATH" "$IPA_DIR/Payload/"
(cd "$IPA_DIR" && zip -qry "$(basename "$IPA_PATH")" Payload)
unzip -tq "$IPA_PATH"
shasum -a 256 "$IPA_PATH"
echo "Unsigned IPA: $IPA_PATH"
