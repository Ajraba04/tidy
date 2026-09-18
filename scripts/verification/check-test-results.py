#!/usr/bin/env python3
"""Reject zero-test success and preserve failed aggregate outcomes."""
import argparse
import json
import re
import subprocess
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument('kind', choices=['swift', 'xcode'])
parser.add_argument('artifact')
parser.add_argument('--minimum', type=int, required=True)
parser.add_argument('--allow-skipped', action='append', default=[])
args = parser.parse_args()
if args.kind == 'swift':
    log = Path(args.artifact).read_text(errors='replace')
    results = re.findall(r'Test run with (\d+) tests?[^\n]* (passed|failed)', log)
    if not results or any(state != 'passed' for _, state in results):
        raise SystemExit('Missing or failed Swift test aggregate')
    skipped = re.findall(r'(?m)^.*?\bTest (.+?) skipped(?:\.|:|$)', log)
    if any(name.strip('"') not in args.allow_skipped for name in skipped):
        raise SystemExit('Unexpected skipped Swift test; provide isolated execution evidence')
    count = sum(int(n) for n, _ in results)
else:
    summary = json.loads(subprocess.check_output(['xcrun', 'xcresulttool', 'get', 'test-results',
        'summary', '--path', args.artifact, '--compact']))
    if summary.get('failedTests', 0) or summary.get('testFailures'):
        raise SystemExit('Xcode result bundle contains failures')
    if summary.get('skippedTests', 0):
        raise SystemExit('Xcode result bundle contains skipped tests')
    count = summary.get('passedTests', 0)
    if summary.get('result') not in (None, 'Passed'):
        raise SystemExit('Xcode test run did not pass')
if count < args.minimum:
    raise SystemExit(f'Too few passing tests: {count}; require at least {args.minimum}')
print(f'PASS: {count} tests, minimum {args.minimum}')
