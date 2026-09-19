#!/usr/bin/env python3
"""Run bounded current-host observations against Tidy's isolated runtime host.

The runtime app chooses and attests its own synthetic storage. This observer may
select only a fixed scenario and never forwards a home, state path, duration,
policy, capability, or authority value into the app.
"""

from __future__ import annotations

import argparse
import ctypes
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import stat
import statistics
import subprocess
import sys
import tempfile
import time
from typing import Any


RUNTIME_BUNDLE_ID = "io.github.ajraba04.Tidy.ProductionRuntimeVerification"
PRODUCTION_BUNDLE_ID = "io.github.ajraba04.Tidy"
REPO_ROOT = Path(__file__).resolve().parents[2]
FIXTURE_PREFIX = "tidy-production-runtime-"
EVIDENCE_PREFIX = "tidy-r13-observation-"
MARKERS = (b"runtime.synthetic.attestation", b"tidy-production-runtime-")
ATTESTATION_KEYS = {
    "schema", "scenario", "pid", "settingsRevision", "timerRunning",
    "sceneLeases", "explicitWorkLeases", "scanSessions", "scanActiveWork",
    "allMutationsDenied", "timerScheduledCount", "timerCancelledCount",
    "observedMonotonicNanoseconds", "applicationHidden",
}
SCENARIOS = {
    "hidden-off": {
        "flag": "--tidy-runtime-hidden-off",
        "duration": 120,
        "timer": False,
        "testCase": "testProductionHiddenOffObservationRemainsIdleForFixedWindow",
    },
    "hidden-authorized": {
        "flag": "--tidy-runtime-hidden-authorized",
        "duration": 600,
        "timer": True,
        "testCase": "testProductionHiddenAuthorizedObservationKeepsOneTimerForFixedWindow",
    },
}
PERFORMANCE_SCENARIOS = {
    "performance-50k": {
        "testCase": "testFixed50kProductionScanWithExternalObservation",
        "finalName": "runtime-performance.json",
        "timeout": 180,
    },
    "active-cancel-20": {
        "testCase": "testTwentyActiveCancelCyclesWithExternalObservation",
        "finalName": "runtime-cycles.json",
        "timeout": 600,
    },
}
MODES = (*sorted(SCENARIOS), *sorted(PERFORMANCE_SCENARIOS),
         "traffic-workflows", "paired-builds")
TRAFFIC_CASES = (
    "testProductionRuntimeStartsWithSyntheticStorageAttestation",
    "testProductionSettingsAndSafeCleanSupportTwoWindowsKeyboardAndAX",
    "testProductionFullHomeScanTraversesOnlySyntheticHomeAndPreservesWitness",
    "testProductionFullHomeScanCancelSurvivesCloseAndReopen",
    "testProductionFreshDefaultsQuickScanKeepsSettingsAbsent",
    "testProductionFutureSettingsRecoveryPreservesBytesAndWithholdsControls",
)
BUILD_PAIR_COUNT = 5
TOOLS = {
    "ps": Path("/bin/ps"),
    "pgrep": Path("/usr/bin/pgrep"),
    "lsof": Path("/usr/sbin/lsof"),
    "footprint": Path("/usr/bin/footprint"),
    "nettop": Path("/usr/bin/nettop"),
}
LIBPROC = ctypes.CDLL("/usr/lib/libproc.dylib", use_errno=True)
LIBC = ctypes.CDLL(None, use_errno=True)
PROC_PIDPATHINFO_MAXSIZE = 4096
RENAME_EXCL = 0x00000004


class ObservationError(RuntimeError):
    pass


def is_relative_to(path: Path, parent: Path) -> bool:
    try:
        path.relative_to(parent)
        return True
    except ValueError:
        return False


def markers_in(path: Path) -> set[bytes]:
    found: set[bytes] = set()
    overlap = b""
    width = max(map(len, MARKERS)) - 1
    with path.open("rb") as stream:
        while chunk := stream.read(1024 * 1024):
            data = overlap + chunk
            found.update(marker for marker in MARKERS if marker in data)
            overlap = data[-width:]
    return found


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        while chunk := stream.read(1024 * 1024):
            digest.update(chunk)
    return digest.hexdigest()


def artifact_manifest(app: Path) -> dict[str, Any]:
    app = app.resolve(strict=True)
    paths = [(app / "Contents/Info.plist").resolve(strict=True)]
    code_directory = (app / "Contents/MacOS").resolve(strict=True)
    paths.extend(sorted(path.resolve(strict=True) for path in code_directory.rglob("*")
                        if path.is_file()))
    if any(not is_relative_to(path, app) for path in paths):
        raise ObservationError("artifact manifest path escapes the runtime bundle")
    return {
        "bundle": str(app),
        "files": [{
            "path": str(path.relative_to(app)),
            "bytes": path.stat().st_size,
            "sha256": sha256_file(path),
        } for path in paths],
    }


def git_bytes(arguments: list[str]) -> bytes:
    result = run_tool(["/usr/bin/git", *arguments], timeout=30, cwd=REPO_ROOT)
    if result.returncode != 0:
        raise ObservationError(f"git {' '.join(arguments)} failed")
    return result.stdout


def source_wip_state() -> dict[str, Any]:
    head = git_bytes(["rev-parse", "HEAD"]).decode("ascii").strip()
    status = git_bytes(["status", "--porcelain=v1", "-z", "--untracked-files=all"])
    staged = git_bytes(["diff", "--binary", "--cached", "--no-ext-diff", "HEAD", "--"])
    unstaged = git_bytes(["diff", "--binary", "--no-ext-diff", "HEAD", "--"])
    untracked = [path for path in
                 git_bytes(["ls-files", "-o", "--exclude-standard", "-z"]).split(b"\0") if path]
    untracked_digest = hashlib.sha256()
    untracked_bytes = 0
    for raw_path in sorted(untracked):
        relative = Path(os.fsdecode(raw_path))
        path = (REPO_ROOT / relative).absolute()
        if not is_relative_to(path, REPO_ROOT):
            raise ObservationError("untracked source input escapes the repository")
        info = path.lstat()
        untracked_digest.update(raw_path + b"\0")
        if stat.S_ISLNK(info.st_mode):
            payload = os.readlink(path).encode("utf-8")
            untracked_digest.update(b"link\0" + payload)
            untracked_bytes += len(payload)
        elif stat.S_ISREG(info.st_mode):
            if info.st_size > 64 * 1024 * 1024:
                raise ObservationError("untracked source input exceeds the 64 MiB bound")
            with path.open("rb") as stream:
                while chunk := stream.read(1024 * 1024):
                    untracked_digest.update(chunk)
                    untracked_bytes += len(chunk)
                    if untracked_bytes > 256 * 1024 * 1024:
                        raise ObservationError("aggregate untracked inputs exceed 256 MiB")
        else:
            raise ObservationError("untracked source input is not a regular file or symlink")
    return {
        "head": head,
        "statusEntryCount": len([entry for entry in status.split(b"\0") if entry]),
        "statusSHA256": hashlib.sha256(status).hexdigest(),
        "stagedDiffSHA256": hashlib.sha256(staged).hexdigest(),
        "unstagedDiffSHA256": hashlib.sha256(unstaged).hexdigest(),
        "untrackedInputCount": len(untracked),
        "untrackedInputBytes": untracked_bytes,
        "untrackedContentSHA256": untracked_digest.hexdigest(),
    }


def host_context() -> dict[str, Any]:
    commands = {
        "swVers": ["/usr/bin/sw_vers"],
        "architecture": ["/usr/bin/uname", "-m"],
        "xcode": ["/usr/bin/xcodebuild", "-version"],
        "python": [sys.executable, "--version"],
    }
    output: dict[str, str] = {}
    for name, arguments in commands.items():
        result = run_tool(arguments, timeout=10)
        if result.returncode != 0:
            raise ObservationError(f"host context command failed: {name}")
        text = (result.stdout + result.stderr).decode("utf-8", errors="strict").strip()
        output[name] = text
    return {
        "commands": output,
        "observerTools": {
            name: {"path": str(path), "sha256": sha256_file(path)}
            for name, path in sorted(TOOLS.items())
        },
    }


def validate_runtime_app(app: Path) -> tuple[Path, Path]:
    app = app.resolve(strict=True)
    if app.suffix != ".app" or not app.is_dir():
        raise ObservationError("runtime app must be an existing .app directory")
    info_path = (app / "Contents/Info.plist").resolve(strict=True)
    if not is_relative_to(info_path, app):
        raise ObservationError("runtime Info.plist escapes its bundle")
    try:
        info = plistlib.loads(info_path.read_bytes())
    except (OSError, plistlib.InvalidFileException) as error:
        raise ObservationError(f"invalid runtime Info.plist: {error}") from error
    if info.get("CFBundleIdentifier") != RUNTIME_BUNDLE_ID:
        raise ObservationError("refusing a non-runtime bundle identifier")
    executable_name = info.get("CFBundleExecutable")
    if not isinstance(executable_name, str) or Path(executable_name).name != executable_name:
        raise ObservationError("invalid runtime executable name")
    code_directory = (app / "Contents/MacOS").resolve(strict=True)
    if not is_relative_to(code_directory, app) or not code_directory.is_dir():
        raise ObservationError("runtime code directory escapes or is missing")
    executable = (code_directory / executable_name).resolve(strict=True)
    if not is_relative_to(executable, app) or not executable.is_file():
        raise ObservationError("runtime executable escapes or is missing")
    code_files = sorted(path for path in code_directory.rglob("*") if path.is_file())
    found: set[bytes] = set()
    for path in code_files:
        resolved = path.resolve(strict=True)
        if not is_relative_to(resolved, app):
            raise ObservationError("runtime code file escapes its bundle")
        found.update(markers_in(resolved))
    if found != set(MARKERS):
        raise ObservationError("runtime executable lacks the fixed synthetic composition")
    return app, executable


def canonical_temporary_roots() -> tuple[Path, ...]:
    roots = [Path("/private/tmp").resolve(strict=True)]
    system_temporary = Path(tempfile.gettempdir()).resolve(strict=True)
    if system_temporary not in roots:
        roots.append(system_temporary)
    return tuple(roots)


