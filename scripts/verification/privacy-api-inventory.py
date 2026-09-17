#!/usr/bin/env python3
"""List direct source occurrences for manual required-reason review, not legal approval."""
from pathlib import Path
import re
ROOT = Path(__file__).resolve().parents[2]
PATTERNS = {
    'File metadata': re.compile(r'\b(?:fstatat|fstat|lstat|stat|getattrlist|fgetattrlist)\s*\(|\.(?:creationDate|modificationDate|contentModificationDateKey|creationDateKey|fileModificationDate)\b'),
    'Disk/volume': re.compile(r'\b(?:fstatfs|statfs|statvfs|fstatvfs)\s*\(|\.(?:volumeAvailableCapacityKey|volumeAvailableCapacityForImportantUsageKey|volumeAvailableCapacityForOpportunisticUsageKey|volumeTotalCapacityKey|systemFreeSize|systemSize)\b'),
    'Time/boot': re.compile(r'\b(?:systemUptime|mach_absolute_time)\b|kern\.boottime'),
    'User defaults': re.compile(r'\bUserDefaults\b|@AppStorage\b'),
}
print('| Source | Direct API category | Lines |')
print('|---|---|---|')
for base in ('Tidy', 'TidyCore/Sources'):
    for source in sorted((ROOT/base).rglob('*.swift')):
        lines = source.read_text().splitlines()
        for category, pattern in PATTERNS.items():
            hits = [str(n) for n, line in enumerate(lines, 1) if pattern.search(line) and not line.lstrip().startswith('//')]
            if hits:
                print(f'| `{source.relative_to(ROOT)}` | {category} | {", ".join(hits)} |')
