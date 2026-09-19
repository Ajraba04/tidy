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
import queue
import re
import shutil
import stat
import subprocess
import sys
import tempfile
import threading
import time
from typing import Any


RUNTIME_BUNDLE_ID = "io.github.ajraba04.Tidy.ProductionRuntimeVerification"
PRODUCTION_BUNDLE_ID = "io.github.ajraba04.Tidy"
REPO_ROOT = Path(__file__).resolve().parents[2]
FIXTURE_PREFIX = "tidy-production-runtime-"
EVIDENCE_PREFIX = "tidy-r13-observation-"
ROOT_LINE_PREFIX = "TIDY_RUNTIME_ROOT="
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
    },
    "hidden-authorized": {
        "flag": "--tidy-runtime-hidden-authorized",
        "duration": 600,
        "timer": True,
    },
}
TOOLS = {
    "ps": Path("/bin/ps"),
    "pgrep": Path("/usr/bin/pgrep"),
    "lsof": Path("/usr/sbin/lsof"),
    "footprint": Path("/usr/bin/footprint"),
    "nettop": Path("/usr/bin/nettop"),
}
LIBPROC = ctypes.CDLL("/usr/lib/libproc.dylib", use_errno=True)
PROC_PIDPATHINFO_MAXSIZE = 4096


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


def wait_for_root(lines: "queue.Queue[str]", process: subprocess.Popen,
                  timeout: float = 30) -> Path:
    deadline = time.monotonic() + timeout
    roots: list[Path] = []
    while time.monotonic() < deadline:
        if process.poll() is not None:
            raise ObservationError("runtime host exited before announcing its root")
        try:
            line = lines.get(timeout=min(0.25, max(0.01, deadline - time.monotonic())))
        except queue.Empty:
            continue
        if line.startswith(ROOT_LINE_PREFIX):
            roots.append(Path(line.removeprefix(ROOT_LINE_PREFIX)))
            if len(roots) > 1:
                raise ObservationError("runtime host announced more than one root")
            return validate_fixture_root(roots[0])
    raise ObservationError("runtime host did not announce its root")


def wait_for_ready(root: Path, scenario: str, pid: int, timeout: float = 30) -> dict[str, Any]:
    path = root / "state/runtime-ready.json"
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if path.is_file():
            return parse_attestation(path, scenario, pid)
        time.sleep(0.05)
    raise ObservationError("runtime host did not publish its ready document")


def wait_for_final(root: Path, scenario: str, pid: int, initial: dict[str, Any],
                   timeout: float = 15) -> dict[str, Any]:
    path = root / "state/runtime-final.json"
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if path.is_file():
            return parse_attestation(path, scenario, pid, initial=initial)
        time.sleep(0.05)
    raise ObservationError("runtime host did not publish its final document")


def reader_thread(stream: Any, lines: "queue.Queue[str]", destination: Path) -> None:
    with destination.open("wb") as output:
        while data := stream.readline():
            output.write(data)
            output.flush()
            try:
                lines.put(data.decode("utf-8", errors="strict").rstrip("\n"))
            except UnicodeError:
                lines.put("<invalid-utf8>")