def validate_fixture_root(root: Path, *, require_exists: bool = True) -> Path:
    if root.name == "" or not root.name.startswith(FIXTURE_PREFIX):
        raise ObservationError("fixture root has an unexpected name")
    if require_exists:
        info = root.lstat()
        if stat.S_ISLNK(info.st_mode) or not stat.S_ISDIR(info.st_mode):
            raise ObservationError("fixture root is not a no-follow directory")
        if info.st_uid != os.geteuid() or stat.S_IMODE(info.st_mode) != 0o700:
            raise ObservationError("fixture root owner or mode is unsafe")
        resolved = root.resolve(strict=True)
    else:
        resolved = root.resolve(strict=False)
    if resolved.parent not in canonical_temporary_roots():
        raise ObservationError("fixture root is outside canonical temporary storage")
    home = Path.home().resolve(strict=True)
    if is_relative_to(resolved, home):
        raise ObservationError("fixture root is inside the user home")
    return resolved


def validate_evidence_root(root: Path) -> Path:
    info = root.lstat()
    if not root.name.startswith(EVIDENCE_PREFIX) or stat.S_ISLNK(info.st_mode) \
            or not stat.S_ISDIR(info.st_mode) or info.st_uid != os.geteuid() \
            or stat.S_IMODE(info.st_mode) != 0o700:
        raise ObservationError("evidence root is not an owned private directory")
    return root.resolve(strict=True)


def parse_cpu_seconds(raw: str) -> float:
    value = raw.strip()
    if not value:
        raise ObservationError("missing process CPU time")
    days = 0
    if "-" in value:
        day_text, value = value.split("-", 1)
        days = int(day_text)
    parts = value.split(":")
    if len(parts) == 3:
        hours, minutes, seconds = int(parts[0]), int(parts[1]), float(parts[2])
    elif len(parts) == 2:
        hours, minutes, seconds = 0, int(parts[0]), float(parts[1])
    else:
        raise ObservationError(f"unsupported process CPU time: {raw!r}")
    if min(days, hours, minutes) < 0 or seconds < 0 or minutes >= 60 or seconds >= 60:
        raise ObservationError(f"invalid process CPU time: {raw!r}")
    return (((days * 24) + hours) * 60 + minutes) * 60 + seconds


def pid_executable(pid: int) -> Path:
    buffer = ctypes.create_string_buffer(PROC_PIDPATHINFO_MAXSIZE)
    count = LIBPROC.proc_pidpath(pid, buffer, len(buffer))
    if count <= 0:
        error = ctypes.get_errno()
        raise ObservationError(f"proc_pidpath failed for owned PID {pid}: errno {error}")
    try:
        path = Path(buffer.value.decode("utf-8", errors="strict")).resolve(strict=True)
    except (UnicodeError, OSError) as error:
        raise ObservationError(f"invalid proc_pidpath result: {error}") from error
    return path


def parse_attestation(path: Path, scenario: str, pid: int, *,
                      initial: dict[str, Any] | None = None) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise ObservationError(f"invalid runtime ready document: {error}") from error
    if not isinstance(value, dict) or set(value) != ATTESTATION_KEYS:
        raise ObservationError("runtime attestation has an unexpected shape")
    integer_fields = ("schema", "pid", "settingsRevision", "sceneLeases",
                      "explicitWorkLeases", "scanSessions", "scanActiveWork",
                      "timerScheduledCount", "timerCancelledCount",
                      "observedMonotonicNanoseconds")
    if any(not isinstance(value[field], int) or isinstance(value[field], bool)
           for field in integer_fields):
        raise ObservationError("runtime attestation integer field has the wrong type")
    if not isinstance(value["timerRunning"], bool) \
            or not isinstance(value["allMutationsDenied"], bool) \
            or not isinstance(value["applicationHidden"], bool) \
            or not isinstance(value["scenario"], str):
        raise ObservationError("runtime attestation scalar field has the wrong type")
    expected = SCENARIOS[scenario]
    if value["schema"] != 1 or value["scenario"] != scenario or value["pid"] != pid:
        raise ObservationError("runtime attestation identity does not match the owned launch")
    if value["settingsRevision"] != 1 or value["timerRunning"] != expected["timer"]:
        raise ObservationError("runtime attestation policy/timer state is wrong")
    if any(value[field] != 0 for field in
           ("sceneLeases", "explicitWorkLeases", "scanSessions", "scanActiveWork")):
        raise ObservationError("runtime attestation contains unexpected work")
    if not value["allMutationsDenied"]:
        raise ObservationError("runtime attestation reports changed mutation authority")
    if not value["applicationHidden"]:
        raise ObservationError("runtime observation app is not hidden")
    if scenario == "hidden-off":
        if value["timerScheduledCount"] != 0 or value["timerCancelledCount"] != 0:
            raise ObservationError("hidden-off monitor timer instrumentation is nonzero")
    else:
        if value["timerScheduledCount"] < 1 or value["timerCancelledCount"] != 0:
            raise ObservationError("hidden-authorized monitor timer instrumentation is invalid")
    if value["observedMonotonicNanoseconds"] < 0:
        raise ObservationError("runtime attestation monotonic time is invalid")
    if initial is not None:
        stable = ("scenario", "pid", "settingsRevision", "timerRunning", "sceneLeases",
                  "explicitWorkLeases", "scanSessions", "scanActiveWork",
                  "allMutationsDenied", "timerScheduledCount", "timerCancelledCount",
                  "applicationHidden")
        if any(value[field] != initial[field] for field in stable):
            raise ObservationError("runtime final state changed during the observation window")
        minimum = SCENARIOS[scenario]["duration"] * 1_000_000_000
        if value["observedMonotonicNanoseconds"] - initial["observedMonotonicNanoseconds"] < minimum:
            raise ObservationError("runtime final attestation was published before the fixed window")
    return value


def run_tool(arguments: list[str], *, timeout: float = 10,
             stdout_path: Path | None = None, stderr_path: Path | None = None,
             cwd: Path | None = None) -> subprocess.CompletedProcess:
    stdout: Any = subprocess.PIPE if stdout_path is None else stdout_path.open("wb")
    stderr: Any = subprocess.PIPE if stderr_path is None else stderr_path.open("wb")
    try:
        return subprocess.run(arguments, stdin=subprocess.DEVNULL, stdout=stdout, stderr=stderr,
                              timeout=timeout, check=False, cwd=cwd)
    finally:
        if stdout_path is not None:
            stdout.close()
        if stderr_path is not None:
            stderr.close()


def validate_xcresult(result_bundle: Path, cases: list[str], evidence: Path,
                      label: str) -> None:
    command = [
        sys.executable, str(REPO_ROOT / "scripts/verification/check-test-results.py"),
        "xcode", str(result_bundle), "--minimum", str(len(cases)),
    ]
    for case in cases:
        command.extend(["--require-case", case])
    result = run_tool(command, timeout=60,
                      stdout_path=evidence / f"{label}-result-check.stdout",
                      stderr_path=evidence / f"{label}-result-check.stderr", cwd=REPO_ROOT)
    if result.returncode != 0:
        raise ObservationError(f"XCTest result validation failed: {label}")


def process_identity(pid: int) -> dict[str, Any]:
    result = run_tool([str(TOOLS["ps"]), "-p", str(pid), "-o", "pid=,rss=,time=,lstart=,command="],
                      timeout=5)
    text = result.stdout.decode("utf-8", errors="strict").strip()
    if result.returncode != 0 or not text:
        raise ObservationError("owned runtime process is unavailable")
    match = re.match(r"^\s*(\d+)\s+(\d+)\s+(\S+)\s+(.{24})\s+(.+)$", text)
    if not match:
        raise ObservationError(f"unexpected ps identity row: {text!r}")
    return {
        "pid": int(match.group(1)),
        "rssKiB": int(match.group(2)),
        "cpuSeconds": parse_cpu_seconds(match.group(3)),
        "processStart": match.group(4),
        "command": match.group(5),
        "executable": str(pid_executable(pid)),
    }


def descriptor_counts(pid: int) -> tuple[int, int]:
    result = run_tool([str(TOOLS["lsof"]), "-nP", "-a", "-p", str(pid), "-Ff"], timeout=10)
    if result.returncode not in (0, 1):
        raise ObservationError("lsof failed for the owned runtime process")
    lines = result.stdout.decode("utf-8", errors="strict").splitlines()
    numeric = sum(1 for line in lines if re.fullmatch(r"f\d+[a-zA-Z]*", line))
    special = sum(1 for line in lines if line in {"fcwd", "frtd", "ftxt"})
    return numeric, special


def child_pids(pid: int) -> list[int]:
    pending = [pid]
    found: set[int] = set()
    while pending:
        parent = pending.pop()
        result = run_tool([str(TOOLS["pgrep"]), "-P", str(parent)], timeout=5)
        if result.returncode == 1:
            continue
        if result.returncode != 0:
            raise ObservationError("pgrep failed for the owned runtime process")
        children = {int(line) for line in result.stdout.decode("ascii").splitlines()
                    if line.strip().isdigit()}
        for child in children - found:
            found.add(child)
            pending.append(child)
    return sorted(found)


def wait_for_final(root: Path, scenario: str, pid: int, initial: dict[str, Any],
                   timeout: float = 15) -> dict[str, Any]:
    path = root / "state/runtime-final.json"
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if path.is_file():
            validate_owned_document(path)
            return parse_attestation(path, scenario, pid, initial=initial)
        time.sleep(0.05)
    raise ObservationError("runtime host did not publish its final document")


def sample_process(pid: int, executable: Path, expected_start: str,
                   duration: int, evidence: Path) -> tuple[list[dict[str, Any]], set[int]]:
    samples: list[dict[str, Any]] = []
    observed_children: set[int] = set()
    beginning = time.monotonic()
    deadline = beginning + duration
    next_sample = beginning
    index = 0
    numeric_fds: int | None = None
    special_refs: int | None = None
    while True:
        if process_is_gone(pid):
            raise ObservationError("runtime host exited during observation")
        started = time.monotonic()
        identity = process_identity(pid)
        if identity["pid"] != pid or identity["processStart"] != expected_start \
                or Path(identity["executable"]) != executable:
            raise ObservationError("runtime PID identity changed")
        children = child_pids(pid)
        observed_children.update(children)
        fd_sampled = index % 5 == 0 or started >= deadline
        if fd_sampled:
            numeric_fds, special_refs = descriptor_counts(pid)
        if numeric_fds is None or special_refs is None:
            raise ObservationError("initial file-descriptor sample was not captured")
        samples.append({
            "index": index,
            "elapsedSeconds": started - beginning,
            "rssKiB": identity["rssKiB"],
            "cpuSeconds": identity["cpuSeconds"],
            "fdCount": numeric_fds,
            "specialFileReferences": special_refs,
            "fdSampled": fd_sampled,
            "childPIDs": children,
        })
        index += 1
        if started >= deadline:
            break
        next_sample += 1.0
        time.sleep(max(0, min(next_sample, deadline) - time.monotonic()))
    (evidence / "samples.json").write_text(json.dumps(samples, indent=2) + "\n", encoding="utf-8")
    return samples, observed_children


