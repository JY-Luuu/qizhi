#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/Qizhi.app"
if [[ ! -d "$APP" ]]; then
  bash scripts/build-app.sh release
fi

VERSION="$(plutil -extract CFBundleShortVersionString raw "$APP/Contents/Info.plist")"
RELEASES="build/releases"
DMG="$RELEASES/Qizhi.dmg"
ZIP="$RELEASES/Qizhi.zip"
STAGING="$(mktemp -d "${TMPDIR:-/tmp}/Qizhi-dmg.XXXXXX")"

cleanup() {
  /usr/bin/python3 - "$STAGING" <<'PY'
import shutil, sys
shutil.rmtree(sys.argv[1], ignore_errors=True)
PY
}
trap cleanup EXIT

mkdir -p "$RELEASES"
cp -R "$APP" "$STAGING/Qizhi.app"
# A synced source folder may attach Finder metadata after signing. Remove only
# signing-invalid attributes from the isolated distribution copy, then verify it.
xattr -dr com.apple.FinderInfo "$STAGING/Qizhi.app" 2>/dev/null || true
xattr -dr com.apple.ResourceFork "$STAGING/Qizhi.app" 2>/dev/null || true
codesign --verify --deep --strict "$STAGING/Qizhi.app"
ln -s /Applications "$STAGING/Applications"

ditto -c -k --sequesterRsrc --keepParent "$STAGING/Qizhi.app" "$ZIP"
hdiutil create -quiet -ov -format UDZO -volname "栖纸 Qizhi $VERSION" \
  -srcfolder "$STAGING" "$DMG"

shasum -a 256 "$DMG" "$ZIP"
