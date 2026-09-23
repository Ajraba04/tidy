# Opening a verified unsigned artifact

Signing and notarization are optional for Tidy's intended manual ZIP/DMG distribution. No new package from the remediation branch has passed the full installation acceptance matrix. These instructions describe the chosen path; they do not certify an existing download.

1. Obtain the artifact and its expected SHA-256 from the same trusted, authenticated release record. Compare `shasum -a 256 /path/to/Tidy-version.zip` (or the DMG) with that record **before** extracting or installing. A hash downloaded from an untrusted source alongside a substituted artifact is not provenance.
2. Extract the ZIP or open the DMG and copy `Tidy.app` to the intended Applications directory. Try opening the app once.
3. If macOS blocks it because the developer cannot be verified, and you have established that the artifact is trustworthy and unmodified, open **System Settings → Privacy & Security** and use **Open Anyway** for this app. Confirm the subsequent per-app prompt.
4. If macOS reports malware, revocation, damage or modification, stop and obtain a verified replacement. The unidentified-developer procedure is not a remedy for those warnings. Managed Macs may restrict exceptions.

This follows Apple's current [Safely open apps on your Mac](https://support.apple.com/en-us/102445) guidance, checked on 2026-09-17. Do not disable Gatekeeper globally or recursively remove quarantine attributes as a standard installation step. The old Control-click workflow is not assumed to work on every supported OS.

An unsigned app has not received Apple's notarization malware check. Neither unsigned nor notarized status establishes Tidy's functional, privacy or safety acceptance. Keep unresolved mandatory recovery records across manual upgrades; do not delete application-support data to bypass a recovery warning. Installation, upgrade and uninstall with recovery witnesses still require disposable-host evidence on the supported OS matrix.