def start_nettop(pid: int, duration: int, evidence: Path) -> subprocess.Popen:
    stdout = (evidence / "nettop.stdout").open("wb")
    stderr = (evidence / "nettop.stderr").open("wb")
    process = subprocess.Popen([
        str(TOOLS["nettop"]), "-n", "-P", "-x", "-p", str(pid),
        "-L", str(duration), "-s", "1", "-J", "bytes_in,bytes_out",
    ], stdin=subprocess.DEVNULL, stdout=stdout, stderr=stderr)
    process._tidy_streams = (stdout, stderr)  # type: ignore[attr-defined]
    return process


def finish_nettop(process: subprocess.Popen, timeout: float = 10) -> int:
    try:
        return process.wait(timeout=timeout)
    finally:
        for stream in getattr(process, "_tidy_streams", ()):
            stream.close()


def stop_nettop(process: subprocess.Popen, timeout: float = 10) -> int:
    if process.poll() is None:
        process.terminate()
    try:
        return process.wait(timeout=timeout)
    finally:
        for stream in getattr(process, "_tidy_streams", ()):
            stream.close()


def parse_nettop_counters(path: Path) -> tuple[int, int, int]:
    rows = 0
    maximum_in = 0
    maximum_out = 0
    for line in path.read_text(encoding="utf-8").splitlines():
        fields = [field.strip() for field in line.split(",")]
        if len(fields) < 3 or fields[0] == "" or fields[1] == "bytes_in":
            continue
        try:
            bytes_in = int(fields[1])
            bytes_out = int(fields[2])
        except ValueError:
            continue
        rows += 1
        maximum_in = max(maximum_in, bytes_in)
        maximum_out = max(maximum_out, bytes_out)
    return rows, maximum_in, maximum_out


def run_nettop_positive_control(evidence: Path) -> dict[str, Any]:
    code = """
import socket, time
server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
server.bind(("127.0.0.1", 0)); server.listen(1)
client = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
client.connect(server.getsockname()); accepted, _ = server.accept()
time.sleep(1.0)
payload = b"T" * 65536
total = 0
for _ in range(24):
    client.sendall(payload)
    remaining = len(payload)
    while remaining:
        remaining -= len(accepted.recv(remaining))
    total += len(payload)
    time.sleep(0.15)
print(total, flush=True)
time.sleep(1.0)
"""
    child_stdout = (evidence / "positive-control.stdout").open("wb")
    child_stderr = (evidence / "positive-control.stderr").open("wb")
    child = subprocess.Popen([sys.executable, "-c", code], stdin=subprocess.DEVNULL,
                             stdout=child_stdout, stderr=child_stderr)
    nettop_stdout = (evidence / "positive-control.nettop.csv").open("wb")
    nettop_stderr = (evidence / "positive-control.nettop.stderr").open("wb")
    nettop = subprocess.Popen([
        str(TOOLS["nettop"]), "-n", "-P", "-x", "-p", str(child.pid),
        "-L", "7", "-s", "1", "-J", "bytes_in,bytes_out",
    ], stdin=subprocess.DEVNULL, stdout=nettop_stdout, stderr=nettop_stderr)
    try:
        child_exit = child.wait(timeout=10)
        nettop_exit = nettop.wait(timeout=12)
    finally:
        for stream in (child_stdout, child_stderr, nettop_stdout, nettop_stderr):
            stream.close()
        if child.poll() is None:
            child.terminate()
        if nettop.poll() is None:
            nettop.terminate()
    rows, maximum_in, maximum_out = parse_nettop_counters(
        evidence / "positive-control.nettop.csv")
    result = {
        "traffic": "self-owned loopback TCP only",
        "helperPID": child.pid,
        "helperExit": child_exit,
        "nettopExit": nettop_exit,
        "observedRows": rows,
        "maximumBytesIn": maximum_in,
        "maximumBytesOut": maximum_out,
        "positiveCounterObserved": maximum_in > 0 and maximum_out > 0,
    }
    (evidence / "positive-control.json").write_text(
        json.dumps(result, indent=2) + "\n", encoding="utf-8")
    if child_exit != 0 or nettop_exit != 0 or not result["positiveCounterObserved"]:
        raise ObservationError("nettop loopback positive control failed")
    return result


def run_footprint(pid: int, evidence: Path) -> int:
    return run_tool([
        str(TOOLS["footprint"]), "--pid", str(pid), "--noCategories",
        "--format", "bytes", "--json", str(evidence / "footprint.json"),
    ], timeout=30, stdout_path=evidence / "footprint.stdout",
        stderr_path=evidence / "footprint.stderr").returncode


def summarize(scenario: str, app: Path, executable: Path, ready: dict[str, Any],
              final: dict[str, Any], positive_control: dict[str, Any],
              source_state: dict[str, Any], artifact: dict[str, Any], host: dict[str, Any],
              samples: list[dict[str, Any]], children: set[int], nettop_exit: int,
              footprint_exit: int, evidence: Path) -> dict[str, Any]:
    if not samples:
        raise ObservationError("observation produced no process samples")
    cpu_delta = samples[-1]["cpuSeconds"] - samples[0]["cpuSeconds"]
    span = samples[-1]["elapsedSeconds"] - samples[0]["elapsedSeconds"]
    nettop_rows, maximum_in, maximum_out = parse_nettop_counters(evidence / "nettop.stdout")
    footprint_file = evidence / "footprint.json"
    metric_status = {
        "networkCounters": "verified" if nettop_exit == 0 else "unverified-tool-failure",
        "physicalFootprint": "verified" if footprint_exit == 0 and footprint_file.is_file()
            else "unverified-tool-failure",
    }
    summary = {
        "schema": 1,
        "scenario": scenario,
        "sourceRevision": source_state["head"],
        "sourceWIPState": source_state,
        "artifactManifest": artifact,
        "host": host,
        "runtimeApp": str(app),
        "runtimeExecutable": str(executable),
        "pid": ready["pid"],
        "sampleCount": len(samples),
        "sampleSpanSeconds": span,
        "rssMinimumKiB": min(sample["rssKiB"] for sample in samples),
        "rssMaximumKiB": max(sample["rssKiB"] for sample in samples),
        "fdMinimum": min(sample["fdCount"] for sample in samples if sample["fdSampled"]),
        "fdMaximum": max(sample["fdCount"] for sample in samples if sample["fdSampled"]),
        "specialFileReferencesMinimum": min(sample["specialFileReferences"] for sample in samples
                                             if sample["fdSampled"]),
        "specialFileReferencesMaximum": max(sample["specialFileReferences"] for sample in samples
                                             if sample["fdSampled"]),
        "cpuDeltaSeconds": cpu_delta,
        "cpuPercentOfOneCore": (cpu_delta / span * 100) if span > 0 else None,
        "observedChildPIDs": sorted(children),
        "nettopExit": nettop_exit,
        "nettopObservedRows": nettop_rows,
        "nettopMaximumBytesIn": maximum_in,
        "nettopMaximumBytesOut": maximum_out,
        "footprintExit": footprint_exit,
        "metricStatus": metric_status,
        "ready": ready,
        "final": final,
        "positiveControl": positive_control,
        "claims": "bounded current-host diagnostic only",
    }
    (evidence / "summary.json").write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    return summary


def markdown_summary(summary: dict[str, Any]) -> str:
    return "\n".join([
        f"# R13 {summary['scenario']} current-host observation",
        "",
        "This is a bounded current-host diagnostic. It is not reference-hardware, supported-OS,",
        "human accessibility, privacy-purpose, package, or release acceptance.",
        "",
        f"- Source revision: `{summary['sourceRevision']}`",
        f"- Samples: {summary['sampleCount']} over {summary['sampleSpanSeconds']:.3f} seconds",
        f"- RSS: {summary['rssMinimumKiB']}–{summary['rssMaximumKiB']} KiB",
        f"- CPU delta: {summary['cpuDeltaSeconds']:.3f} seconds "
        f"({summary['cpuPercentOfOneCore']:.4f}% of one core)",
        f"- File descriptors: {summary['fdMinimum']}–{summary['fdMaximum']}",
        f"- Sampled child PIDs: {summary['observedChildPIDs']}",
        f"- nettop exit: {summary['nettopExit']}; footprint exit: {summary['footprintExit']}",
        f"- nettop rows: {summary['nettopObservedRows']}; max bytes in/out: "
        f"{summary['nettopMaximumBytesIn']}/{summary['nettopMaximumBytesOut']}",
        f"- Metric status: {summary['metricStatus']}",
        "",
        "The ready attestation was written once after fixed policy settlement. Sampling the",
        "attestation did not create a repeating monitor, scan, or command in the app.",
        "Zero sampled network rows are only a bounded observation. A failed observer marks the",
        "network metric unverified and can never support a zero-network claim.",
        "",
    ])


def fixture_root_snapshot() -> set[Path]:
    roots: set[Path] = set()
    for parent in canonical_temporary_roots():
        try:
            entries = list(parent.iterdir())
        except OSError as error:
            raise ObservationError(f"could not enumerate canonical temporary roots: {error}") from error
        for entry in entries:
            if entry.name.startswith(FIXTURE_PREFIX):
                roots.add(entry.absolute())
    return roots


def wait_for_runtime_pid(executable: Path, before: set[int], runner: subprocess.Popen,
                         timeout: float = 30) -> tuple[int, dict[str, Any]]:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if runner.poll() is not None:
            raise ObservationError("xcodebuild exited before launching the runtime host")
        candidates = [pid for pid in matching_runtime_pids(executable) if pid not in before]
        if len(candidates) > 1:
            raise ObservationError("more than one matching runtime host launched")
        if candidates:
            identity = process_identity(candidates[0])
            if Path(identity["executable"]) != executable:
                raise ObservationError("runtime executable identity does not match")
            return candidates[0], identity
        time.sleep(0.05)
    raise ObservationError("xcodebuild did not launch the runtime host")


