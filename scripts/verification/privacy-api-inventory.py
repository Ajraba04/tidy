#!/usr/bin/env python3
"""Inventory direct required-reason API source tokens for manual Apple review.

This is a conservative source scanner, not runtime evidence, App Store approval,
or a substitute for mapping each call site to the data fields it reads.
"""

from __future__ import annotations

import argparse
from collections import defaultdict
from pathlib import Path
import re
import sys


ROOT = Path(__file__).resolve().parents[2]
SOURCE_ROOTS = ("Tidy", "TidyCore/Sources")
SOURCE_SUFFIXES = {".swift", ".c", ".h", ".m", ".mm"}


def call(name: str) -> re.Pattern[str]:
    return re.compile(rf"\b{re.escape(name)}\s*\(")


PATTERNS: dict[str, tuple[tuple[str, re.Pattern[str]], ...]] = {
    "File timestamp": (
        ("FileAttributeKey.creationDate",
         re.compile(r"\bFileAttributeKey\.creationDate\b|\bNSFileCreationDate\b")),
        ("FileAttributeKey.modificationDate",
         re.compile(r"\bFileAttributeKey\.modificationDate\b|\bNSFileModificationDate\b")),
        ("UIDocument.fileModificationDate", re.compile(r"\bUIDocument\.fileModificationDate\b|\.fileModificationDate\b")),
        ("URLResourceKey.creationDateKey",
         re.compile(r"\bURLResourceKey\.creationDateKey\b|\bNSURLCreationDateKey\b|\.creationDateKey\b")),
        ("URLResourceKey.contentModificationDateKey",
         re.compile(r"\bURLResourceKey\.contentModificationDateKey\b|\bNSURLContentModificationDateKey\b|\.contentModificationDateKey\b")),
        ("URLResourceValues.creationDate",
         re.compile(r"(?<!FileAttributeKey)(?<!URLResourceKey)\.creationDate\b")),
        ("URLResourceValues.contentModificationDate",
         re.compile(r"(?<!FileAttributeKey)(?<!URLResourceKey)\.contentModificationDate\b")),
        ("fgetattrlist", call("fgetattrlist")),
        ("fstat", call("fstat")),
        ("fstatat", call("fstatat")),
        ("getattrlist", call("getattrlist")),
        ("getattrlistat", call("getattrlistat")),
        ("getattrlistbulk", call("getattrlistbulk")),
        ("lstat", call("lstat")),
        ("stat", call("stat")),
    ),
    "System boot time": (
        ("ProcessInfo.systemUptime", re.compile(r"\bProcessInfo\.processInfo\.systemUptime\b|\.systemUptime\b")),
        ("mach_absolute_time", re.compile(r"\bmach_absolute_time\s*\(")),
    ),
    "Disk space": (
        ("FileAttributeKey.systemFreeSize",
         re.compile(r"\bFileAttributeKey\.systemFreeSize\b|\bNSFileSystemFreeSize\b|\.systemFreeSize\b")),
        ("FileAttributeKey.systemSize",
         re.compile(r"\bFileAttributeKey\.systemSize\b|\bNSFileSystemSize\b|\.systemSize\b")),
        ("URLResourceKey.volumeAvailableCapacityKey",
         re.compile(r"\bURLResourceKey\.volumeAvailableCapacityKey\b|\bNSURLVolumeAvailableCapacityKey\b|\.volumeAvailableCapacityKey\b")),
        ("URLResourceKey.volumeAvailableCapacityForImportantUsageKey",
         re.compile(r"\bURLResourceKey\.volumeAvailableCapacityForImportantUsageKey\b|\bNSURLVolumeAvailableCapacityForImportantUsageKey\b|\.volumeAvailableCapacityForImportantUsageKey\b")),
        ("URLResourceKey.volumeAvailableCapacityForOpportunisticUsageKey",
         re.compile(r"\bURLResourceKey\.volumeAvailableCapacityForOpportunisticUsageKey\b|\bNSURLVolumeAvailableCapacityForOpportunisticUsageKey\b|\.volumeAvailableCapacityForOpportunisticUsageKey\b")),
        ("URLResourceKey.volumeTotalCapacityKey",
         re.compile(r"\bURLResourceKey\.volumeTotalCapacityKey\b|\bNSURLVolumeTotalCapacityKey\b|\.volumeTotalCapacityKey\b")),
        ("fgetattrlist", call("fgetattrlist")),
        ("fstatfs", call("fstatfs")),
        ("fstatvfs", call("fstatvfs")),
        ("getattrlist", call("getattrlist")),
        ("getattrlistat", call("getattrlistat")),
        ("statfs", call("statfs")),
        ("statvfs", call("statvfs")),
    ),
    "Active keyboards": (
        ("UITextInputMode.activeInputModes",
         re.compile(r"\bUITextInputMode\.activeInputModes\b|\.activeInputModes\b")),
    ),
    "User defaults": (
        ("UserDefaults", re.compile(r"\bUserDefaults\b|\bNSUserDefaults\b")),
        ("@AppStorage", re.compile(r"@AppStorage\b")),
    ),
    # Apple does not name this sysctl string in the current accessed-API list,
    # but it is retained as a separate sensitive boot-identity review row.
    "Boot identity (not in current Apple required-reason list)": (
        ("kern.boottime", re.compile(r"[\"']kern\.boottime[\"']")),
        ("kern.bootsessionuuid", re.compile(r"[\"']kern\.bootsessionuuid[\"']")),
    ),
}


