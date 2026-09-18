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
python3 scripts/verification/check-test-results.py swift "$EVIDENCE/core.log" --minimum 670 \
  --allow-skipped 'registered scan process probes stay within the acknowledged shared process cap' \
  --require-case 'selected-project scope with no acknowledged roots performs zero metadata visits' \
  --require-case 'manual Continue consumes bounded cursors and converges without scope expansion' \
  --require-case 'event after guard consumption invalidates the published cursor at suspension' \
  --require-case 'persisted generation collision after unreliable restart requires a fresh baseline' \
  --require-case 'status drains pending historical catch-up before returning a cached aggregate' \
  --require-case 'failed FSEvents startup stays uncacheable even after a complete fresh walk' \
  --require-case 'long callback paths are rejected before Swift bridging and pending bytes stay bounded' \
  --require-case 'suspension atomically rejects an event after expected-generation capture' \
  --require-case 'an event for an already visited file during manual-Continue idle fails closed'
# This fixture observes a process-global gate and must run in a fresh test
# process. Its opt-in flag is deliberately absent from the aggregate above.
(
  cd TidyCore
  TIDY_ISOLATED_GATE_TESTS=1 swift test --scratch-path "$EVIDENCE/core-build" \
    --jobs 2 --no-parallel --filter CoreOrchestrationTests.registeredScanUsesSharedProcessCap
) 2>&1 | tee "$EVIDENCE/isolated-process-cap.log"
python3 scripts/verification/check-test-results.py swift "$EVIDENCE/isolated-process-cap.log" --minimum 1
xcodebuild -project Tidy.xcodeproj -scheme TidyAppModelTests -configuration Debug \
  -destination "platform=macOS,arch=$(uname -m)" -jobs 2 \
  -derivedDataPath "$EVIDENCE/models-build" -resultBundlePath "$EVIDENCE/models.xcresult" \
  test CODE_SIGNING_ALLOWED=NO 2>&1 | tee "$EVIDENCE/models.log"
python3 scripts/verification/check-test-results.py xcode "$EVIDENCE/models.xcresult" --minimum 130 \
  --require-case 'testRealFSEventsHundredThousandUnchangedScanMatchesFreshAndReducesMetadataVisits' \
  --require-case 'testSelectedProjectsWithoutRootsDoesNotTraverseDocuments' \
  --require-case 'testContinuableTerminalPartialReleasesIdleResourcesAndGapChangeFailsClosed' \
  --require-case 'testFirstIndexedPartialContinueWaitsForSuspensionAndUsesLiveDeviceCheckpoint' \
  --require-case 'testSimultaneousContinueCallersShareOneReservedContinuationTransition' \
  --require-case 'testIndexDisabledTerminalPartialDoesNotAdvertiseContinueAndReleasesSession' \
  --require-case 'testActualReplaceAndPostRenameSyncFailuresNeverCommit' \
  --require-case 'testBounded32SnapshotQueueOverflowPreservesAcceptedAdmissionUntilExplicitResave' \
  --require-case 'testExplicitMonitoringDisposalIsIdempotentAndStopsBinderCallbacks' \
  --require-case 'testDestroyingManySceneModelsReturnsLeaseGenerationBookkeepingToBaseline'
xcodebuild -project Tidy.xcodeproj -scheme TidyNativeUITests -configuration Debug \
  -destination "platform=macOS,arch=$(uname -m)" -jobs 2 \
  -derivedDataPath "$EVIDENCE/ui-build" -resultBundlePath "$EVIDENCE/native-ui.xcresult" \
  test CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES 2>&1 | tee "$EVIDENCE/native-ui.log"
python3 scripts/verification/check-test-results.py xcode "$EVIDENCE/native-ui.xcresult" --minimum 2 \
  --require-case 'testEveryReviewTierKeepsSyntheticMutationsDisabled' \
  --require-case 'testSettingsRowsExposeSeparateEditorAndMetadataElements'
xcodebuild -project Tidy.xcodeproj -scheme Tidy -configuration Release -jobs 2 \
  -derivedDataPath "$EVIDENCE/release-build" build \
  CODE_SIGNING_ALLOWED=NO 'ARCHS=arm64 x86_64' ONLY_ACTIVE_ARCH=NO \
  2>&1 | tee "$EVIDENCE/release.log"
APP="$EVIDENCE/release-build/Build/Products/Release/Tidy.app"
lipo -verify_arch arm64 x86_64 "$APP/Contents/MacOS/Tidy"
plutil -lint "$APP/Contents/Resources/PrivacyInfo.xcprivacy"
shasum -a 256 "$APP/Contents/MacOS/Tidy" > "$EVIDENCE/executable.sha256"
