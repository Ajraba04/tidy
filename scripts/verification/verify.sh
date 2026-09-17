#!/usr/bin/env bash
# Deterministic correctness/build gates. Physical performance and human AT stay separate.
set -euo pipefail
cd "$(dirname "$0")/../.."
EVIDENCE="${TIDY_VERIFICATION_OUTPUT:-$PWD/dist/verification}"
mkdir -p "$EVIDENCE"
EVIDENCE="$(cd "$EVIDENCE" && pwd -P)"
{
  xcodebuild -version
  swift --version
  xcodegen --version
  sw_vers
  uname -m
  git rev-parse HEAD
} > "$EVIDENCE/toolchain.txt"
python3 scripts/verification/check-project.py
python3 scripts/verification/check-personal-data.py --self-test
python3 scripts/verification/check-personal-data.py
(
  cd TidyCore
  swift test --scratch-path "$EVIDENCE/core-build" --jobs 2 --no-parallel
) 2>&1 | tee "$EVIDENCE/core.log"
python3 scripts/verification/check-test-results.py swift "$EVIDENCE/core.log" --minimum 623
xcodebuild -project Tidy.xcodeproj -scheme TidyAppModelTests -configuration Debug \
  -destination "platform=macOS,arch=$(uname -m)" -jobs 2 \
  -derivedDataPath "$EVIDENCE/models-build" -resultBundlePath "$EVIDENCE/models.xcresult" \
  test CODE_SIGNING_ALLOWED=NO 2>&1 | tee "$EVIDENCE/models.log"
python3 scripts/verification/check-test-results.py xcode "$EVIDENCE/models.xcresult" --minimum 119
xcodebuild -project Tidy.xcodeproj -scheme TidyNativeUITests -configuration Debug \
  -destination "platform=macOS,arch=$(uname -m)" -jobs 2 \
  -derivedDataPath "$EVIDENCE/ui-build" -resultBundlePath "$EVIDENCE/native-ui.xcresult" \
  test CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES 2>&1 | tee "$EVIDENCE/native-ui.log"
python3 scripts/verification/check-test-results.py xcode "$EVIDENCE/native-ui.xcresult" --minimum 1
xcodebuild -project Tidy.xcodeproj -scheme Tidy -configuration Release -jobs 2 \
  -derivedDataPath "$EVIDENCE/release-build" build \
  CODE_SIGNING_ALLOWED=NO 'ARCHS=arm64 x86_64' ONLY_ACTIVE_ARCH=NO \
  2>&1 | tee "$EVIDENCE/release.log"
APP="$EVIDENCE/release-build/Build/Products/Release/Tidy.app"
lipo -verify_arch arm64 x86_64 "$APP/Contents/MacOS/Tidy"
plutil -lint "$APP/Contents/Resources/PrivacyInfo.xcprivacy"
shasum -a 256 "$APP/Contents/MacOS/Tidy" > "$EVIDENCE/executable.sha256"
