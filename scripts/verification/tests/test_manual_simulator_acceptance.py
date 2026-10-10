"""Pure/local-file tests only. Never invokes simctl, codesign or subprocesses."""
import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

PATH = Path(__file__).resolve().parents[1] / "manual-simulator-acceptance.py"
SPEC = importlib.util.spec_from_file_location("manual_semantics", PATH)
driver = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(driver)


class SemanticsPreparationTests(unittest.TestCase):
    def test_staging_name_replacement_at_link_refuses_and_preserves_unknown_leaves(self):
        for replacement in ("symlink", "regular"):
            with self.subTest(replacement=replacement), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary).resolve(); os.chmod(root, 0o700)
                foreign = root / "foreign.txt"
                foreign.write_bytes(b"other"); os.chmod(foreign, 0o600)
                original_link = os.link
                substituted = []
                def swap_then_link(source, destination, *, src_dir_fd, dst_dir_fd, follow_symlinks):
                    self.assertFalse(follow_symlinks)
                    substituted.append(source)
                    os.unlink(source, dir_fd=src_dir_fd)
                    if replacement == "symlink":
                        os.symlink("foreign.txt", source, dir_fd=src_dir_fd)
                    else:
                        original_link("foreign.txt", source, src_dir_fd=src_dir_fd,
                            dst_dir_fd=src_dir_fd, follow_symlinks=False)
                    original_link(source, destination, src_dir_fd=src_dir_fd,
                        dst_dir_fd=dst_dir_fd, follow_symlinks=False)
                with driver.VerifiedDirectory.open_existing(root, private=True) as anchored:
                    with patch.object(driver.os, "link", swap_then_link), patch.object(driver.subprocess, "Popen") as spawn:
                        with self.assertRaises(driver.Refusal):
                            anchored.write_new("publication.json", b"owned")
                        spawn.assert_not_called()
                self.assertEqual(len(substituted), 1)
                final = root / "publication.json"
                staging = root / substituted[0]
                self.assertTrue(os.path.lexists(final), "Never blindly unlink the unexpected final leaf")
                self.assertTrue(os.path.lexists(staging), "Never unlink a substituted staging leaf")
                if replacement == "symlink":
                    self.assertTrue(final.is_symlink()); self.assertTrue(staging.is_symlink())
                else:
                    self.assertEqual(final.stat().st_ino, foreign.stat().st_ino)
                    self.assertEqual(staging.stat().st_ino, foreign.stat().st_ino)
                self.assertEqual(foreign.read_bytes(), b"other")

    @staticmethod
    def flagged_stat(value):
        fields = {name: getattr(value, name) for name in dir(value) if name.startswith("st_")}
        fields["st_flags"] = fields.get("st_flags", 0) | 0x40000000
        return SimpleNamespace(**fields)

    def test_dataless_files_and_directories_refuse_before_content_or_enumeration(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary).resolve()
            file = root / "owned"; file.write_bytes(b"owned")
            flagged_file = self.flagged_stat(file.stat())
            original_lstat = Path.lstat
            def file_stat(path, *args, **kwargs):
                return flagged_file if path == file else original_lstat(path, *args, **kwargs)
            with patch.object(Path, "lstat", file_stat), patch.object(driver.os, "open", side_effect=AssertionError("opened dataless file")) as opened:
                with self.assertRaises(driver.Refusal):
                    driver.read_regular(file, 1024)
                opened.assert_not_called()
            flagged_directory = self.flagged_stat(root.stat())
            def directory_stat(path, *args, **kwargs):
                return flagged_directory if path == root else original_lstat(path, *args, **kwargs)
            with patch.object(Path, "lstat", directory_stat), patch.object(driver, "read_regular", side_effect=AssertionError("read below dataless directory")) as read, patch.object(Path, "iterdir", side_effect=AssertionError("enumerated dataless directory")) as listed:
                with self.assertRaises(driver.Refusal):
                    driver.file_witness(str(root))
                read.assert_not_called(); listed.assert_not_called()

    def test_opened_file_dataless_flag_is_rechecked_before_read(self):
        with tempfile.TemporaryDirectory() as temporary:
            file = Path(temporary).resolve() / "owned"; file.write_bytes(b"owned")
            flagged = self.flagged_stat(file.stat())
            original_fstat = os.fstat
            def fd_stat(fd):
                value = original_fstat(fd)
                return flagged if (value.st_dev, value.st_ino) == (flagged.st_dev, flagged.st_ino) else value
            with patch.object(driver.os, "fstat", fd_stat), patch.object(driver.os, "read", side_effect=AssertionError("read hydrated content")) as read:
                with self.assertRaises(driver.Refusal):
                    driver.read_regular(file, 1024)
                read.assert_not_called()

    def test_retained_root_and_evidence_refuse_replaced_path_without_redirected_write(self):
        for replaced in ("root", "evidence"):
            with tempfile.TemporaryDirectory() as temporary:
                sandbox = Path(temporary).resolve()
                root = sandbox / "owned"; root.mkdir(mode=0o700)
                redirected = sandbox / "redirected"; redirected.mkdir(mode=0o700)
                with driver.VerifiedDirectory.open_existing(root, private=True) as anchored:
                    with anchored.create_directory("evidence") as evidence:
                        original_identity = driver.identity
                        def fixture_identity(path, *args, **kwargs):
                            return {"fixtureOnly": True} if str(path) == driver.SIMCTL else original_identity(path, *args, **kwargs)
                        with patch.object(driver, "identity", fixture_identity):
                            experiment = driver.Driver({}, anchored, evidence)
                        original = root if replaced == "root" else root / "evidence"
                        moved = sandbox / ("saved-" + replaced)
                        original.rename(moved)
                        original.symlink_to(redirected, target_is_directory=True)
                        with patch.object(driver.subprocess, "Popen") as spawn:
                            try:
                                with self.assertRaises(driver.Refusal):
                                    evidence.write_new("evidence.json", b"owned")
                                with self.assertRaises(driver.Refusal):
                                    experiment.command([driver.SIMCTL, "--version"])
                                spawn.assert_not_called()
                            finally:
                                experiment.close()
                        self.assertFalse((redirected / "evidence.json").exists())
                        self.assertFalse((moved / "evidence.json").exists())

    def test_retained_ancestor_replacement_refuses_creation_and_initial_symlink_refuses(self):
        with tempfile.TemporaryDirectory() as temporary:
            sandbox = Path(temporary).resolve()
            parent = sandbox / "parent"; parent.mkdir(mode=0o700)
            root = parent / "owned"; root.mkdir(mode=0o700)
            redirected = sandbox / "redirected"; redirected.mkdir(mode=0o700)
            with driver.VerifiedDirectory.open_existing(root, private=True) as anchored:
                parent.rename(sandbox / "saved-parent")
                parent.symlink_to(redirected, target_is_directory=True)
                with patch.object(driver.subprocess, "Popen") as spawn:
                    with self.assertRaises(driver.Refusal):
                        anchored.create_directory("fixture")
                    spawn.assert_not_called()
                self.assertFalse((redirected / "fixture").exists())
                self.assertFalse((sandbox / "saved-parent" / "owned" / "fixture").exists())
            with self.assertRaises(driver.Refusal):
                driver.VerifiedDirectory.open_existing(parent, private=True)

    def test_dry_run_never_invokes_sdk_and_writes_only_requested_plan(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary).resolve()
            os.chmod(root, 0o700)
            witness = {"filesystem": "synthetic-data-only"}
            with patch.object(driver, "file_witness", return_value=witness), patch.object(driver.subprocess, "Popen") as spawn:
                with contextlib.redirect_stdout(io.StringIO()) as output:
                    self.assertEqual(driver.main(["--output-root", str(root)]), 0)
                spawn.assert_not_called()
                self.assertEqual(list(root.iterdir()), [])
                shown = json.loads(output.getvalue())
                self.assertEqual(shown["plan"]["productionRegistry"], "DENIED")
                self.assertIsNone(shown["plan"]["planPath"])
                plan_path = root / "reviewed.json"
                with contextlib.redirect_stdout(io.StringIO()):
                    self.assertEqual(driver.main(["--output-root", str(root), "--plan", str(plan_path)]), 0)
                spawn.assert_not_called()
                self.assertEqual(list(root.iterdir()), [plan_path])
                self.assertEqual(plan_path.stat().st_mode & 0o777, 0o600)

    def test_plan_tampering_and_existing_fixture_refuse_before_spawn(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary).resolve(); os.chmod(root, 0o700)
            plan_path = root / "reviewed.json"
            witness = {"filesystem": "synthetic-data-only"}
            plan = driver.build_plan("9C718062-6318-4503-949A-99E63661C36F", str(root), str(plan_path), witness)
            data = driver.canonical(plan)
            driver.write_new(plan_path, data)
            with patch.object(driver, "file_witness", return_value=witness), patch.object(driver.subprocess, "Popen") as spawn:
                driver.validate_plan(plan, str(plan_path), driver.digest(data), str(root), data)
                for key, changed in [("commands", {"shutdown": ["/bin/echo", "unsafe"]}), ("limits", {}), ("runtime", "other")]:
                    edited = dict(plan); edited[key] = changed
                    forged = driver.canonical(edited)
                    with self.assertRaises(driver.Refusal):
                        driver.validate_plan(edited, str(plan_path), driver.digest(forged), str(root), forged)
                with patch.object(driver, "file_witness", return_value={"changed": True}):
                    with self.assertRaises(driver.Refusal):
                        driver.validate_plan(plan, str(plan_path), driver.digest(data), str(root), data)
                with patch.object(driver.os.path, "lexists", return_value=True):
                    with self.assertRaises(driver.Refusal):
                        driver.validate_plan(plan, str(plan_path), driver.digest(data), str(root), data)
                spawn.assert_not_called()

    def test_runtime_must_be_exact_available_and_support_exact_type(self):
        row = {"identifier": driver.RUNTIME, "version": "27.0", "isAvailable": True,
               "supportedDeviceTypes": [{"identifier": driver.DEVICE_TYPE}]}
        driver.require_installed_runtime({"runtimes": [row]})
        for replacement in ({}, {"isAvailable": False}, {"version": "26.0"}, {"supportedDeviceTypes": []}):
            invalid = dict(row); invalid.update(replacement)
            if not replacement:
                invalid = {}
            with self.assertRaises(driver.Refusal):
                driver.require_installed_runtime({"runtimes": [invalid]})

    def test_postcondition_is_exact_unpaired_and_includes_witness(self):
        target = "9C718062-6318-4503-949A-99E63661C36F"
        witness = "FC5C16F6-BCE4-49B3-96EC-C56A5AD375F1"
        names = {"target": "target", "witness": "witness"}
        owned = {"target": target, "witness": witness}
        devices = {key: {"udid": key, "runtime": driver.RUNTIME, "type": driver.DEVICE_TYPE,
                         "name": names[role], "state": "Shutdown", "available": True}
                   for role, key in owned.items()}
        inventory = {"devices": devices, "pairs": {}}
        driver.verify_owned(inventory, owned, {"target": "Shutdown", "witness": "Shutdown"}, names)
        for field, value in [("type", "other"), ("runtime", "other"), ("state", "Booted"), ("available", False), ("name", "foreign")]:
            changed = {key: dict(row) for key, row in devices.items()}
            changed[witness][field] = value
            with self.assertRaises(driver.Refusal):
                driver.verify_owned({"devices": changed, "pairs": {}}, owned,
                    {"target": "Shutdown", "witness": "Shutdown"}, names)
        with self.assertRaises(driver.Refusal):
            driver.verify_owned({"devices": devices, "pairs": {"foreign": {}}}, owned,
                {"target": "Shutdown", "witness": "Shutdown"}, names)

    def test_full_identity_and_duplicate_json_reject_aliases(self):
        for value in ("booted", "all", "9C718062", "../device", None):
            with self.assertRaises(driver.Refusal):
                driver.full_uuid(value)
        with self.assertRaises(driver.Refusal):
            driver.decode_json(b'{"devices":{},"devices":{}}')
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary).resolve()
            regular = root / "owned"; regular.write_bytes(b"witness")
            link = root / "alias"; link.symlink_to(regular)
            with self.assertRaises(driver.Refusal):
                driver.read_regular(link, 1024)


if __name__ == "__main__":
    unittest.main()
