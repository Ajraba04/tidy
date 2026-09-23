#!/usr/bin/env bash
set -euo pipefail
# Reviewed upstream release; update version + digest together in a reviewed PR.
TOOLS_DIR="${1:?Usage: install-xcodegen.sh destination-directory}"
mkdir -p "$TOOLS_DIR"
curl --fail --location --retry 2 \
  https://github.com/yonaskolb/XcodeGen/releases/download/2.46.0/xcodegen.zip \
  --output "$TOOLS_DIR/xcodegen.zip"
python3 - "$TOOLS_DIR/xcodegen.zip" <<'PY'
import hashlib, pathlib, sys
actual = hashlib.sha256(pathlib.Path(sys.argv[1]).read_bytes()).hexdigest()
expected = '4d9e34b62172d645eed6457cac13fc222569974098ef4ee9c3368bedf0196806'
if actual != expected:
    raise SystemExit('XcodeGen archive digest mismatch')
PY
unzip -q -o "$TOOLS_DIR/xcodegen.zip" -d "$TOOLS_DIR"
"$TOOLS_DIR/xcodegen/bin/xcodegen" --version
