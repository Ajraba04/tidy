#!/usr/bin/env python3
"""Check compiled fixture markers before UI launch and in the Release artifact."""
import argparse
from pathlib import Path
import plistlib
import sys

MARKERS = (b'runtime.synthetic.attestation', b'tidy-production-runtime-')
IDENTIFIERS = {
    'production': 'io.github.ajraba04.Tidy',
    'fixture': 'io.github.ajraba04.Tidy.ProductionRuntimeVerification',
}


def markers_in(path):
    found = set()
    overlap = b''
    with path.open('rb') as stream:
        while chunk := stream.read(1024 * 1024):
            data = overlap + chunk
            found.update(marker for marker in MARKERS if marker in data)
            overlap = data[-(max(map(len, MARKERS)) - 1):]
    return found


def inspect(app, mode):
    app = app.resolve(strict=True)
    info_path = app / 'Contents/Info.plist'
    if not info_path.resolve(strict=True).is_relative_to(app):
        raise ValueError('Info.plist escapes the built app')
    info = plistlib.loads(info_path.read_bytes())
    if info.get('CFBundleIdentifier') != IDENTIFIERS[mode]:
        raise ValueError('unexpected bundle identifier for this verification mode')
    executable = info.get('CFBundleExecutable')
    if not isinstance(executable, str) or Path(executable).name != executable:
        raise ValueError('missing or invalid bundle executable')
    macos = app / 'Contents/MacOS'
    if not macos.resolve(strict=True).is_relative_to(app):
        raise ValueError('code directory escapes the built app')
    if not (macos / executable).is_file():
        raise ValueError('bundle executable is missing')
    files = sorted(path for path in macos.rglob('*') if path.is_file())
    found = set()
    for path in files:
        if not path.resolve(strict=True).is_relative_to(app):
            raise ValueError('code file escapes the built app')
        found.update(markers_in(path))
    if mode == 'production' and found:
        raise ValueError('production code contains fixture-only markers')
    if mode == 'fixture' and found != set(MARKERS):
        raise ValueError('runtime host lacks its compiled synthetic composition')
    print(f'PASS: {mode} binary composition ({len(files)} code files)')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('mode', choices=IDENTIFIERS)
    parser.add_argument('app', type=Path)
    args = parser.parse_args()
    try:
        inspect(args.app, args.mode)
    except (OSError, ValueError, plistlib.InvalidFileException) as error:
        print(f'Binary composition check failed: {error}', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
