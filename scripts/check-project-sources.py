#!/usr/bin/env python3
"""Compare explicit test-target source/resource membership with project.yml on macOS.

No project generation or third-party Python package is required. The app target's
recursive source group is checked by the app build; this checks the explicit lists
most vulnerable to silent coverage loss after regeneration.
"""
import json
from pathlib import Path
import re
import subprocess

root = Path(__file__).resolve().parent.parent
spec = (root / "project.yml").read_text().split("\ntargets:\n", 1)[1].split("\nschemes:\n", 1)[0]
project = json.loads(subprocess.check_output([
    "plutil", "-convert", "json", "-o", "-", str(root / "Tidy.xcodeproj/project.pbxproj")
]))
objects = project["objects"]
paths = {}


def visit(identifier, parent=""):
    obj = objects[identifier]
    path = str(Path(parent) / obj.get("path", ""))
    if obj["isa"] in ("PBXGroup", "PBXVariantGroup"):
        for child in obj.get("children", []):
            visit(child, path)
    elif obj["isa"] == "PBXFileReference":
        paths[identifier] = path.removeprefix("./")


visit(objects[project["rootObject"]]["mainGroup"])
for name in ("TidyAppModelTests", "TidyUITestHost"):
    section = re.search(r"^  " + name + r":\n(.*?)(?=^  \w+:|\Z)", spec, re.M | re.S)
    if not section:
        raise SystemExit(f"Missing target in project.yml: {name}")
    expected = set(re.findall(r"^      - path: (.+)$", section[1], re.M))
    target = next(obj for obj in objects.values() if obj.get("isa") == "PBXNativeTarget" and obj.get("name") == name)
    actual = set()
    for phase_id in target["buildPhases"]:
        phase = objects[phase_id]
        if phase["isa"] not in ("PBXSourcesBuildPhase", "PBXResourcesBuildPhase"):
            continue
        for build_id in phase["files"]:
            actual.add(paths[objects[build_id]["fileRef"]])
    if expected != actual:
        raise SystemExit(f"{name}: project.yml-only={sorted(expected - actual)}; project-only={sorted(actual - expected)}")
print("Explicit test-target sources and resources agree with project.yml.")