HitMap = dict[str, dict[str, list[int]]]


def scan_lines(lines: list[str]) -> HitMap:
    hits: dict[str, dict[str, list[int]]] = {
        category: defaultdict(list) for category in PATTERNS
    }
    for line_number, line in enumerate(lines, 1):
        if line.lstrip().startswith("//"):
            continue
        for category, patterns in PATTERNS.items():
            for api, pattern in patterns:
                matches = list(pattern.finditer(line))
                if api in {"stat", "statfs"}:
                    # Swift imports C structures with the same names as these
                    # functions. Exclude only a zero-argument initializer; a
                    # multiline function call remains visible.
                    matches = [match for match in matches
                               if re.match(r"\s*\)", line[match.end():]) is None]
                if matches:
                    hits[category][api].append(line_number)
    return {category: dict(apis) for category, apis in hits.items() if apis}


def source_files(root: Path):
    for base in SOURCE_ROOTS:
        directory = root / base
        if not directory.exists():
            continue
        for source in sorted(directory.rglob("*")):
            if source.is_file() and source.suffix in SOURCE_SUFFIXES:
                yield source


def render_inventory(root: Path) -> str:
    rows: list[tuple[str, str, str]] = []
    for source in source_files(root):
        hits = scan_lines(source.read_text(encoding="utf-8").splitlines())
        for category, apis in hits.items():
            matches = "; ".join(
                f"`{api}`@{','.join(str(line) for line in lines)}"
                for api, lines in sorted(apis.items())
            )
            rows.append((str(source.relative_to(root)), category, matches))

    output = [
        "| Source | Direct API category | Matched tokens and lines |",
        "|---|---|---|",
    ]
    output.extend(f"| `{source}` | {category} | {matches} |"
                  for source, category, matches in rows)
    return "\n".join(output)


def run_self_test() -> None:
    fixture = [
        "_ = FileAttributeKey.creationDate",
        "_ = FileAttributeKey.modificationDate",
        "_ = UIDocument.fileModificationDate",
        "_ = URLResourceKey.creationDateKey",
        "_ = URLResourceKey.contentModificationDateKey",
        "_ = values.creationDate",
        "_ = values.contentModificationDate",
        "fgetattrlist(fd, &request, &buffer, 64, 0)",
        "fstat(fd, &info)",
        "fstatat(fd, name, &info, 0)",
        "getattrlist(path, &request, &buffer, 64, 0)",
        "getattrlistat(fd, name, &request, &buffer, 64, 0)",
        "getattrlistbulk(fd, &request, &buffer, 64, 0)",
        "lstat(path, &info)",
        "stat(path, &info)",
        "_ = ProcessInfo.processInfo.systemUptime",
        "_ = mach_absolute_time()",
        "_ = FileAttributeKey.systemFreeSize",
        "_ = FileAttributeKey.systemSize",
        "_ = URLResourceKey.volumeAvailableCapacityKey",
        "_ = URLResourceKey.volumeAvailableCapacityForImportantUsageKey",
        "_ = URLResourceKey.volumeAvailableCapacityForOpportunisticUsageKey",
        "_ = URLResourceKey.volumeTotalCapacityKey",
        "fstatfs(fd, &info)",
        "fstatvfs(fd, &info)",
        "statfs(path, &info)",
        "statvfs(path, &info)",
        "_ = UITextInputMode.activeInputModes",
        "_ = UserDefaults.standard",
        "@AppStorage(\"fixture\") var fixture = false",
        "sysctlbyname(\"kern.boottime\", &value, &size, nil, 0)",
        "sysctlbyname(\"kern.bootsessionuuid\", &value, &size, nil, 0)",
        "stat(",
        "    path, &info)",
        "statfs(",
        "    path, &filesystemInfo)",
        "var structureOnly = stat()",
        "var filesystemStructureOnly = statfs()",
        "let statistic = 1",
    ]
    hits = scan_lines(fixture)
    found = {(category, api) for category, apis in hits.items() for api in apis}
    expected = {(category, api) for category, patterns in PATTERNS.items()
                for api, _ in patterns}
    missing = sorted(expected - found)
    if missing:
        raise AssertionError(f"scanner missed configured patterns: {missing}")
    if 33 not in hits["File timestamp"]["stat"] or 35 not in hits["Disk space"]["statfs"]:
        raise AssertionError("scanner missed a multiline stat/statfs call")
    if any(37 in lines or 38 in lines or 39 in lines
           for apis in hits.values() for lines in apis.values()):
        raise AssertionError("scanner matched a struct initializer or unrelated identifier")
    print(f"privacy inventory self-tests: PASS ({len(expected)} scanner patterns)")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, default=ROOT,
                        help="repository root to scan (defaults to this checkout)")
    parser.add_argument("--self-test", action="store_true",
                        help="verify every current pattern, including getattrlistat/bulk")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    try:
        if args.self_test:
            run_self_test()
        else:
            print(render_inventory(args.root.resolve()))
    except (AssertionError, OSError, UnicodeError) as error:
        print(f"privacy inventory failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