def validate_owned_document(path: Path) -> None:
    info = path.lstat()
    if stat.S_ISLNK(info.st_mode) or not stat.S_ISREG(info.st_mode) \
            or info.st_uid != os.geteuid() or stat.S_IMODE(info.st_mode) != 0o600 \
            or info.st_nlink != 1:
        raise ObservationError("runtime document identity or permissions are unsafe")


def wait_for_hidden_ready_root(before: set[Path], scenario: str, pid: int,
                               timeout: float = 30) -> tuple[Path, dict[str, Any]]:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        matches: list[tuple[Path, dict[str, Any]]] = []
        for candidate in fixture_root_snapshot() - before:
            try:
                root = validate_fixture_root(candidate)
                path = root / "state/runtime-ready.json"
                if not path.exists():
                    continue
                validate_owned_document(path)
                value = parse_attestation(path, scenario, pid)
                matches.append((root, value))
            except (ObservationError, OSError):
                continue
        if len(matches) > 1:
            raise ObservationError("more than one runtime root matches the owned launch")
        if matches:
            return matches[0]
        time.sleep(0.05)
    raise ObservationError("runtime host did not publish its ready document")


def publish_owned_signal(root: Path, name: str, payload: bytes) -> None:
    if name not in {"runtime-observation-observed", "runtime-performance-proceed",
                    "runtime-performance-observed"}:
        raise ObservationError("unsupported external observation signal")
    root = validate_fixture_root(root)
    state = root / "state"
    state_info = state.lstat()
    if stat.S_ISLNK(state_info.st_mode) or not stat.S_ISDIR(state_info.st_mode) \
            or state_info.st_uid != os.geteuid() or stat.S_IMODE(state_info.st_mode) != 0o700:
        raise ObservationError("runtime state directory is unsafe")
    directory = os.open(state, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | os.O_CLOEXEC)
    temporary = f".external-observer-{os.urandom(16).hex()}"
    descriptor = -1
    try:
        descriptor = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL
                             | os.O_NOFOLLOW | os.O_CLOEXEC, 0o600, dir_fd=directory)
        written = 0
        while written < len(payload):
            count = os.write(descriptor, payload[written:])
            if count <= 0:
                raise ObservationError("external observation signal write failed")
            written += count
        os.fsync(descriptor)
        os.close(descriptor)
        descriptor = -1
        rename = LIBC.renameatx_np
        rename.argtypes = [ctypes.c_int, ctypes.c_char_p, ctypes.c_int,
                           ctypes.c_char_p, ctypes.c_uint]
        rename.restype = ctypes.c_int
        if rename(directory, temporary.encode(), directory, name.encode(), RENAME_EXCL) != 0:
            error = ctypes.get_errno()
            raise ObservationError(f"exclusive signal publication failed: errno {error}")
        os.fsync(directory)
    finally:
        if descriptor >= 0:
            os.close(descriptor)
        try:
            os.unlink(temporary, dir_fd=directory)
        except FileNotFoundError:
            pass
        os.close(directory)


def terminate_pid_owned(pid: int, executable: Path, expected_start: str) -> None:
    identity = process_identity(pid)
    if identity["processStart"] != expected_start or Path(identity["executable"]) != executable:
        raise ObservationError("runtime PID identity changed before termination")
    os.kill(pid, 15)
    deadline = time.monotonic() + 15
    while time.monotonic() < deadline:
        if process_is_gone(pid):
            return
        time.sleep(0.05)
    raise ObservationError("runtime PID did not terminate")


def hidden_test_command(scenario: str, app: Path, evidence: Path) -> list[str]:
    derived_data = derived_data_for_runtime_app(app)
    configuration = app.parent.name
    if configuration not in {"Debug", "Release"}:
        raise ObservationError("runtime app has an unsupported build configuration")
    test_case = SCENARIOS[scenario]["testCase"]
    return [
        "/usr/bin/xcodebuild", "-project", str(REPO_ROOT / "Tidy.xcodeproj"),
        "-scheme", "TidyProductionNativeUITests", "-configuration", configuration,
        "-destination", f"platform=macOS,arch={os.uname().machine}", "-jobs", "2",
        "-derivedDataPath", str(derived_data),
        "-resultBundlePath", str(evidence / "hidden-observation.xcresult"),
        f"-only-testing:TidyProductionNativeUITests/ProductionObservationRuntimeUITests/{test_case}",
        "test-without-building", "CODE_SIGN_IDENTITY=-", "CODE_SIGNING_ALLOWED=YES",
    ]


PERFORMANCE_READY_KEYS = {
    "schema", "scenario", "pid", "fixtureFiles", "fixtureLogicalBytes",
    "fixtureAllocatedBytes", "registrySessions", "registryActiveWork",
    "schedulerActive", "schedulerQueued", "schedulerLiveSessions",
    "explicitLeases", "indexWatchActive", "allMutationsDenied",
    "witnessUnchanged", "settled",
}
PERFORMANCE_50K_KEYS = {
    "schema", "scenario", "pid", "fixtureDirectories", "fixtureFiles",
    "fixtureLogicalBytes", "fixtureAllocatedBytes", "requestNanoseconds",
    "firstRegistryProgressNanoseconds", "firstRenderableUsefulResultNanoseconds",
    "terminalNanoseconds", "workersSettledNanoseconds", "terminal",
    "completeCoverage", "processedEntries", "metadataVisits", "schedulerWorkers",
    "registrySessions", "registryActiveWork", "retainedTerminalStates",
    "allMutationsDenied", "witnessUnchanged", "settled", "passed",
}
PERFORMANCE_CYCLE_KEYS = {
    "schema", "scenario", "pid", "cycleCount", "cancelRequested",
    "terminalCancelled", "completedBeforeCancel", "otherTerminal",
    "maxCancelToTerminalNanoseconds", "maxCancelToSettledNanoseconds",
    "registrySessions", "registryActiveWork", "retainedTerminalStates",
    "schedulerActive", "schedulerQueued", "schedulerLiveSessions",
    "explicitLeases", "indexWatchActive", "allMutationsDenied",
    "witnessUnchanged", "settled", "passed",
}


def load_exact_json(path: Path, keys: set[str]) -> dict[str, Any]:
    validate_owned_document(path)
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise ObservationError(f"invalid runtime JSON document: {error}") from error
    if not isinstance(value, dict) or set(value) != keys:
        raise ObservationError("runtime JSON document has an unexpected shape")
    return value


def exact_integer(value: dict[str, Any], key: str) -> int:
    result = value[key]
    if not isinstance(result, int) or isinstance(result, bool):
        raise ObservationError(f"runtime JSON field is not an integer: {key}")
    return result


def exact_boolean(value: dict[str, Any], key: str) -> bool:
    result = value[key]
    if not isinstance(result, bool):
        raise ObservationError(f"runtime JSON field is not a boolean: {key}")
    return result


def validate_performance_ready(value: dict[str, Any], scenario: str, pid: int) -> None:
    integer_fields = PERFORMANCE_READY_KEYS - {
        "scenario", "indexWatchActive", "allMutationsDenied", "witnessUnchanged", "settled",
    }
    for field in integer_fields:
        if exact_integer(value, field) < 0:
            raise ObservationError(f"performance ready integer is negative: {field}")
    for field in ("indexWatchActive", "allMutationsDenied", "witnessUnchanged", "settled"):
        exact_boolean(value, field)
    if not isinstance(value["scenario"], str) or value["schema"] != 1 \
            or value["scenario"] != scenario or value["pid"] != pid:
        raise ObservationError("performance ready identity is invalid")
    if value["fixtureFiles"] != 50_000 or value["fixtureLogicalBytes"] != 0 \
            or value["fixtureAllocatedBytes"] < 0:
        raise ObservationError("performance ready fixture measurement is invalid")
    zeros = ("registrySessions", "registryActiveWork", "schedulerActive", "schedulerQueued",
             "schedulerLiveSessions", "explicitLeases")
    if any(value[field] != 0 for field in zeros) or value["indexWatchActive"] \
            or not value["allMutationsDenied"] or not value["witnessUnchanged"] \
            or not value["settled"]:
        raise ObservationError("performance ready baseline is not settled")


def validate_performance_final(value: dict[str, Any], scenario: str, pid: int) -> None:
    expected_keys = PERFORMANCE_50K_KEYS if scenario == "performance-50k" \
        else PERFORMANCE_CYCLE_KEYS
    if set(value) != expected_keys:
        raise ObservationError("performance final document has an unexpected shape")
    boolean_fields = {"allMutationsDenied", "witnessUnchanged", "settled", "passed"}
    if scenario == "performance-50k":
        boolean_fields.add("completeCoverage")
    string_fields = {"scenario"}
    if scenario == "performance-50k":
        string_fields.add("terminal")
    for field in expected_keys - boolean_fields - string_fields:
        if exact_integer(value, field) < 0:
            raise ObservationError(f"performance final integer is negative: {field}")
    for field in boolean_fields:
        exact_boolean(value, field)
    if any(not isinstance(value[field], str) for field in string_fields) \
            or value["schema"] != 1 or value["scenario"] != scenario or value["pid"] != pid:
        raise ObservationError("performance final identity is invalid")
    if not value["passed"] or not value["allMutationsDenied"] \
            or not value["witnessUnchanged"] or not value["settled"]:
        raise ObservationError("performance final document reports a failed invariant")
    if scenario == "performance-50k":
        ordering = [value["requestNanoseconds"], value["firstRegistryProgressNanoseconds"],
                    value["firstRenderableUsefulResultNanoseconds"], value["terminalNanoseconds"],
                    value["workersSettledNanoseconds"]]
        if ordering != sorted(ordering) or value["terminal"] != "complete" \
                or not value["completeCoverage"] or value["fixtureDirectories"] != 500 \
                or value["fixtureFiles"] != 50_000 or value["fixtureLogicalBytes"] != 0 \
                or value["processedEntries"] < 50_000 or value["metadataVisits"] < 50_000 \
                or value["registrySessions"] != 1 or value["retainedTerminalStates"] != 1 \
                or value["registryActiveWork"] != 0:
            raise ObservationError("50k performance final contract failed")
        if value["firstRenderableUsefulResultNanoseconds"] - value["requestNanoseconds"] \
                > 1_000_000_000 or value["workersSettledNanoseconds"] \
                - value["requestNanoseconds"] > 10_000_000_000:
            raise ObservationError("50k performance timing threshold failed")
    else:
        if value["cycleCount"] != 20 or value["cancelRequested"] != 20 \
                or value["terminalCancelled"] != 20 or value["completedBeforeCancel"] != 0 \
                or value["otherTerminal"] != 0 or value["registrySessions"] != 20 \
                or value["retainedTerminalStates"] != 20 \
                or any(value[field] != 0 for field in
                       ("registryActiveWork", "schedulerActive", "schedulerQueued",
                        "schedulerLiveSessions", "explicitLeases")) \
                or value["indexWatchActive"]:
            raise ObservationError("active-cancel performance final contract failed")
        if value["maxCancelToTerminalNanoseconds"] > 500_000_000 \
                or value["maxCancelToSettledNanoseconds"] > 500_000_000:
            raise ObservationError("active-cancel timing threshold failed")