def sample_process(process: subprocess.Popen, executable: Path, expected_start: str,
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
        if process.poll() is not None:
            raise ObservationError("runtime host exited during observation")
        started = time.monotonic()
        identity = process_identity(process.pid)
        if identity["pid"] != process.pid or identity["processStart"] != expected_start \
                or Path(identity["executable"]) != executable:
            raise ObservationError("runtime PID identity changed")
        children = child_pids(process.pid)
        observed_children.update(children)
        fd_sampled = index % 5 == 0 or started >= deadline
        if fd_sampled:
            numeric_fds, special_refs = descriptor_counts(process.pid)
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


def terminate_owned(process: subprocess.Popen, executable: Path, start: str) -> None:
    identity = process_identity(process.pid)
    if identity["processStart"] != start or Path(identity["executable"]) != executable:
        raise ObservationError("runtime process start identity changed before termination")
    process.terminate()
    try:
        process.wait(timeout=15)
    except subprocess.TimeoutExpired as error:
        raise ObservationError("runtime process did not terminate; evidence retained") from error


def remove_owned_root(root: Path) -> None:
    validated = validate_fixture_root(root)
    shutil.rmtree(validated)
    if validated.exists():
        raise ObservationError("runtime fixture root removal did not complete")


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
    (evidence / "artifact-manifest-start.json").write_text(
        json.dumps(artifact_start, indent=2) + "\n", encoding="utf-8")
    (evidence / "source-wip-start.json").write_text(
        json.dumps(source_start, indent=2) + "\n", encoding="utf-8")
    (evidence / "host.json").write_text(json.dumps(host, indent=2) + "\n", encoding="utf-8")
    positive_control = run_nettop_positive_control(evidence)
    stderr_stream = (evidence / "runtime.stderr").open("wb")
    process = subprocess.Popen([
        str(executable), "-ApplePersistenceIgnoreState", "YES",
        SCENARIOS[scenario]["flag"],
    ], stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=stderr_stream)
    lines: "queue.Queue[str]" = queue.Queue()
    assert process.stdout is not None
    reader = threading.Thread(target=reader_thread,
                              args=(process.stdout, lines, evidence / "runtime.stdout"), daemon=True)
    reader.start()
    root: Path | None = None
    identity: dict[str, Any] | None = None
    nettop: subprocess.Popen | None = None
    completed = False
    try:
        root = wait_for_root(lines, process)
        identity = process_identity(process.pid)
        if Path(identity["executable"]) != executable:
            raise ObservationError("launched runtime executable identity does not match")
        ready = wait_for_ready(root, scenario, process.pid)
        (evidence / "ready.json").write_text(json.dumps(ready, indent=2) + "\n", encoding="utf-8")
        nettop = start_nettop(process.pid, SCENARIOS[scenario]["duration"], evidence)
        samples, children = sample_process(process, executable, identity["processStart"],
                                           SCENARIOS[scenario]["duration"], evidence)
        final = wait_for_final(root, scenario, process.pid, ready)
        (evidence / "final.json").write_text(json.dumps(final, indent=2) + "\n",
                                              encoding="utf-8")
        nettop_exit = finish_nettop(nettop)
        footprint_exit = run_footprint(process.pid, evidence)
        artifact_end = artifact_manifest(app)
        source_end = source_wip_state()
        (evidence / "artifact-manifest-end.json").write_text(
            json.dumps(artifact_end, indent=2) + "\n", encoding="utf-8")
        (evidence / "source-wip-end.json").write_text(
            json.dumps(source_end, indent=2) + "\n", encoding="utf-8")
        if artifact_end != artifact_start:
            raise ObservationError("runtime artifact changed during observation")
        if source_end != source_start:
            raise ObservationError("source WIP state changed during observation")
        summary = summarize(scenario, app, executable, ready, final, positive_control,
                            source_start, artifact_start, host,
                            samples, children,
                            nettop_exit, footprint_exit, evidence)
        (evidence / "summary.md").write_text(markdown_summary(summary), encoding="utf-8")
        terminate_owned(process, executable, identity["processStart"])
        remove_owned_root(root)
        root = None
        completed = True
        return evidence
    except Exception:
        (evidence / "FAILED").write_text("observation failed; inspect retained evidence\n",
                                          encoding="utf-8")
        raise
    finally:
        if nettop is not None and nettop.poll() is None:
            nettop.terminate()
            try:
                nettop.wait(timeout=5)
            except subprocess.TimeoutExpired:
                pass
            for stream in getattr(nettop, "_tidy_streams", ()):
                stream.close()
        if not completed and process.poll() is None:
            try:
                cleanup_identity = identity or process_identity(process.pid)
                if Path(cleanup_identity["executable"]) != executable:
                    raise ObservationError("runtime executable changed before failure cleanup")
                terminate_owned(process, executable, cleanup_identity["processStart"])
                (evidence / "process-cleanup.txt").write_text(
                    "owned runtime process terminated after observer failure\n", encoding="utf-8")
            except (ObservationError, OSError, subprocess.SubprocessError) as cleanup_error:
                (evidence / "process-cleanup.txt").write_text(
                    f"runtime process retained after identity/termination failure: {cleanup_error}\n",
                    encoding="utf-8")
        stderr_stream.close()
        if process.poll() is not None:
            reader.join(timeout=2)
        # On uncertainty, never remove a live process or its root.
        if root is not None:
            (evidence / "retained-root.txt").write_text(str(root) + "\n", encoding="utf-8")


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
        finally:
            shutil.rmtree(fixture)
    print("R13 observation harness self-tests: PASS")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("scenario", nargs="?", choices=sorted(SCENARIOS))
    parser.add_argument("--runtime-app", type=Path)
    args = parser.parse_args()
    if args.self_test:
        if args.scenario is not None or args.runtime_app is not None:
            parser.error("--self-test accepts no scenario or runtime app")
    elif args.scenario is None or args.runtime_app is None:
        parser.error("scenario and --runtime-app are required")
    return args


def main() -> int:
    args = parse_args()
    try:
        if args.self_test:
            run_self_test()
        else:
            evidence = observe(args.scenario, args.runtime_app)
            print(f"R13 observation evidence: {evidence}")
    except (AssertionError, ObservationError, OSError, ValueError,
            subprocess.SubprocessError) as error:
        print(f"R13 observation failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
