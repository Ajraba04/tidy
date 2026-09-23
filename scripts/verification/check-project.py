#!/usr/bin/env python3
"""Generate in disposable storage and compare source/resource target membership."""
import json
from pathlib import Path
import shlex
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
RUNTIME_HOST = 'TidyProductionRuntimeHost'
RUNTIME_FLAG = 'TIDY_RUNTIME_TEST_HOST'


def setting_tokens(value):
    if isinstance(value, list):
        return [token for item in value for token in shlex.split(str(item))]
    return shlex.split(str(value or ''))


def validate_runtime_isolation(objects):
    """The disposable composition must be a build-time choice of one test host."""
    targets = {obj['name']: obj for obj in objects.values()
               if obj.get('isa') == 'PBXNativeTarget'}
    for required in ('Tidy', RUNTIME_HOST, 'TidyProductionNativeUITests'):
        if required not in targets:
            raise SystemExit(f'Required production/runtime target missing: {required}')
    for obj in objects.values():
        if obj.get('isa') not in ('PBXNativeTarget', 'PBXProject'):
            continue
        name = obj.get('name', '<project>')
        configurations = objects[obj['buildConfigurationList']]['buildConfigurations']
        for identifier in configurations:
            configuration = objects[identifier]
            settings = configuration.get('buildSettings', {})
            conditions = setting_tokens(settings.get('SWIFT_ACTIVE_COMPILATION_CONDITIONS'))
            flags = setting_tokens(settings.get('OTHER_SWIFT_FLAGS'))
            has_fixture_flag = RUNTIME_FLAG in conditions or f'-D{RUNTIME_FLAG}' in flags or \
                any(left == '-D' and right == RUNTIME_FLAG
                    for left, right in zip(flags, flags[1:]))
            if has_fixture_flag != (name == RUNTIME_HOST):
                raise SystemExit(f'Runtime composition flag isolation failed: '
                                 f'{name}/{configuration["name"]}')
            if name == RUNTIME_HOST and settings.get('PRODUCT_BUNDLE_IDENTIFIER') != \
                    'io.github.ajraba04.Tidy.ProductionRuntimeVerification':
                raise SystemExit('Runtime host must use its distinct verification bundle identifier')
            if name == 'TidyProductionNativeUITests' and \
                    settings.get('TEST_TARGET_NAME') != RUNTIME_HOST:
                raise SystemExit('Production-scene UI tests must launch the isolated runtime host')


def membership(project):
    objects = json.loads(subprocess.check_output(
        ['plutil', '-convert', 'json', '-o', '-', str(project / 'project.pbxproj')]))['objects']
    validate_runtime_isolation(objects)
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
    for target in ('TidyAppModelTests', 'TidyNativeUITests', 'TidyProductionNativeUITests'):
        tests = expected.get((target, 'PBXSourcesBuildPhase'), [])
        sources = sorted((ROOT / target).rglob('*.swift'))
        if not sources:
            raise SystemExit(f'Test target has no source files: {target}')
        for source in sources:
            if str(source.relative_to(ROOT)) not in tests:
                raise SystemExit(f'Test missing from generated project: {target}/{source.name}')
    print(f'PASS: {len(expected)} target phases match; all test files included; '
          'runtime composition restricted to its test host.')