def performance_test_command(scenario: str, app: Path, evidence: Path) -> list[str]:
    derived_data = derived_data_for_runtime_app(app)
    configuration = app.parent.name
    if configuration not in {"Debug", "Release"}:
        raise ObservationError("runtime app has an unsupported build configuration")
    test_case = PERFORMANCE_SCENARIOS[scenario]["testCase"]
    return [
        "/usr/bin/xcodebuild", "-project", str(REPO_ROOT / "Tidy.xcodeproj"),
        "-scheme", "TidyProductionNativeUITests", "-configuration", configuration,
        "-destination", f"platform=macOS,arch={os.uname().machine}", "-jobs", "2",
        "-derivedDataPath", str(derived_data),
        "-resultBundlePath", str(evidence / "performance.xcresult"),
        f"-only-testing:TidyProductionNativeUITests/ProductionPerformanceRuntimeUITests/{test_case}",
        "test-without-building", "CODE_SIGN_IDENTITY=-", "CODE_SIGNING_ALLOWED=YES",
    ]


def wait_for_performance_ready_root(before: set[Path], scenario: str, pid: int,
                                    timeout: float = 180) -> tuple[Path, dict[str, Any]]:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        matches: list[tuple[Path, dict[str, Any]]] = []
        for candidate in fixture_root_snapshot() - before:
            try:
                root = validate_fixture_root(candidate)
                path = root / "state/runtime-performance-ready.json"
                if not path.exists():
                    continue
                value = load_exact_json(path, PERFORMANCE_READY_KEYS)
                validate_performance_ready(value, scenario, pid)
                matches.append((root, value))
            except (ObservationError, OSError):
                continue
        if len(matches) > 1:
            raise ObservationError("more than one performance root matches the owned launch")
        if matches:
            return matches[0]
        time.sleep(0.05)
    raise ObservationError("runtime host did not publish performance readiness")


def observe_performance(scenario: str, runtime_app: Path) -> Path:
    app, executable = validate_runtime_app(runtime_app)
    evidence = Path(tempfile.mkdtemp(prefix=EVIDENCE_PREFIX + scenario + "-", dir="/private/tmp"))
    os.chmod(evidence, 0o700)
    evidence = validate_evidence_root(evidence)
    artifact_start = artifact_manifest(app)
    source_start = source_wip_state()
    host = host_context()
    for name, value in (("artifact-manifest-start.json", artifact_start),
                        ("source-wip-start.json", source_start), ("host.json", host)):
        (evidence / name).write_text(json.dumps(value, indent=2) + "\n", encoding="utf-8")
    positive_control = run_nettop_positive_control(evidence)
    existing_pids = set(matching_runtime_pids(executable))
    if existing_pids:
        raise ObservationError("runtime host is already running before performance observation")
    existing_roots = fixture_root_snapshot()
    stdout = (evidence / "xcodebuild.stdout").open("wb")
    stderr = (evidence / "xcodebuild.stderr").open("wb")
    runner = subprocess.Popen(performance_test_command(scenario, app, evidence), cwd=REPO_ROOT,
                              stdin=subprocess.DEVNULL, stdout=stdout, stderr=stderr)
    pid: int | None = None
    identity: dict[str, Any] | None = None
    root: Path | None = None
    capture: dict[str, Any] | None = None
    observed_published = False
    completed = False
    try:
        pid, identity = wait_for_runtime_pid(executable, existing_pids, runner, timeout=120)
        root, ready = wait_for_performance_ready_root(existing_roots, scenario, pid)
        (evidence / "ready.json").write_text(json.dumps(ready, indent=2) + "\n",
                                              encoding="utf-8")
        capture = start_process_capture(pid, "runtime", None, evidence)
        beginning = time.monotonic()
        observed_children: set[int] = set()
        sample_capture(capture, 0.0, fd_every=10)
        publish_owned_signal(root, "runtime-performance-proceed",
                             b"TIDY_RUNTIME_PROCEED_V1\n")
        final_path = root / "state" / PERFORMANCE_SCENARIOS[scenario]["finalName"]
        error_path = root / "state/runtime-performance-error.json"
        deadline = time.monotonic() + PERFORMANCE_SCENARIOS[scenario]["timeout"]
        while not final_path.exists() and not error_path.exists():
            if runner.poll() is not None:
                raise ObservationError("performance XCTest exited before final publication")
            if time.monotonic() >= deadline:
                raise ObservationError("performance observation exceeded its fixed deadline")
            sample_capture(capture, time.monotonic() - beginning, fd_every=10)
            observed_children.update(child_pids(pid))
            time.sleep(0.1)
        sample_capture(capture, time.monotonic() - beginning, fd_every=10)
        if error_path.exists():
            error = load_exact_json(error_path, {"schema", "scenario", "pid", "message"})
            raise ObservationError(f"runtime performance error: {error.get('message')}")
        keys = PERFORMANCE_50K_KEYS if scenario == "performance-50k" \
            else PERFORMANCE_CYCLE_KEYS
        final = load_exact_json(final_path, keys)
        validate_performance_final(final, scenario, pid)
        footprint_exit = run_footprint(pid, evidence)
        process_row = finish_process_capture(capture)
        capture = None
        process_row["observedChildPIDs"] = sorted(observed_children)
        publish_owned_signal(root, "runtime-performance-observed",
                             b"TIDY_RUNTIME_OBSERVED_V1\n")
        observed_published = True
        try:
            runner_exit = runner.wait(timeout=60)
        except subprocess.TimeoutExpired as error:
            raise ObservationError("performance XCTest did not finish") from error
        if runner_exit != 0 or not (evidence / "performance.xcresult").is_dir():
            raise ObservationError("performance XCTest failed")
        validate_xcresult(evidence / "performance.xcresult",
                          [PERFORMANCE_SCENARIOS[scenario]["testCase"]],
                          evidence, "performance")
        cleanup_deadline = time.monotonic() + 15
        while root.exists() and time.monotonic() < cleanup_deadline:
            time.sleep(0.05)
        if root.exists():
            raise ObservationError("performance XCTest did not remove its fixture root")
        artifact_end = artifact_manifest(app)
        source_end = source_wip_state()
        if artifact_end != artifact_start or source_end != source_start:
            raise ObservationError("artifact or source WIP changed during performance observation")
        summary = {
            "schema": 1, "mode": scenario, "sourceWIPState": source_start,
            "artifactManifest": artifact_start, "host": host, "ready": ready,
            "final": final, "process": process_row, "positiveControl": positive_control,
            "footprintExit": footprint_exit,
            "physicalFootprintStatus": "verified" if footprint_exit == 0
                and (evidence / "footprint.json").is_file() else "unverified-tool-failure",
            "xcodebuildExit": runner_exit, "resultBundlePresent": True,
            "claims": "bounded current-host production-scene diagnostic only",
        }
        (evidence / "summary.json").write_text(json.dumps(summary, indent=2) + "\n",
                                                encoding="utf-8")
        completed = True
        return evidence
    except Exception:
        (evidence / "FAILED").write_text("observation failed; inspect retained evidence\n",
                                          encoding="utf-8")
        raise
    finally:
        if capture is not None:
            try:
                finish_process_capture(capture)
            except (ObservationError, OSError):
                pass
        if root is not None and not observed_published and root.exists():
            try:
                publish_owned_signal(root, "runtime-performance-observed",
                                     b"TIDY_RUNTIME_OBSERVED_V1\n")
            except (ObservationError, OSError):
                pass
        if not completed and pid is not None and identity is not None and not process_is_gone(pid):
            try:
                terminate_pid_owned(pid, executable, identity["processStart"])
            except (ObservationError, OSError):
                pass
        if runner.poll() is None:
            runner.terminate()
            try:
                runner.wait(timeout=15)
            except subprocess.TimeoutExpired:
                pass
        stdout.close()
        stderr.close()
        if not completed and root is not None and root.exists():
            (evidence / "retained-root.txt").write_text(str(root) + "\n", encoding="utf-8")


