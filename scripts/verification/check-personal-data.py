#!/usr/bin/env python3
"""Fail without printing any matched personal data; self-test the forbidden rules."""
import argparse
from pathlib import Path
import re
import subprocess
import sys
import tempfile

RULES = [re.compile(pattern, re.I) for pattern in (
    r'binjamshid', r'albayyan', r'claude\.ai', r'/Users/[A-Za-z]',
)]
def forbidden(text):
    return any(rule.search(text) for rule in RULES)

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--self-test', action='store_true')
    parser.add_argument('roots', nargs='*', default=['TidyCore/Sources', 'Tidy'])
    args = parser.parse_args()
    if args.self_test:
        with tempfile.TemporaryDirectory(prefix='tidy-personal-gate-') as scratch:
            fixture = Path(scratch) / 'Fixture.swift'
            for sentinel in ('binjamshid', 'albayyan', 'claude.ai', '/Users/PrivateFixture'):
                fixture.write_text(sentinel)
                result = subprocess.run([sys.executable, __file__, scratch], capture_output=True, text=True)
                if result.returncode == 0 or sentinel in result.stdout + result.stderr:
                    raise SystemExit('Seeded forbidden source did not fail privately')
            fixture.write_text('let home = environment.homeDirectory')
            result = subprocess.run([sys.executable, __file__, scratch], capture_output=True)
            if result.returncode != 0:
                raise SystemExit('Clean source was incorrectly denied')
        print('PASS: seeded source scans fail without exposing values; clean source passes')
        return
    violations = 0
    for root in map(Path, args.roots):
        if not root.exists():
            raise SystemExit('Required source root is missing')
        for source in root.rglob('*'):
            if source.is_file() and source.suffix in {'.swift', '.json', '.plist', '.xcstrings'}:
                if forbidden(source.read_text(errors='replace')):
                    violations += 1
    if violations:
        raise SystemExit(f'Personal-data gate failed in {violations} source files; inspect locally. Values withheld.')
    print('PASS: no forbidden personal-data patterns in source')

if __name__ == '__main__':
    main()
