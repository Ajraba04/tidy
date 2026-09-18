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
parser.add_argument('--require-case', action='append', default=[],
                    help='Required passing test display name or identifier (repeatable)')
args = parser.parse_args()

def normalized_case_name(name):
    value = name.rsplit('/', 1)[-1].strip().strip('"')
    return value[:-2] if value.endswith('()') else value

if args.kind == 'swift':
    log = Path(args.artifact).read_text(errors='replace')
    results = re.findall(r'Test run with (\d+) tests?[^\n]* (passed|failed)', log)
    if not results or any(state != 'passed' for _, state in results):
        raise SystemExit('Missing or failed Swift test aggregate')
    skipped = re.findall(r'(?m)^.*?\bTest (.+?) skipped(?:\.|:|$)', log)
    if any(name.strip('"') not in args.allow_skipped for name in skipped):
        raise SystemExit('Unexpected skipped Swift test; provide isolated execution evidence')
    count = sum(int(n) for n, _ in results)
    passed = set()
    for line in log.splitlines():
        match = re.match(r'^✔ Test (?:(?:"([^"]+)")|(.+?))'
                         r'(?: with \d+ test cases)? passed(?: |$)', line)
        if match:
            passed.add(normalized_case_name(match.group(1) or match.group(2)))
    missing = [name for name in args.require_case
               if normalized_case_name(name) not in passed]
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
    tests = json.loads(subprocess.check_output(['xcrun', 'xcresulttool', 'get', 'test-results',
        'tests', '--path', args.artifact, '--compact']))
    passed = set()
    def collect(nodes):
        for node in nodes:
            if node.get('result') == 'Passed':
                passed.update(normalized_case_name(value) for value in
                              filter(None, [node.get('name'), node.get('nodeIdentifier')]))
            collect(node.get('children', []))
    collect(tests.get('testNodes', []))
    missing = [name for name in args.require_case
               if normalized_case_name(name) not in passed]
if count < args.minimum:
    raise SystemExit(f'Too few passing tests: {count}; require at least {args.minimum}')
if missing:
    raise SystemExit('Missing required passing test cases: ' + ', '.join(missing))
print(f'PASS: {count} tests, minimum {args.minimum}')