def observe(scenario: str, runtime_app: Path) -> Path:
    app, executable = validate_runtime_app(runtime_app)
    for name, tool in TOOLS.items():
        if not tool.is_file():
            raise ObservationError(f"required observer tool is missing: {name}")
    evidence = Path(tempfile.mkdtemp(prefix=EVIDENCE_PREFIX, dir="/private/tmp"))
    os.chmod(evidence, 0o700)
    evidence = validate_evidence_root(evidence)
    artifact_start = artifact_manifest(app)
    source_start = source_wip_state()
    host = host_context()
    for name, value in (("artifact-manifest-start.json", artifact_start),
                        ("source-wip-start.json", source_start), ("host.json", host)):
        (evidence / name).write_text(json.dumps(value, indent=2) + "\n", encoding="utf-8")
    positive_control = run_nettop_positive_control(evidence)
    existing_pids = set(matching_runtime_pids(executable))
    if existing_pids:
        raise ObservationError("runtime host is already running before hidden observation")
    existing_roots = fixture_root_snapshot()
    stdout = (evidence / "xcodebuild.stdout").open("wb")
    stderr = (evidence / "xcodebuild.stderr").open("wb")
    runner = subprocess.Popen(hidden_test_command(scenario, app, evidence), cwd=REPO_ROOT,
                              stdin=subprocess.DEVNULL, stdout=stdout, stderr=stderr)
    pid: int | None = None
    identity: dict[str, Any] | None = None
    root: Path | None = None
    nettop: subprocess.Popen | None = None
    completed = False
    try:
        pid, identity = wait_for_runtime_pid(executable, existing_pids, runner)
        root, ready = wait_for_hidden_ready_root(existing_roots, scenario, pid)
        (evidence / "ready.json").write_text(json.dumps(ready, indent=2) + "\n",
                                              encoding="utf-8")
        nettop = start_nettop(pid, SCENARIOS[scenario]["duration"], evidence)
        samples, children = sample_process(pid, executable, identity["processStart"],
                                           SCENARIOS[scenario]["duration"], evidence)
        final = wait_for_final(root, scenario, pid, ready)
        validate_owned_document(root / "state/runtime-final.json")
        (evidence / "final.json").write_text(json.dumps(final, indent=2) + "\n",
                                              encoding="utf-8")
        nettop_exit = finish_nettop(nettop)
        footprint_exit = run_footprint(pid, evidence)
        publish_owned_signal(root, "runtime-observation-observed",
                             b"TIDY_RUNTIME_OBSERVATION_OBSERVED_V1\n")
        try:
            runner_exit = runner.wait(timeout=30)
        except subprocess.TimeoutExpired as error:
            raise ObservationError("hidden observation XCTest did not finish") from error
        if runner_exit != 0 or not (evidence / "hidden-observation.xcresult").is_dir():
            raise ObservationError("hidden observation XCTest failed")
        validate_xcresult(evidence / "hidden-observation.xcresult",
                          [SCENARIOS[scenario]["testCase"]], evidence,
                          "hidden-observation")
        cleanup_deadline = time.monotonic() + 15
        while root.exists() and time.monotonic() < cleanup_deadline:
            time.sleep(0.05)
        if root.exists():
            raise ObservationError("hidden observation XCTest did not remove its fixture root")
        artifact_end = artifact_manifest(app)
        source_end = source_wip_state()
        if artifact_end != artifact_start or source_end != source_start:
            raise ObservationError("artifact or source WIP changed during observation")
        summary = summarize(scenario, app, executable, ready, final, positive_control,
                            source_start, artifact_start, host, samples, children,
                            nettop_exit, footprint_exit, evidence)
        summary["xcodebuildExit"] = runner_exit
        summary["resultBundlePresent"] = True
        (evidence / "summary.json").write_text(json.dumps(summary, indent=2) + "\n",
                                                encoding="utf-8")
        (evidence / "summary.md").write_text(markdown_summary(summary), encoding="utf-8")
        completed = True
        return evidence
    except Exception:
        (evidence / "FAILED").write_text("observation failed; inspect retained evidence\n",
                                          encoding="utf-8")
        raise
    finally:
        if nettop is not None and nettop.poll() is None:
            stop_nettop(nettop)
        if not completed and pid is not None and identity is not None and not process_is_gone(pid):
            try:
                terminate_pid_owned(pid, executable, identity["processStart"])
                (evidence / "process-cleanup.txt").write_text(
                    "owned runtime process terminated after observer failure\n", encoding="utf-8")
            except (ObservationError, OSError) as cleanup_error:
                (evidence / "process-cleanup.txt").write_text(
                    f"runtime process retained after cleanup failure: {cleanup_error}\n",
                    encoding="utf-8")
        if runner.poll() is None:
            runner.terminate()
            try:
                runner.wait(timeout=15)
            except subprocess.TimeoutExpired:
                pass
        stdout.close()
        stderr.close()
        if not completed and root is not None and root.exists():
            (evidence / "retained-root.txt").write_text(str(root) + "\n", encoding="utf-8")


def derived_data_for_runtime_app(app: Path) -> Path:
    app = app.resolve(strict=True)
    parents = list(app.parents)
    for index, parent in enumerate(parents):
        if parent.name == "Products" and index + 1 < len(parents) \
                and parents[index + 1].name == "Build":
            return parents[index + 2]
    raise ObservationError("runtime app is not inside a DerivedData Build/Products directory")


def matching_runtime_pids(executable: Path) -> list[int]:
    result = run_tool([str(TOOLS["pgrep"]), "-f", "TidyProductionRuntimeHost"], timeout=5)
    if result.returncode == 1:
        return []
    if result.returncode != 0:
        raise ObservationError("could not enumerate runtime-host PIDs")
    matches = []
    for line in result.stdout.decode("ascii").splitlines():
        if not line.strip().isdigit():
            continue
        pid = int(line)
        try:
            if pid_executable(pid) == executable:
                matches.append(pid)
        except ObservationError:
            continue
    return sorted(matches)


def process_is_gone(pid: int) -> bool:
    result = run_tool([str(TOOLS["ps"]), "-p", str(pid), "-o", "pid="], timeout=5)
    return result.returncode != 0 or not result.stdout.strip()


def start_process_capture(pid: int, role: str, parent_pid: int | None,
                          evidence: Path) -> dict[str, Any]:
    identity = process_identity(pid)
    directory = evidence / f"{role}-{pid}-{time.monotonic_ns()}"
    directory.mkdir(mode=0o700)
    return {
        "role": role,
        "parentPID": parent_pid,
        "identity": identity,
        "directory": directory,
        "nettop": start_nettop(pid, 20 * 60, directory),
        "samples": [],
        "finished": False,
    }


def sample_capture(capture: dict[str, Any], elapsed: float, *, fd_every: int = 4) -> None:
    if capture["finished"]:
        return
    pid = capture["identity"]["pid"]
    try:
        identity = process_identity(pid)
    except ObservationError:
        if not process_is_gone(pid):
            raise
        capture["nettopExit"] = stop_nettop(capture["nettop"])
        capture["finished"] = True
        capture["endedNaturally"] = True
        return
    if identity["processStart"] != capture["identity"]["processStart"] \
            or identity["executable"] != capture["identity"]["executable"]:
        raise ObservationError("workflow process PID identity changed")
    if fd_every < 1:
        raise ObservationError("file-descriptor sampling interval is invalid")
    should_sample_fds = len(capture["samples"]) % fd_every == 0
    fd_count: int | None = None
    special_refs: int | None = None
    if should_sample_fds:
        fd_count, special_refs = descriptor_counts(pid)
    capture["samples"].append({
        "elapsedSeconds": elapsed,
        "rssKiB": identity["rssKiB"],
        "cpuSeconds": identity["cpuSeconds"],
        "fdCount": fd_count,
        "specialFileReferences": special_refs,
    })


def finish_process_capture(capture: dict[str, Any]) -> dict[str, Any]:
    if not capture["finished"]:
        pid = capture["identity"]["pid"]
        if not process_is_gone(pid):
            identity = process_identity(pid)
            if identity["processStart"] != capture["identity"]["processStart"] \
                    or identity["executable"] != capture["identity"]["executable"]:
                raise ObservationError("workflow process identity changed before capture stop")
        capture["nettopExit"] = stop_nettop(capture["nettop"])
        capture["finished"] = True
        capture["endedNaturally"] = process_is_gone(pid)
    samples = capture["samples"]
    sample_path = capture["directory"] / "samples.json"
    sample_path.write_text(json.dumps(samples, indent=2) + "\n", encoding="utf-8")
    observed_rows, maximum_in, maximum_out = parse_nettop_counters(
        capture["directory"] / "nettop.stdout")
    fd_samples = [sample["fdCount"] for sample in samples if sample["fdCount"] is not None]
    return {
        "pid": capture["identity"]["pid"],
        "role": capture["role"],
        "parentPID": capture["parentPID"],
        "processStart": capture["identity"]["processStart"],
        "executable": capture["identity"]["executable"],
        "sampleCount": len(samples),
        "rssMaximumKiB": max((sample["rssKiB"] for sample in samples), default=None),
        "fdMinimum": min(fd_samples, default=None),
        "fdMaximum": max(fd_samples, default=None),
        "endedNaturally": capture["endedNaturally"],
        "nettopExit": capture["nettopExit"],
        "nettopStatus": "bounded-capture-intentionally-stopped"
            if capture["nettopExit"] == -15 else
            ("completed" if capture["nettopExit"] == 0 else "unverified-tool-failure"),
        "nettopRows": observed_rows,
        "maximumBytesIn": maximum_in,
        "maximumBytesOut": maximum_out,
    }


