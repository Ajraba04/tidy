#!/usr/bin/env python3
"""Prepared SDK command-semantics experiment; never Tidy acceptance authority.

Default mode reads bounded filesystem witnesses and prints a plan. It invokes
no SDK command and writes only an explicitly requested, newly created plan.
Execution requires the existing reviewed plan path, SHA256 and output root.
Those arguments bind the procedure; they do not substitute for owner approval.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import pwd
import re
import selectors
import stat
import subprocess
import sys
import time
import uuid

SIMCTL = "/Applications/Xcode.app/Contents/Developer/usr/bin/simctl"
DEVELOPER = "/Applications/Xcode.app/Contents/Developer"
RUNTIME = "com.apple.CoreSimulator.SimRuntime.iOS-27-0"
DEVICE_TYPE = "com.apple.CoreSimulator.SimDeviceType.iPhone-17"
ENV = {"PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "HOME": "/var/empty", "DEVELOPER_DIR": DEVELOPER}
LIMITS = {"wallSeconds": 180, "commandSeconds": 15, "streamBytes": 1048576,
          "commands": 80, "bootObservations": 8, "devices": 256, "planBytes": 131072,
          "maximumEvidenceBytes": 201326592, "directoryDepth": 32,
          "maximumHeldDirectoryFDs": 128, "executableBytes": 134217728, "driverBytes": 524288}
CLASSIFICATION = "SDK command semantics only; no Tidy receipt/proof, bridge/journal qualification or registry activation"
SF_DATALESS = 0x40000000


class Refusal(Exception):
    pass


def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=True).encode()


def digest(data):
    return hashlib.sha256(data).hexdigest()


def full_uuid(value):
    if not isinstance(value, str) or not re.fullmatch(r"[0-9A-Fa-f]{8}(?:-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12}", value):
        raise Refusal("Missing or malformed full UUID")
    return str(uuid.UUID(value)).upper()


def require_materialized(s):
    if getattr(s, "st_flags", 0) & SF_DATALESS:
        raise Refusal("Dataless resource; hydration is outside this procedure")


def metadata_identity(s, directory=False, private=False):
    require_materialized(s)
    expected = stat.S_ISDIR if directory else stat.S_ISREG
    if not expected(s.st_mode) or s.st_uid != os.getuid() and private:
        raise Refusal("Unexpected file kind or owner")
    if private and stat.S_IMODE(s.st_mode) != (0o700 if directory else 0o600):
        raise Refusal("Private resource permissions required")
    result = {"device": s.st_dev, "inode": s.st_ino, "uid": s.st_uid, "mode": stat.S_IMODE(s.st_mode)}
    if not directory:
        result.update(size=s.st_size, mtime=s.st_mtime_ns, ctime=s.st_ctime_ns)
    return result


def identity(path, directory=False, private=False):
    path = Path(path)
    if not path.is_absolute() or ".." in path.parts or len(path.parts) > LIMITS["directoryDepth"]:
        raise Refusal("Noncanonical path")
    # Metadata only: deny a dataless/symbolic ancestor before opening a file or
    # enumerating a directory. Do not resolve through an ancestor alias.
    current = Path("/")
    components = path.parts[1:]
    metadata_identity(current.lstat(), directory=True)
    for index, component in enumerate(components):
        current = current / component
        s = current.lstat()
        if index + 1 < len(components):
            metadata_identity(s, directory=True)
    return metadata_identity(current.lstat(), directory=directory, private=private)


class VerifiedDirectory:
    """Retained no-follow directory chain; writes never resolve a pathname parent.

    Child anchors retain their parent object. Callers keep the whole chain open
    through SDK work and publication, and close children before their parents.
    """
    def __init__(self, path, chain, owned_fds, private, parent=None):
        self.path = Path(path)
        self.chain = chain
        self.owned_fds = owned_fds
        self.private = private
        self.parent = parent
        self.fd = chain[-1][0]

    @classmethod
    def open_existing(cls, path, private=False):
        path = Path(path)
        expected = identity(path, directory=True, private=private)
        flags = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | os.O_NONBLOCK
        opened = []
        chain = []
        try:
            fd = os.open("/", flags); opened.append(fd)
            root = metadata_identity(os.fstat(fd), directory=True)
            chain.append((fd, None, None, root))
            for index, name in enumerate(path.parts[1:]):
                before = metadata_identity(os.stat(name, dir_fd=fd, follow_symlinks=False), directory=True)
                next_fd = os.open(name, flags, dir_fd=fd); opened.append(next_fd)
                current = metadata_identity(os.fstat(next_fd), directory=True,
                    private=private and index + 2 == len(path.parts))
                if current != before:
                    raise Refusal("Directory changed during anchored open")
                chain.append((next_fd, fd, name, current)); fd = next_fd
            if chain[-1][3] != expected:
                raise Refusal("Directory identity changed")
            result = cls(path, chain, opened, private)
            result.require_current()
            return result
        except Exception:
            for fd in reversed(opened):
                os.close(fd)
            raise

    def require_current(self):
        try:
            for fd, parent_fd, name, expected in self.chain:
                if metadata_identity(os.fstat(fd), directory=True) != expected:
                    raise Refusal("Held directory identity changed")
                named = os.stat("/", follow_symlinks=False) if parent_fd is None else os.stat(name, dir_fd=parent_fd, follow_symlinks=False)
                if metadata_identity(named, directory=True) != expected:
                    raise Refusal("Named directory or ancestor replaced")
            metadata_identity(os.fstat(self.fd), directory=True, private=self.private)
        except OSError as error:
            raise Refusal("Held directory chain is unavailable") from error
        return self.chain[-1][3]

    @staticmethod
    def leaf(name):
        if not isinstance(name, str) or name in (".", "..") or not re.fullmatch(r"[A-Za-z0-9._-]{1,160}", name):
            raise Refusal("Invalid anchored leaf")
        return name

    def create_directory(self, name):
        name = self.leaf(name)
        self.require_current()
        os.mkdir(name, mode=0o700, dir_fd=self.fd)
        self.require_current()
        expected = metadata_identity(os.stat(name, dir_fd=self.fd, follow_symlinks=False), directory=True, private=True)
        fd = os.open(name, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=self.fd)
        try:
            if metadata_identity(os.fstat(fd), directory=True, private=True) != expected:
                raise Refusal("New owned directory changed")
            child = VerifiedDirectory(self.path / name, self.chain + [(fd, self.fd, name, expected)], [fd], True, self)
            child.require_current()
            os.fsync(self.fd)
            return child
        except Exception:
            os.close(fd)
            raise

    def open_directory(self, name, private=False):
        name = self.leaf(name)
        self.require_current()
        before = metadata_identity(os.stat(name, dir_fd=self.fd, follow_symlinks=False), directory=True, private=private)
        fd = os.open(name, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=self.fd)
        try:
            if metadata_identity(os.fstat(fd), directory=True, private=private) != before:
                raise Refusal("Named directory changed during anchored open")
            child = VerifiedDirectory(self.path / name, self.chain + [(fd, self.fd, name, before)], [fd], private, self)
            child.require_current()
            return child
        except Exception:
            os.close(fd)
            raise

    def read_regular(self, name, maximum, private=False):
        name = self.leaf(name)
        self.require_current()
        before = metadata_identity(os.stat(name, dir_fd=self.fd, follow_symlinks=False), private=private)
        fd = os.open(name, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=self.fd)
        try:
            self.require_current()
            opened = metadata_identity(os.fstat(fd), private=private)
            if opened != before or opened["size"] > maximum:
                raise Refusal("Changed or oversized file")
            chunks = bytearray()
            while len(chunks) <= maximum:
                # Recheck the held FD before every content read, including a
                # flag transition after opening. No read may hydrate dataless data.
                require_materialized(os.fstat(fd))
                part = os.read(fd, min(65536, maximum + 1 - len(chunks)))
                if not part:
                    break
                chunks.extend(part)
            self.require_current()
            named = metadata_identity(os.stat(name, dir_fd=self.fd, follow_symlinks=False), private=private)
            if len(chunks) > maximum or metadata_identity(os.fstat(fd), private=private) != before or named != before:
                raise Refusal("Changed or oversized file")
            return bytes(chunks)
        finally:
            os.close(fd)

    def write_new(self, name, data):
        name = self.leaf(name)
        self.require_current()
        temporary = ".tidy-write-" + str(uuid.uuid4())
        fd = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600, dir_fd=self.fd)
        original = None
        try:
            original = os.fstat(fd)
            metadata_identity(original, private=True)
            self.require_current()
            remaining = memoryview(data)
            while remaining:
                require_materialized(os.fstat(fd))
                written = os.write(fd, remaining)
                if written <= 0:
                    raise Refusal("Incomplete evidence write")
                remaining = remaining[written:]
            os.fsync(fd)
            current = os.fstat(fd)
            metadata_identity(current, private=True)
            named = os.stat(temporary, dir_fd=self.fd, follow_symlinks=False)
            if (named.st_dev, named.st_ino) != (original.st_dev, original.st_ino) or (current.st_dev, current.st_ino) != (original.st_dev, original.st_ino):
                raise Refusal("Owned evidence leaf changed")
            self.require_current()
            # Publish a complete new file relative to the held directory. link
            # refuses an existing final leaf instead of overwriting it.
            os.link(temporary, name, src_dir_fd=self.fd, dst_dir_fd=self.fd, follow_symlinks=False)
            # The staging pathname can be replaced between its check and link.
            # Prove that the published no-follow leaf is the still-held owned
            # regular file before accepting publication. Never remove a foreign
            # final leaf when this verification fails.
            held = metadata_identity(os.fstat(fd), private=True)
            published = metadata_identity(os.stat(name, dir_fd=self.fd, follow_symlinks=False), private=True)
            staged = metadata_identity(os.stat(temporary, dir_fd=self.fd, follow_symlinks=False), private=True)
            if held != published or held != staged or held["size"] != len(data) or (held["device"], held["inode"]) != (original.st_dev, original.st_ino):
                raise Refusal("Published evidence differs from the held owned staging file")
            os.fsync(self.fd)
            self.require_current()
        finally:
            try:
                held = metadata_identity(os.fstat(fd), private=True)
                named = metadata_identity(os.stat(temporary, dir_fd=self.fd, follow_symlinks=False), private=True)
                if original is not None and named == held and (held["device"], held["inode"]) == (original.st_dev, original.st_ino):
                    os.unlink(temporary, dir_fd=self.fd)
            except (Refusal, OSError):
                pass
            os.close(fd)

    def close(self):
        for fd in reversed(self.owned_fds):
            os.close(fd)
        self.owned_fds = []

    def __enter__(self):
        return self

    def __exit__(self, *_):
        self.close()


def read_regular(path, maximum, private=False):
    before = identity(path, private=private)
    path = Path(path)
    with VerifiedDirectory.open_existing(path.parent) as parent:
        result = parent.read_regular(path.name, maximum, private=private)
        if identity(path, private=private) != before:
            raise Refusal("Changed or oversized file")
        return result


def default_set_path():
    return str(Path(pwd.getpwuid(os.getuid()).pw_dir) / "Library/Developer/CoreSimulator/Devices")


def file_witness(device_set):
    root = Path(device_set)
    root_identity = identity(root, directory=True)
    with VerifiedDirectory.open_existing(root) as anchored:
        if anchored.require_current() != root_identity:
            raise Refusal("Device-set root changed before inventory")
        configs = {"device_set.plist": digest(anchored.read_regular("device_set.plist", LIMITS["streamBytes"]))}
        anchored.require_current()
        entries = []
        with os.scandir(anchored.fd) as iterator:
            for entry in iterator:
                if len(entries) >= LIMITS["devices"] + 32:
                    raise Refusal("Device-set filesystem inventory exceeds bound")
                s = entry.stat(follow_symlinks=False)
                require_materialized(s)
                if stat.S_ISLNK(s.st_mode):
                    raise Refusal("Symbolic entry in device set")
                entries.append((entry.name, s))
        observed = []
        for name, s in sorted(entries):
            observed.append({"name": name, "device": s.st_dev, "inode": s.st_ino, "kind": stat.S_IFMT(s.st_mode)})
            if re.fullmatch(r"[0-9A-Fa-f-]{36}", name):
                full_uuid(name)
                with anchored.open_directory(name) as device:
                    configs[name + "/device.plist"] = digest(device.read_regular("device.plist", LIMITS["streamBytes"]))
        anchored.require_current()
        return {"root": root_identity, "inventory": observed, "configurationSHA256": configs}


def templates(device_set, outside_set, target_name, witness_name):
    def command(root, *args):
        return [SIMCTL, "--set", root, *args]
    return {
        "signature": ["/usr/bin/codesign", "--verify", "--strict", "--all-architectures", "-R", "anchor apple", SIMCTL],
        "version": [SIMCTL, "--version"],
        "outsideReads": [command(outside_set, "list", kind, "-j") for kind in ("devices", "runtimes", "pairs")],
        "ownedReads": [command(device_set, "list", kind, "-j") for kind in ("devices", "runtimes", "pairs")],
        "createTarget": command(device_set, "create", target_name, DEVICE_TYPE, RUNTIME),
        "createWitness": command(device_set, "create", witness_name, DEVICE_TYPE, RUNTIME),
        "boot": command(device_set, "boot", "{recordedTargetFullUUID}"),
        "shutdown": command(device_set, "shutdown", "{recordedTargetFullUUID}"),
        "cleanup": [command(device_set, "delete", "{recordedTargetFullUUID}"),
                    command(device_set, "delete", "{recordedWitnessFullUUID}")],
    }


def build_plan(plan_id, output_root, plan_path, host_witness, output_identity=None):
    plan_id = full_uuid(plan_id)
    root = str(Path(output_root).resolve(strict=True))
    if len(root.encode()) > 1024:
        raise Refusal("Output path exceeds bound")
    if plan_path is not None:
        proposed = Path(plan_path)
        if str(proposed.parent.resolve(strict=True)) != root or not re.fullmatch(r"[A-Za-z0-9._-]{1,128}\.json", proposed.name):
            raise Refusal("Plan must be a named JSON file directly inside the owned output root")
        plan_path = root + "/" + proposed.name
    parent = "/private/tmp/Tidy-SDK-Semantics-" + plan_id
    target_name, witness_name = "Tidy-SDK-Target-" + plan_id, "Tidy-SDK-Witness-" + plan_id
    outside = default_set_path()
    return {"schema": 1, "classification": CLASSIFICATION, "productionRegistry": "DENIED",
            "planID": plan_id, "planPath": plan_path, "outputRoot": root,
            "outputRootIdentity": output_identity or identity(root, directory=True, private=True),
            "privateParent": parent, "deviceSet": parent + "/device-set",
            "evidenceDirectory": root + "/sdk-semantics-" + plan_id,
            "defaultDeviceSet": outside, "defaultFileWitness": host_witness,
            "producer": {"simctl": SIMCTL, "xcodeVersion": "27.0", "xcodeBuild": "27A266a", "coreSimulatorVersion": "1171.7"},
            "runtime": RUNTIME, "deviceType": DEVICE_TYPE, "environment": ENV, "limits": LIMITS,
            "targetName": target_name, "witnessName": witness_name,
            "commands": templates(parent + "/device-set", outside, target_name, witness_name),
            "rules": ["No implicit runtime download", "Only two recorded owned UUIDs may be deleted",
                      "No mutation kill, retry, erase, all, booted, unavailable or default-set mutation",
                      "Unknown result preserves fixtures; no automatic retry or cleanup",
                      "No recursive filesystem cleanup; retain evidence and private set"]}


def validate_plan(plan, path, expected_sha256, output_root, data):
    if digest(data) != expected_sha256 or not re.fullmatch(r"[0-9a-f]{64}", expected_sha256):
        raise Refusal("Reviewed plan digest mismatch")
    if not isinstance(plan, dict) or plan.get("planPath") != str(Path(path).resolve(strict=True)):
        raise Refusal("Reviewed plan path mismatch")
    if plan.get("outputRoot") != str(Path(output_root).resolve(strict=True)):
        raise Refusal("Reviewed output root mismatch")
    expected = build_plan(plan["planID"], output_root, plan["planPath"], plan["defaultFileWitness"], plan["outputRootIdentity"])
    if canonical(plan) != canonical(expected):
        raise Refusal("Plan commands, types, limits or scope differ from compiled procedure")
    if identity(output_root, directory=True, private=True) != plan["outputRootIdentity"]:
        raise Refusal("Output root identity changed")
    if file_witness(plan["defaultDeviceSet"]) != plan["defaultFileWitness"]:
        raise Refusal("Default device-set filesystem witness changed since planning")
    for key in ("privateParent", "deviceSet", "evidenceDirectory"):
        if os.path.lexists(plan[key]):
            raise Refusal("Refusing an existing fixture or evidence path")


def decode_json(data):
    def unique(pairs):
        result = {}
        for key, value in pairs:
            if key in result:
                raise Refusal("Duplicate JSON field")
            result[key] = value
        return result
    try:
        return json.loads(data.decode("utf-8"), object_pairs_hook=unique)
    except (ValueError, UnicodeError) as error:
        raise Refusal("Malformed complete inventory") from error


def inventory(devices, runtimes, pairs):
    device_root, runtime_root, pair_root = map(decode_json, (devices, runtimes, pairs))
    if set(device_root) != {"devices"} or set(runtime_root) != {"runtimes"} or set(pair_root) != {"pairs"}:
        raise Refusal("Incomplete inventory envelope")
    if not isinstance(device_root["devices"], dict) or not isinstance(runtime_root["runtimes"], list) or not isinstance(pair_root["pairs"], dict):
        raise Refusal("Malformed inventory collections")
    rows = {}
    for runtime, group in device_root["devices"].items():
        if not isinstance(group, list):
            raise Refusal("Malformed device group")
        for row in group:
            key = full_uuid(row.get("udid"))
            if key in rows or len(rows) >= LIMITS["devices"]:
                raise Refusal("Duplicate or excessive devices")
            if row.get("state") not in {"Booted", "Booting", "Shutdown", "Shutting Down", "Creating"} or type(row.get("isAvailable")) is not bool:
                raise Refusal("Unknown device state or availability")
            rows[key] = {"udid": key, "runtime": runtime, "type": row.get("deviceTypeIdentifier"),
                         "name": row.get("name"), "state": row["state"], "available": row["isAvailable"]}
    runtime_rows = runtime_root["runtimes"]
    if len(runtime_rows) > 256 or len(pair_root["pairs"]) > 1024:
        raise Refusal("Excessive runtime or pair inventory")
    runtime_ids = [row.get("identifier") for row in runtime_rows]
    if len(set(runtime_ids)) != len(runtime_ids):
        raise Refusal("Duplicate runtime identity")
    return {"devices": rows, "runtimes": runtime_rows, "pairs": pair_root["pairs"]}


def require_installed_runtime(observed):
    matches = [r for r in observed["runtimes"] if r.get("identifier") == RUNTIME]
    if len(matches) != 1:
        raise Refusal("Exact installed runtime missing")
    runtime = matches[0]
    types = runtime.get("supportedDeviceTypes")
    if runtime.get("isAvailable") is not True or runtime.get("version") != "27.0" or not isinstance(types, list):
        raise Refusal("Exact runtime unavailable or unsupported")
    identifiers = [t.get("identifier") for t in types]
    if identifiers.count(DEVICE_TYPE) != 1:
        raise Refusal("Exact device type not installed for runtime; no download permitted")


def verify_owned(observed, owned, states, names):
    if set(observed["devices"]) != set(owned.values()) or observed["pairs"]:
        raise Refusal("Foreign, missing or paired device in private set")
    for role, key in owned.items():
        row = observed["devices"][key]
        if row != {"udid": key, "runtime": RUNTIME, "type": DEVICE_TYPE, "name": names[role],
                   "state": states[role], "available": True}:
            raise Refusal("Owned device identity, availability or state changed")


class Driver:
    def __init__(self, plan, output_anchor, evidence_anchor):
        self.plan = plan
        self.output_anchor = output_anchor
        self.evidence_anchor = evidence_anchor
        self.tool_identity = identity(SIMCTL)
        self.tmp_anchor = VerifiedDirectory.open_existing("/private/tmp")
        self.private_anchor = None
        self.set_anchor = None
        self.deadline = time.monotonic() + LIMITS["wallSeconds"]
        self.count = 0
        self.records = []
        self.owned = {}
        self.report = {"classification": CLASSIFICATION, "productionRegistry": "DENIED", "status": "uncertain",
                       "ownedUUIDs": self.owned, "commands": self.records, "automaticCleanup": False}

    def command(self, argv, mutation=False):
        self.output_anchor.require_current()
        self.evidence_anchor.require_current()
        self.tmp_anchor.require_current()
        if self.private_anchor:
            self.private_anchor.require_current()
        if self.set_anchor:
            self.set_anchor.require_current()
        self.count += 1
        if self.count > LIMITS["commands"] or time.monotonic() >= self.deadline:
            raise Refusal("Finite command or wall deadline exhausted")
        if argv[0] == SIMCTL and identity(SIMCTL) != self.tool_identity:
            raise Refusal("Pinned executable identity changed")
        if mutation:
            if identity(self.plan["privateParent"], directory=True, private=True) != self.report.get("ownedParentIdentity") or identity(self.plan["deviceSet"], directory=True, private=True) != self.report.get("ownedSetIdentity"):
                raise Refusal("Owned mutation scope changed")
            if file_witness(self.plan["defaultDeviceSet"]) != self.plan["defaultFileWitness"]:
                raise Refusal("Original host filesystem witness changed")
            prefix = [SIMCTL, "--set", self.plan["deviceSet"]]
            allowed = [self.plan["commands"]["createTarget"], self.plan["commands"]["createWitness"]]
            if "target" in self.owned:
                allowed += [prefix + [verb, self.owned["target"]] for verb in ("boot", "shutdown")]
            allowed += [prefix + ["delete", key] for key in self.owned.values()]
            if argv not in allowed:
                raise Refusal("Mutation differs from fixed owned command")
        end = min(self.deadline, time.monotonic() + LIMITS["commandSeconds"])
        record = {"argv": argv, "mutation": mutation, "observedOwnedWait": False, "timeout": False}
        record["argvSHA256"] = digest(canonical(argv))
        self.records.append(record)
        process = subprocess.Popen(argv, env=ENV, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                                   stderr=subprocess.PIPE, start_new_session=True)
        record["ownedPID"] = process.pid
        selector = selectors.DefaultSelector()
        captures = {"stdout": bytearray(), "stderr": bytearray()}
        overflow = False
        for label, stream in (("stdout", process.stdout), ("stderr", process.stderr)):
            os.set_blocking(stream.fileno(), False)
            selector.register(stream, selectors.EVENT_READ, label)
        try:
            while selector.get_map() or process.poll() is None:
                remaining = end - time.monotonic()
                if remaining <= 0:
                    record["timeout"] = True
                    raise Refusal("Child deadline exceeded; no kill, retry or cleanup")
                for key, _ in selector.select(min(remaining, 0.05)):
                    data = os.read(key.fileobj.fileno(), 65536)
                    if not data:
                        selector.unregister(key.fileobj)
                    else:
                        capture = captures[key.data]
                        room = LIMITS["streamBytes"] - len(capture)
                        capture.extend(data[:room])
                        overflow = overflow or len(data) > room
            code = process.wait(timeout=max(0.001, end - time.monotonic()))
            record.update(observedOwnedWait=True, exitCode=code, overflow=overflow)
            for label, data in captures.items():
                record[label + "SHA256"] = digest(data)
                self.evidence_anchor.write_new(f"{self.count:02d}-{label}.bin", bytes(data))
            if code != 0 or overflow:
                raise Refusal("Child refusal, abnormal exit or bounded-output overflow; no retry")
            return bytes(captures["stdout"])
        finally:
            selector.close()
            # Closing streams is not proof of exit. Never terminate/kill a
            # mutating child; timeout leaves the set and owned identities intact.
            process.stdout.close(); process.stderr.close()

    def observe(self, root):
        replies = [self.command([SIMCTL, "--set", root, "list", kind, "-j"])
                   for kind in ("devices", "runtimes", "pairs")]
        parsed = inventory(*replies)
        return parsed, digest(canonical([decode_json(reply) for reply in replies]))

    def outside_unchanged(self, baseline):
        _, current = self.observe(self.plan["defaultDeviceSet"])
        if current != baseline or file_witness(self.plan["defaultDeviceSet"]) != self.plan["defaultFileWitness"]:
            raise Refusal("Original default-set witness changed; preserve fixtures")

    def run(self):
        version_path = "/Applications/Xcode.app/Contents/version.plist"
        metadata = plistlib.loads(read_regular(version_path, LIMITS["streamBytes"]))
        if (metadata.get("CFBundleShortVersionString"), metadata.get("ProductBuildVersion")) != ("27.0", "27A266a"):
            raise Refusal("Pinned Xcode metadata mismatch")
        self.command(self.plan["commands"]["signature"])
        self.report["simctlSHA256"] = digest(read_regular(SIMCTL, LIMITS["executableBytes"]))
        self.report["simctlIdentity"] = self.tool_identity
        version = self.command(self.plan["commands"]["version"])
        if not re.fullmatch(rb"@\(#\)PROGRAM:simctl +PROJECT:CoreSimulator-1171\.7\n?", version):
            raise Refusal("Pinned CoreSimulator version mismatch")
        outside, baseline = self.observe(self.plan["defaultDeviceSet"])
        require_installed_runtime(outside)
        self.outside_unchanged(baseline)
        self.report["outsideBeforeSHA256"] = baseline
        parent = Path(self.plan["privateParent"])
        self.private_anchor = self.tmp_anchor.create_directory(parent.name)
        device_set = Path(self.plan["deviceSet"])
        self.set_anchor = self.private_anchor.create_directory("device-set")
        self.report["ownedParentIdentity"] = self.private_anchor.require_current()
        self.report["ownedSetIdentity"] = self.set_anchor.require_current()
        witness = canonical({"outsideWitness": self.plan["planID"]})
        self.evidence_anchor.write_new("outside-witness.bin", witness)
        names = {"target": self.plan["targetName"], "witness": self.plan["witnessName"]}
        for role, name in names.items():
            output = self.command([SIMCTL, "--set", str(device_set), "create", name, DEVICE_TYPE, RUNTIME], mutation=True)
            key = full_uuid(output.decode("ascii").strip())
            if key in self.owned.values():
                raise Refusal("Duplicate created identity")
            self.owned[role] = key
            self.save_report()
        current, _ = self.observe(str(device_set))
        verify_owned(current, self.owned, {"target": "Shutdown", "witness": "Shutdown"}, names)
        self.command([SIMCTL, "--set", str(device_set), "boot", self.owned["target"]], mutation=True)
        for attempt in range(LIMITS["bootObservations"]):
            current, before = self.observe(str(device_set))
            if current["devices"].get(self.owned["target"], {}).get("state") == "Booted":
                break
            if attempt + 1 == LIMITS["bootObservations"]:
                raise Refusal("Target did not reach Booted in bounded read observations")
            time.sleep(min(1, max(0, self.deadline - time.monotonic())))
        verify_owned(current, self.owned, {"target": "Booted", "witness": "Shutdown"}, names)
        original_witness = current["devices"][self.owned["witness"]]
        self.report["ownedBeforeSHA256"] = before
        self.outside_unchanged(baseline)
        self.command([SIMCTL, "--set", str(device_set), "shutdown", self.owned["target"]], mutation=True)
        current, after = self.observe(str(device_set))
        verify_owned(current, self.owned, {"target": "Shutdown", "witness": "Shutdown"}, names)
        if current["devices"][self.owned["witness"]] != original_witness or self.evidence_anchor.read_regular("outside-witness.bin", 4096, private=True) != witness:
            raise Refusal("Outside target or private-file witness changed")
        self.outside_unchanged(baseline)
        self.report.update(ownedAfterSHA256=after, outsideAfterSHA256=baseline, semanticsVerified=True)
        # No broad selectors or set removal: only recorded full IDs, validated
        # Shutdown immediately before each individually owned deletion.
        remaining = dict(self.owned)
        deleted = []
        for role in ("target", "witness"):
            current, _ = self.observe(str(device_set))
            verify_owned(current, remaining, {r: "Shutdown" for r in remaining}, names)
            if self.evidence_anchor.read_regular("outside-witness.bin", 4096, private=True) != witness:
                raise Refusal("Private-file witness changed before cleanup")
            self.outside_unchanged(baseline)
            if identity(device_set, directory=True, private=True) != self.report["ownedSetIdentity"]:
                raise Refusal("Owned device-set identity changed")
            self.command([SIMCTL, "--set", str(device_set), "delete", remaining[role]], mutation=True)
            deleted.append(remaining.pop(role))
            self.report["deletedOwnedUUIDs"] = deleted
            self.save_report()
        current, _ = self.observe(str(device_set))
        verify_owned(current, {}, {}, names)
        self.outside_unchanged(baseline)
        self.report["status"] = "SDK-semantics-verified"
        self.report["privateParentRetained"] = str(parent)

    def save_report(self):
        name = f"report-{len(self.records):02d}-{len(self.owned):02d}-{len(self.report.get('deletedOwnedUUIDs', [])):02d}.json"
        self.evidence_anchor.require_current()
        try:
            os.stat(name, dir_fd=self.evidence_anchor.fd, follow_symlinks=False)
        except FileNotFoundError:
            self.evidence_anchor.write_new(name, canonical(self.report))

    def close(self):
        for anchor in (self.set_anchor, self.private_anchor, self.tmp_anchor):
            if anchor:
                anchor.close()


def write_new(path, data):
    path = Path(path)
    with VerifiedDirectory.open_existing(path.parent, private=True) as anchored:
        anchored.write_new(path.name, data)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-root", required=True, help="Existing caller-owned canonical mode0700 evidence directory")
    parser.add_argument("--plan", help="Write one new mode0600 plan here; otherwise print only")
    parser.add_argument("--execute", metavar="EXISTING_REVIEWED_PLAN", help="Owner-authorized execution only; never implied by planning")
    parser.add_argument("--plan-sha256", help="Exact digest from review of that existing plan")
    args = parser.parse_args(argv)
    if not args.execute:
        if args.plan_sha256:
            raise Refusal("Digest is meaningful only with execution")
        path = str(Path(args.plan).absolute()) if args.plan else None
        plan = build_plan(str(uuid.uuid4()), args.output_root, path, file_witness(default_set_path()))
        data = canonical(plan)
        if len(data) > LIMITS["planBytes"]:
            raise Refusal("Plan exceeds byte bound")
        if plan["planPath"]:
            with VerifiedDirectory.open_existing(plan["outputRoot"], private=True) as anchored:
                if anchored.require_current() != plan["outputRootIdentity"]:
                    raise Refusal("Planned output root changed")
                anchored.write_new(Path(plan["planPath"]).name, data)
        print(json.dumps({"plan": plan, "planSHA256": digest(data), "classification": CLASSIFICATION}, indent=2))
        return 0
    if args.plan or not args.plan_sha256:
        raise Refusal("Execution requires only the existing plan, reviewed digest and exact output root")
    path = str(Path(args.execute).absolute())
    data = read_regular(path, LIMITS["planBytes"], private=True)
    plan = decode_json(data)
    validate_plan(plan, path, args.plan_sha256, args.output_root, data)
    with VerifiedDirectory.open_existing(plan["outputRoot"], private=True) as output:
        if output.require_current() != plan["outputRootIdentity"]:
            raise Refusal("Reviewed output root changed")
        with output.create_directory(Path(plan["evidenceDirectory"]).name) as evidence:
            evidence.write_new("reviewed-plan.json", data)
            driver = Driver(plan, output, evidence)
            try:
                driver.report.update(planSHA256=digest(data),
                    driverSHA256=digest(read_regular(str(Path(__file__).absolute()), LIMITS["driverBytes"])))
                try:
                    driver.run()
                except Exception:
                    driver.report["status"] = "uncertain-preserve-fixtures"
                    # A replaced evidence namespace cannot redirect the failure
                    # report; retain owned fixtures and refuse that publication.
                    try:
                        driver.save_report()
                    except (Refusal, OSError):
                        pass
                    print(json.dumps({"status": driver.report["status"], "classification": CLASSIFICATION,
                                      "evidenceDirectory": plan["evidenceDirectory"], "ownedUUIDs": driver.owned}))
                    return 1
                driver.save_report()
                print(json.dumps(driver.report, indent=2))
                return 0
            finally:
                driver.close()


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (Refusal, OSError, KeyError, TypeError, ValueError):
        print("REFUSED: procedure or identity validation failed; no automatic retry or cleanup", file=sys.stderr)
        sys.exit(2)
