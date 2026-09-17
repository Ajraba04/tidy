#!/usr/bin/env python3
"""Generate in disposable storage and compare source/resource target membership."""
import json
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]

def membership(project):
    objects = json.loads(subprocess.check_output(
        ['plutil', '-convert', 'json', '-o', '-', str(project / 'project.pbxproj')]))['objects']
    parents = {}
    for identifier, obj in objects.items():
        for child in obj.get('children', []):
            parents[child] = identifier
    def path(identifier):
        obj = objects[identifier]
        value = obj.get('path', '')
        if obj.get('sourceTree') == '<group>' and identifier in parents:
            return path(parents[identifier]) / value
        return Path(value)
    result = {}
    for obj in objects.values():
        if obj.get('isa') != 'PBXNativeTarget':
            continue
        for phase in obj.get('buildPhases', []):
            entry = objects[phase]
            if entry['isa'] not in ('PBXSourcesBuildPhase', 'PBXResourcesBuildPhase'):
                continue
            result[(obj['name'], entry['isa'])] = sorted(str((project.parent / path(objects[f]['fileRef'])).resolve().relative_to(ROOT))
                for f in entry.get('files', []) if 'fileRef' in objects[f])
    return result

with tempfile.TemporaryDirectory(prefix='.tidy-project-check-', dir=ROOT) as temporary:
    scratch = str(Path(temporary).resolve())
    subprocess.run(['xcodegen', 'generate', '--spec', str(ROOT / 'project.yml'),
        '--project-root', str(ROOT), '--project', scratch, '--quiet'], check=True)
    expected = membership(ROOT / 'Tidy.xcodeproj')
    generated = membership(Path(scratch) / 'Tidy.xcodeproj')
    differences = []
    for key in sorted(expected.keys() | generated.keys()):
        if expected.get(key) != generated.get(key):
            differences.append(f'{key}: committed={expected.get(key)} generated={generated.get(key)}')
    if differences:
        raise SystemExit('\n'.join(differences))
    tests = expected.get(('TidyAppModelTests', 'PBXSourcesBuildPhase'), [])
    for source in sorted((ROOT / 'TidyAppModelTests').glob('*.swift')):
        if str(source.relative_to(ROOT)) not in tests:
            raise SystemExit(f'Model test missing from generated project: {source.name}')
    print(f'PASS: {len(expected)} target phases match; all model test files included.')