def observe_workflow_traffic(runtime_app: Path) -> Path:
    app, executable = validate_runtime_app(runtime_app)
    derived_data = derived_data_for_runtime_app(app)
    evidence = Path(tempfile.mkdtemp(
        prefix=EVIDENCE_PREFIX + "traffic-", dir="/private/tmp"))
    os.chmod(evidence, 0o700)
    evidence = validate_evidence_root(evidence)
    artifact_start = artifact_manifest(app)
    source_start = source_wip_state()
    host = host_context()
    for name, value in (("artifact-manifest-start.json", artifact_start),
                        ("source-wip-start.json", source_start), ("host.json", host)):
        (evidence / name).write_text(json.dumps(value, indent=2) + "\n", encoding="utf-8")
    positive_control = run_nettop_positive_control(evidence)
    result_bundle = evidence / "production-native-ui.xcresult"
    stdout = (evidence / "xcodebuild.stdout").open("wb")
    stderr = (evidence / "xcodebuild.stderr").open("wb")
    command = [
        "/usr/bin/xcodebuild", "-project", str(REPO_ROOT / "Tidy.xcodeproj"),
        "-scheme", "TidyProductionNativeUITests", "-configuration", "Debug",
        "-destination", f"platform=macOS,arch={os.uname().machine}", "-jobs", "2",
        "-derivedDataPath", str(derived_data), "-resultBundlePath", str(result_bundle),
        *[f"-only-testing:TidyProductionNativeUITests/ProductionSceneRuntimeUITests/{case}"
          for case in TRAFFIC_CASES],
        "test-without-building", "CODE_SIGN_IDENTITY=-", "CODE_SIGNING_ALLOWED=YES",
    ]
    if matching_runtime_pids(executable):
        raise ObservationError("runtime host is already running before traffic capture")
    runner = subprocess.Popen(command, cwd=REPO_ROOT, stdin=subprocess.DEVNULL,
                              stdout=stdout, stderr=stderr)
    captures: dict[tuple[int, str], dict[str, Any]] = {}
    attachment_gaps: list[dict[str, Any]] = []
    deadline = time.monotonic() + 20 * 60
    beginning = time.monotonic()
    runner_exit: int | None = None
    try:
        while runner.poll() is None:
            if time.monotonic() >= deadline:
                raise ObservationError("production-native workflow suite exceeded 20 minutes")
            for pid in matching_runtime_pids(executable):
                if any(not capture["finished"] and capture["identity"]["pid"] == pid
                       for capture in captures.values()):
                    continue
                try:
                    capture = start_process_capture(pid, "runtime", None, evidence)
                except ObservationError:
                    if not process_is_gone(pid):
                        raise
                    attachment_gaps.append({
                        "pid": pid, "parentPID": None,
                        "reason": "runtime exited before identity attachment",
                    })
                    continue
                key = (pid, capture["identity"]["processStart"])
                captures[key] = capture
            runtime_pids = [capture["identity"]["pid"] for capture in captures.values()
                            if capture["role"] == "runtime" and not capture["finished"]]
            for runtime_pid in runtime_pids:
                for child_pid in child_pids(runtime_pid):
                    if not any(not capture["finished"]
                               and capture["identity"]["pid"] == child_pid
                               for capture in captures.values()):
                        try:
                            capture = start_process_capture(
                                child_pid, "child", runtime_pid, evidence)
                            key = (child_pid, capture["identity"]["processStart"])
                            captures[key] = capture
                        except ObservationError:
                            if not process_is_gone(child_pid):
                                raise
                            attachment_gaps.append({
                                "pid": child_pid, "parentPID": runtime_pid,
                                "reason": "child exited before identity attachment",
                            })
            elapsed = time.monotonic() - beginning
            for capture in list(captures.values()):
                sample_capture(capture, elapsed)
            time.sleep(0.25)
        runner_exit = runner.wait(timeout=10)
    finally:
        stdout.close()
        stderr.close()
        if runner.poll() is None:
            runner.terminate()
            try:
                runner.wait(timeout=15)
            except subprocess.TimeoutExpired:
                pass
        for capture in captures.values():
            if not capture["finished"]:
                capture["nettopExit"] = stop_nettop(capture["nettop"])
                capture["finished"] = True
                capture["endedNaturally"] = process_is_gone(capture["identity"]["pid"])
    rows = [finish_process_capture(capture)
            for _, capture in sorted(captures.items())]
    artifact_end = artifact_manifest(app)
    source_end = source_wip_state()
    if artifact_end != artifact_start or source_end != source_start:
        raise ObservationError("artifact or source WIP changed during workflow traffic capture")
    summary = {
        "schema": 1,
        "mode": "traffic-workflows",
        "sourceWIPState": source_start,
        "artifactManifest": artifact_start,
        "host": host,
        "positiveControl": positive_control,
        "selectedCases": list(TRAFFIC_CASES),
        "xcodebuildExit": runner_exit,
        "resultBundlePresent": result_bundle.is_dir(),
        "runtimeProcesses": rows,
        "attachmentGaps": attachment_gaps,
        "claims": "bounded representative-workflow traffic diagnostic only",
    }
    (evidence / "summary.json").write_text(json.dumps(summary, indent=2) + "\n",
                                            encoding="utf-8")
    runtime_rows = [row for row in rows if row["role"] == "runtime"]
    if runner_exit != 0 or not result_bundle.is_dir() or len(runtime_rows) < len(TRAFFIC_CASES):
        raise ObservationError("representative workflow traffic run was incomplete")
    validate_xcresult(result_bundle, list(TRAFFIC_CASES), evidence, "workflow-traffic")
    if any(row["nettopExit"] not in (0, -15) for row in rows):
        raise ObservationError("one or more workflow traffic observers failed")
    return evidence


def archive_source(evidence: Path, revision: str) -> tuple[Path, dict[str, Any]]:
    archive = evidence / "source.tar"
    result = run_tool(["/usr/bin/git", "archive", "--format=tar", revision], timeout=60,
                      stdout_path=archive, stderr_path=evidence / "git-archive.stderr",
                      cwd=REPO_ROOT)
    if result.returncode != 0:
        raise ObservationError("git archive failed")
    source = evidence / "source"
    source.mkdir(mode=0o700)
    extract = run_tool(["/usr/bin/tar", "-xf", str(archive), "-C", str(source)], timeout=60,
                       stdout_path=evidence / "tar.stdout",
                       stderr_path=evidence / "tar.stderr")
    if extract.returncode != 0 or not (source / "Tidy.xcodeproj").is_dir():
        raise ObservationError("isolated source archive extraction failed")
    return source, {"revision": revision, "bytes": archive.stat().st_size,
                    "sha256": sha256_file(archive)}


def production_build_command(source: Path, derived_data: Path) -> list[str]:
    return [
        "/usr/bin/xcodebuild", "-project", str(source / "Tidy.xcodeproj"),
        "-scheme", "Tidy", "-configuration", "Release",
        "-destination", f"platform=macOS,arch={os.uname().machine}", "-jobs", "2",
        "-derivedDataPath", str(derived_data), "build", "CODE_SIGNING_ALLOWED=NO",
        f"ARCHS={os.uname().machine}", "ONLY_ACTIVE_ARCH=YES",
    ]


def validate_production_build(app: Path) -> dict[str, Any]:
    app = app.resolve(strict=True)
    info_path = (app / "Contents/Info.plist").resolve(strict=True)
    if not is_relative_to(info_path, app):
        raise ObservationError("paired build Info.plist escapes the app")
    info = plistlib.loads(info_path.read_bytes())
    if info.get("CFBundleIdentifier") != PRODUCTION_BUNDLE_ID:
        raise ObservationError("paired build produced an unexpected bundle identifier")
    executable_name = info.get("CFBundleExecutable")
    if not isinstance(executable_name, str) or Path(executable_name).name != executable_name:
        raise ObservationError("paired build produced an invalid executable name")
    code_directory = (app / "Contents/MacOS").resolve(strict=True)
    executable = (code_directory / executable_name).resolve(strict=True)
    if not is_relative_to(executable, app) or not executable.is_file():
        raise ObservationError("paired build executable is missing or escapes its app")
    found: set[bytes] = set()
    for path in code_directory.rglob("*"):
        if path.is_file():
            resolved = path.resolve(strict=True)
            if not is_relative_to(resolved, app):
                raise ObservationError("paired build code path escapes its app")
            found.update(markers_in(resolved))
    if found:
        raise ObservationError("paired production build contains runtime-fixture markers")
    return artifact_manifest(app)


def run_production_build(source: Path, derived_data: Path, evidence: Path,
                         label: str) -> dict[str, Any]:
    if derived_data.exists():
        raise ObservationError("paired build derived data was not empty")
    if shutil.disk_usage(evidence).free < 4 * 1024 * 1024 * 1024:
        raise ObservationError("paired build requires at least 4 GiB of free temporary space")
    command = production_build_command(source, derived_data)
    started = time.monotonic_ns()
    result = run_tool(command, timeout=20 * 60,
                      stdout_path=evidence / f"{label}.stdout",
                      stderr_path=evidence / f"{label}.stderr", cwd=source)
    ended = time.monotonic_ns()
    record = {
        "label": label,
        "exit": result.returncode,
        "durationNanoseconds": ended - started,
        "durationSeconds": (ended - started) / 1_000_000_000,
        "derivedDataWasInitiallyAbsent": True,
        "command": [
            "xcodebuild", "-project", "<isolated-source>/Tidy.xcodeproj",
            "-scheme", "Tidy", "-configuration", "Release",
            "-destination", f"platform=macOS,arch={os.uname().machine}", "-jobs", "2",
            "-derivedDataPath", "<fresh-pair-derived-data>", "build",
            "CODE_SIGNING_ALLOWED=NO", f"ARCHS={os.uname().machine}",
            "ONLY_ACTIVE_ARCH=YES",
        ],
    }
    if result.returncode == 0:
        product = derived_data / "Build/Products/Release/Tidy.app"
        record["productManifest"] = validate_production_build(product)
        shutil.rmtree(derived_data)
        record["derivedDataRemovedAfterValidation"] = not derived_data.exists()
    return record


def build_control_command(condition: str, app: Path, evidence: Path,
                          label: str) -> list[str]:
    scenario = "hidden-off" if condition == "baseline" else "hidden-authorized"
    test_case = "testProductionHiddenOffBuildControl" if condition == "baseline" \
        else "testProductionHiddenAuthorizedBuildControl"
    derived_data = derived_data_for_runtime_app(app)
    configuration = app.parent.name
    return [
        "/usr/bin/xcodebuild", "-project", str(REPO_ROOT / "Tidy.xcodeproj"),
        "-scheme", "TidyProductionNativeUITests", "-configuration", configuration,
        "-destination", f"platform=macOS,arch={os.uname().machine}", "-jobs", "2",
        "-derivedDataPath", str(derived_data),
        "-resultBundlePath", str(evidence / f"{label}-control.xcresult"),
        f"-only-testing:TidyProductionNativeUITests/ProductionObservationRuntimeUITests/{test_case}",
        "test-without-building", "CODE_SIGN_IDENTITY=-", "CODE_SIGNING_ALLOWED=YES",
    ]


def launch_build_control(app: Path, executable: Path, condition: str,
                         evidence: Path, label: str) -> dict[str, Any]:
    scenario = "hidden-off" if condition == "baseline" else "hidden-authorized"
    existing_pids = set(matching_runtime_pids(executable))
    if existing_pids:
        raise ObservationError("runtime host is already running before paired-build control")
    existing_roots = fixture_root_snapshot()
    stdout = (evidence / f"{label}-control.stdout").open("wb")
    stderr = (evidence / f"{label}-control.stderr").open("wb")
    runner = subprocess.Popen(build_control_command(condition, app, evidence, label),
                              cwd=REPO_ROOT, stdin=subprocess.DEVNULL,
                              stdout=stdout, stderr=stderr)
    pid: int | None = None
    identity: dict[str, Any] | None = None
    root: Path | None = None
    try:
        pid, identity = wait_for_runtime_pid(executable, existing_pids, runner)
        root, ready = wait_for_hidden_ready_root(existing_roots, scenario, pid)
        return {"runner": runner, "stdout": stdout, "stderr": stderr,
                "root": root, "pid": pid, "identity": identity, "ready": ready,
                "scenario": scenario, "condition": condition,
                "resultBundle": evidence / f"{label}-control.xcresult"}
    except Exception:
        if pid is not None and identity is not None and not process_is_gone(pid):
            try:
                terminate_pid_owned(pid, executable, identity["processStart"])
            except (ObservationError, OSError):
                pass
        if runner.poll() is None:
            runner.terminate()
            try:
                runner.wait(timeout=15)
            except subprocess.TimeoutExpired:
                pass
        stdout.close()
        stderr.close()
        raise


