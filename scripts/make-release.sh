#!/usr/bin/env bash
#
# make-release.sh: build a Release-configuration Tidy.app and zip it,
# mirroring what .github/workflows/release.yml does. Useful for a local
# test build before tagging, or for producing an unsigned build by hand.
#
# Usage: scripts/make-release.sh [version]
#   version defaults to the most recent git tag, or "dev" if there is none.
set -euo pipefail

cd "$(dirname "$0")/.."

VERSION="${1:-$(git describe --tags --abbrev=0 2>/dev/null || echo dev)}"

if [[ ! "$VERSION" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; then
  echo "Version must contain only letters, digits, dots, underscores or hyphens." >&2
  exit 1
fi

FREE_KB=$(df -k / | awk 'NR==2{print $4}')
if [ "$FREE_KB" -lt 5242880 ]; then
  echo "Less than 5 GB free on /: a Release build needs headroom. Free up space first." >&2
  exit 1
fi

echo "Building Tidy $VERSION (Release)…"

if command -v xcodegen >/dev/null 2>&1; then
  xcodegen generate
fi

xcodebuild -project Tidy.xcodeproj -scheme Tidy -configuration Release \
  -derivedDataPath ./DerivedData build CODE_SIGNING_ALLOWED=NO \
  'ARCHS=arm64 x86_64' ONLY_ACTIVE_ARCH=NO

APP_PATH="DerivedData/Build/Products/Release/Tidy.app"
APP_VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist")
APP_BUILD=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP_PATH/Contents/Info.plist")
if [[ "$VERSION" != "dev" && "${VERSION#v}" != "$APP_VERSION" ]]; then
  echo "Artifact version does not match the built app version." >&2
  exit 1
fi
[[ "$APP_BUILD" =~ ^[1-9][0-9]*$ ]] || exit 1
lipo -verify_arch arm64 x86_64 "$APP_PATH/Contents/MacOS/Tidy"
codesign -s - --force --deep "$APP_PATH"

mkdir -p dist
ZIP_PATH="dist/Tidy-$VERSION.zip"
rm -f "$ZIP_PATH"
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"

DMG_PATH="dist/Tidy-$VERSION.dmg"
rm -f "$DMG_PATH"
STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT
cp -R "$APP_PATH" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname "Tidy" -srcfolder "$STAGING" -fs HFS+ -format UDZO -ov "$DMG_PATH"

echo
echo "Built unsigned $ZIP_PATH and $DMG_PATH"
(cd dist && shasum -a 256 "Tidy-$VERSION.zip" "Tidy-$VERSION.dmg" > "Tidy-$VERSION.sha256")
echo "Ad-hoc signed, not notarized. Verify the artifact checksum before installing."
echo "For a trusted artifact, use the per-app procedure in docs/UNSIGNED_INSTALL.md."
echo "Building packages does not establish release acceptance; no publication was performed."
