#!/usr/bin/env bash
#
# make-release.sh — build a Release-configuration Tidy.app and zip it,
# mirroring what .github/workflows/release.yml does. Useful for a local
# test build before tagging, or for producing an unsigned build by hand.
#
# Usage: scripts/make-release.sh [version]
#   version defaults to the most recent git tag, or "dev" if there is none.
set -euo pipefail

cd "$(dirname "$0")/.."

VERSION="${1:-$(git describe --tags --abbrev=0 2>/dev/null || echo dev)}"

FREE_KB=$(df -k / | awk 'NR==2{print $4}')
if [ "$FREE_KB" -lt 5242880 ]; then
  echo "Less than 5 GB free on / — a Release build needs headroom. Free up space first." >&2
  exit 1
fi

echo "Building Tidy $VERSION (Release)…"

if command -v xcodegen >/dev/null 2>&1; then
  xcodegen generate
fi

xcodebuild -project Tidy.xcodeproj -scheme Tidy -configuration Release \
  -derivedDataPath ./DerivedData build CODE_SIGNING_ALLOWED=NO

APP_PATH="DerivedData/Build/Products/Release/Tidy.app"
codesign -s - --force --deep "$APP_PATH"

mkdir -p dist
ZIP_PATH="dist/Tidy-$VERSION.zip"
rm -f "$ZIP_PATH"
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"

echo
echo "Built unsigned $ZIP_PATH"
echo "This is ad-hoc signed (not notarized). To open it locally:"
echo "  xattr -dr com.apple.quarantine \"$APP_PATH\""
echo "or right-click the app in Finder and choose Open."