def stop_build_control(control: dict[str, Any]) -> dict[str, Any]:
    root = control["root"]
    runner = control["runner"]
    completed = False
    try:
        publish_owned_signal(root, "runtime-observation-observed",
                             b"TIDY_RUNTIME_OBSERVATION_OBSERVED_V1\n")
        try:
            exit_code = runner.wait(timeout=60)
        except subprocess.TimeoutExpired as error:
            raise ObservationError("paired-build control XCTest did not finish") from error
        if exit_code != 0 or not control["resultBundle"].is_dir():
            raise ObservationError("paired-build control XCTest failed")
        test_case = "testProductionHiddenOffBuildControl" \
            if control["condition"] == "baseline" \
            else "testProductionHiddenAuthorizedBuildControl"
        validate_xcresult(control["resultBundle"], [test_case],
                          control["resultBundle"].parent,
                          f"pair-control-{control['pid']}")
        deadline = time.monotonic() + 15
        while root.exists() and time.monotonic() < deadline:
            time.sleep(0.05)
        if root.exists():
            raise ObservationError("paired-build control did not remove its fixture root")
        completed = True
        return {"xcodebuildExit": exit_code, "resultBundlePresent": True,
                "fixtureRootRemoved": True}
    finally:
        pid = control["pid"]
        if not completed and not process_is_gone(pid):
            try:
                terminate_pid_owned(pid, Path(control["identity"]["executable"]),
                                    control["identity"]["processStart"])
            except (ObservationError, OSError):
                pass
        if runner.poll() is None:
            runner.terminate()
            try:
                runner.wait(timeout=15)
            except subprocess.TimeoutExpired:
                pass
        control["stdout"].close()
        control["stderr"].close()


def observe_paired_builds(runtime_app: Path) -> Path:
    app, executable = validate_runtime_app(runtime_app)
    evidence = Path(tempfile.mkdtemp(
        prefix=EVIDENCE_PREFIX + "paired-builds-", dir="/private/tmp"))
    os.chmod(evidence, 0o700)
    evidence = validate_evidence_root(evidence)
    artifact_start = artifact_manifest(app)
    source_start = source_wip_state()
    if source_start["statusEntryCount"] != 0:
        raise ObservationError("paired builds require a clean frozen source worktree")
    host = host_context()
    source, source_archive = archive_source(evidence, source_start["head"])
    for name, value in (("artifact-manifest-start.json", artifact_start),
                        ("source-wip-start.json", source_start), ("host.json", host),
                        ("source-archive.json", source_archive)):
        (evidence / name).write_text(json.dumps(value, indent=2) + "\n", encoding="utf-8")
    if matching_runtime_pids(executable):
        raise ObservationError("runtime host is already running before paired builds")
    warm = run_production_build(source, evidence / "warm-derived-data", evidence, "warm")
    if warm["exit"] != 0:
        raise ObservationError("paired-build warm-up failed")
    pairs: list[dict[str, Any]] = []
    for pair_index in range(1, BUILD_PAIR_COUNT + 1):
        order = ("baseline", "background") if pair_index % 2 else ("background", "baseline")
        pair: dict[str, Any] = {"pair": pair_index, "order": list(order), "runs": {}}
        for condition in order:
            label = f"pair-{pair_index}-{condition}"
            control: dict[str, Any] | None = None
            run: dict[str, Any] | None = None
            try:
                control = launch_build_control(app, executable, condition, evidence, label)
                run = run_production_build(source, evidence / f"{label}-derived-data",
                                           evidence, label)
                run["runtimeReady"] = control["ready"]
                pair["runs"][condition] = run
                if run["exit"] != 0:
                    raise ObservationError(f"paired production build failed: {label}")
            finally:
                if control is not None:
                    completion = stop_build_control(control)
                    if run is not None:
                        run["controlCompletion"] = completion
        pair["overheadSeconds"] = (
            pair["runs"]["background"]["durationSeconds"]
            - pair["runs"]["baseline"]["durationSeconds"])
        pairs.append(pair)
    artifact_end = artifact_manifest(app)
    source_end = source_wip_state()
    if artifact_end != artifact_start or source_end != source_start:
        raise ObservationError("artifact or source WIP changed during paired builds")
    overheads = [pair["overheadSeconds"] for pair in pairs]
    baseline = [pair["runs"]["baseline"]["durationSeconds"] for pair in pairs]
    background = [pair["runs"]["background"]["durationSeconds"] for pair in pairs]
    summary = {
        "schema": 1,
        "mode": "paired-builds",
        "sourceWIPState": source_start,
        "sourceArchive": source_archive,
        "artifactManifest": artifact_start,
        "host": host,
        "warmup": warm,
        "pairCount": BUILD_PAIR_COUNT,
        "pairs": pairs,
        "baselineMedianSeconds": statistics.median(baseline),
        "backgroundMedianSeconds": statistics.median(background),
        "pairedOverheadMedianSeconds": statistics.median(overheads),
        "claims": "bounded current-host paired-build diagnostic only",
    }
    (evidence / "summary.json").write_text(json.dumps(summary, indent=2) + "\n",
                                            encoding="utf-8")
    return evidence


def make_fake_app(root: Path, bundle_id: str, markers: tuple[bytes, ...]) -> Path:
    app = root / "Fixture.app"
    macos = app / "Contents/MacOS"
    macos.mkdir(parents=True)
    executable = macos / "Fixture"
    executable.write_bytes(b"prefix" + b"|".join(markers) + b"suffix")
    os.chmod(executable, 0o700)
    info = {"CFBundleIdentifier": bundle_id, "CFBundleExecutable": executable.name}
    (app / "Contents/Info.plist").write_bytes(plistlib.dumps(info))
    return app


def run_self_test() -> None:
    with tempfile.TemporaryDirectory(prefix="tidy-r13-observer-selftest-", dir="/private/tmp") as raw:
        root = Path(raw)
        runtime = make_fake_app(root / "runtime", RUNTIME_BUNDLE_ID, MARKERS)
        _, executable = validate_runtime_app(runtime)
        assert executable.name == "Fixture"
        normal = make_fake_app(root / "normal", PRODUCTION_BUNDLE_ID, MARKERS)
        try:
            validate_runtime_app(normal)
        except ObservationError:
            pass
        else:
            raise AssertionError("normal bundle was accepted")
        assert parse_cpu_seconds("01:02") == 62
        assert parse_cpu_seconds("1-02:03:04.5") == 93784.5
        fixture = Path("/private/tmp") / f"{FIXTURE_PREFIX}{os.urandom(8).hex()}"
        fixture.mkdir(mode=0o700)
        try:
            assert validate_fixture_root(fixture) == fixture.resolve()
            ready = {
                "schema": 1, "scenario": "hidden-off", "pid": 123,
                "settingsRevision": 1, "timerRunning": False, "sceneLeases": 0,
                "explicitWorkLeases": 0, "scanSessions": 0, "scanActiveWork": 0,
                "allMutationsDenied": True, "timerScheduledCount": 0,
                "timerCancelledCount": 0, "observedMonotonicNanoseconds": 10,
                "applicationHidden": True,
            }
            ready_path = fixture / "ready.json"
            ready_path.write_text(json.dumps(ready), encoding="utf-8")
            assert parse_attestation(ready_path, "hidden-off", 123) == ready
            final = dict(ready)
            final["observedMonotonicNanoseconds"] += 120 * 1_000_000_000
            ready_path.write_text(json.dumps(final), encoding="utf-8")
            assert parse_attestation(ready_path, "hidden-off", 123, initial=ready) == final
            nettop_path = fixture / "nettop.csv"
            nettop_path.write_text(
                ",bytes_in,bytes_out,\nPython.1,0,0,\nPython.1,10,20,\n",
                encoding="utf-8")
            assert parse_nettop_counters(nettop_path) == (2, 10, 20)
            state = fixture / "state"
            state.mkdir(mode=0o700)
            publish_owned_signal(fixture, "runtime-performance-proceed",
                                 b"TIDY_RUNTIME_PROCEED_V1\n")
            signal = state / "runtime-performance-proceed"
            validate_owned_document(signal)
            assert signal.read_bytes() == b"TIDY_RUNTIME_PROCEED_V1\n"
            performance_ready = {
                "schema": 1, "scenario": "performance-50k", "pid": 123,
                "fixtureFiles": 50_000, "fixtureLogicalBytes": 0,
                "fixtureAllocatedBytes": 0, "registrySessions": 0,
                "registryActiveWork": 0, "schedulerActive": 0,
                "schedulerQueued": 0, "schedulerLiveSessions": 0,
                "explicitLeases": 0, "indexWatchActive": False,
                "allMutationsDenied": True, "witnessUnchanged": True,
                "settled": True,
            }
            assert set(performance_ready) == PERFORMANCE_READY_KEYS
            validate_performance_ready(performance_ready, "performance-50k", 123)
        finally:
            shutil.rmtree(fixture)
    print("R13 observation harness self-tests: PASS")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("mode", nargs="?", choices=MODES)
    parser.add_argument("--runtime-app", type=Path)
    args = parser.parse_args()
    if args.self_test:
        if args.mode is not None or args.runtime_app is not None:
            parser.error("--self-test accepts no mode or runtime app")
    elif args.mode is None or args.runtime_app is None:
        parser.error("mode and --runtime-app are required")
    return args


def main() -> int:
    args = parse_args()
    try:
        if args.self_test:
            run_self_test()
        elif args.mode in SCENARIOS:
            evidence = observe(args.mode, args.runtime_app)
            print(f"R13 observation evidence: {evidence}")
        elif args.mode == "traffic-workflows":
            evidence = observe_workflow_traffic(args.runtime_app)
            print(f"R13 workflow-traffic evidence: {evidence}")
        elif args.mode == "paired-builds":
            evidence = observe_paired_builds(args.runtime_app)
            print(f"R13 paired-build evidence: {evidence}")
        elif args.mode in PERFORMANCE_SCENARIOS:
            evidence = observe_performance(args.mode, args.runtime_app)
            print(f"R13 performance evidence: {evidence}")
        else:
            raise AssertionError(f"unhandled observation mode: {args.mode}")
    except (AssertionError, ObservationError, OSError, ValueError,
            subprocess.SubprocessError) as error:
        print(f"R13 observation failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
