"""Atomic installation tests; runtime execution is verified separately over SSH."""
import concurrent.futures
import hashlib
import importlib.util
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tarfile
import tempfile
import unittest

SOURCE = Path(__file__).with_name("remote-install.py")
spec = importlib.util.spec_from_file_location("remote_install", SOURCE)
installer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(installer)


class InstallationTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="headless-install-")
        self.addCleanup(temporary.cleanup)
        self.directory = Path(temporary.name)
        self.root = self.directory / "installation with ' spaces"

    def fixture(self, build="test-one", change=None, unsafe=None):
        seed = "toolchains/moonbit/linux-x64"
        executables = ["bin/openseek", "bin/moonrun", "bin/rg"] + [seed + "/bin/" + name for name in ["moon", "moonc", "moonx", "moonrun"]]
        names = executables + ["lib/openseek.wasm", "share/doc/moonbit/index.md", "web/viz/index.html", "web/viz/viz_app.js", seed + "/.openseek-moonbit-seed-version", seed + "/lib/core/moon.mod"]
        payload = {name: (change if name == "bin/rg" and change else name).encode() for name in names}
        manifest = {"schema_version": 1, "build_id": build, "platform": "linux-x64", "protocol_version": 1, "data_schema_version": 1, "moonbit_version": "fixture", "resource_sha256": "a" * 64, "runtime_requirements": {"os": "Linux", "libc": "glibc", "minimum_glibc": "2.35"}, "files": [
            {"path": name, "size": len(data), "mode": 0o755 if name in executables else 0o644, "sha256": hashlib.sha256(data).hexdigest()} for name, data in payload.items()]}
        manifest_data = (json.dumps(manifest) + "\n").encode()
        output = io.BytesIO()
        with tarfile.open(fileobj=output, mode="w:gz") as archive:
            for name, data in {**payload, "manifest.json": manifest_data}.items():
                member = tarfile.TarInfo("./" + name)
                member.size = len(data)
                archive.addfile(member, io.BytesIO(data))
            if unsafe:
                archive.addfile(unsafe, io.BytesIO(b"bad") if unsafe.size else None)
        data = output.getvalue()
        request = {"root": str(self.root), "build_id": build, "platform": "linux-x64", "manifest_sha256": hashlib.sha256(manifest_data).hexdigest(), "archive_size": len(data), "archive_sha256": hashlib.sha256(data).hexdigest()}
        return request, data

    def install(self, request, data, runtime=lambda *_: None):
        return installer.install(request, io.BytesIO(data), check_runtime=runtime)

    def final(self, request):
        return self.root / "versions" / request["build_id"] / request["platform"]

    def no_staging(self):
        self.assertEqual(list(self.root.glob(".staging-*")), [])

    def test_verified_install_reuses_exact_version_and_keeps_old_versions(self):
        request, data = self.fixture()
        self.assertEqual(self.install(request, data)["status"], "installed")
        inode = (self.final(request) / "bin/rg").stat().st_ino
        self.assertEqual(self.install(request, data)["status"], "reused")
        self.assertEqual((self.final(request) / "bin/rg").stat().st_ino, inode)
        self.assertEqual(installer.inspect(request)["status"], "reused")
        newer, payload = self.fixture("test-two")
        self.assertEqual(self.install(newer, payload)["status"], "installed")
        installer.verify_tree(self.final(request), request)
        self.no_staging()

    def test_interrupted_or_corrupt_upload_never_replaces_a_verified_version(self):
        old, data = self.fixture()
        self.install(old, data)
        new, data = self.fixture("test-two")
        for body in [data[:-4], data + b"extra", bytes([data[0] ^ 1]) + data[1:]]:
            with self.subTest(length=len(body)):
                with self.assertRaises(installer.InstallError):
                    self.install(new, body)
                self.assertFalse(self.final(new).exists())
                installer.verify_tree(self.final(old), old)
                self.no_staging()

    def test_archive_traversal_links_and_duplicate_files_are_rejected_before_publication(self):
        outside = self.directory / "outside"
        outside.write_text("preserved")
        traversal = tarfile.TarInfo("../../outside")
        traversal.size = 3
        link = tarfile.TarInfo("escape")
        link.type = tarfile.SYMTYPE
        link.linkname = "../../outside"
        duplicate = tarfile.TarInfo("bin/rg")
        duplicate.size = 3
        for entry in [traversal, link, duplicate]:
            request, data = self.fixture(unsafe=entry)
            with self.subTest(name=entry.name):
                with self.assertRaises(installer.InstallError):
                    self.install(request, data)
                self.assertFalse(self.final(request).exists())
                self.assertEqual(outside.read_text(), "preserved")
                self.no_staging()

    def test_same_build_collision_and_installed_corruption_are_errors_not_missing(self):
        original, data = self.fixture()
        self.install(original, data)
        changed, data = self.fixture(change="different payload")
        with self.assertRaisesRegex(installer.InstallError, "Manifest digest mismatch"):
            self.install(changed, data)
        with self.assertRaises(installer.InstallError):
            installer.inspect(changed)
        installer.verify_tree(self.final(original), original)
        (self.final(original) / "bin/rg").write_text("tampered")
        with self.assertRaisesRegex(installer.InstallError, "differs from manifest"):
            installer.inspect(original)
        self.no_staging()

    def test_runtime_failure_and_unsafe_root_leave_existing_content_untouched(self):
        original, data = self.fixture()
        self.install(original, data)
        newer, data = self.fixture("test-two")
        def fail_runtime(*_args):
            raise installer.InstallError("runtime", "unusable executable")
        with self.assertRaisesRegex(installer.InstallError, "unusable executable"):
            self.install(newer, data, fail_runtime)
        self.assertFalse(self.final(newer).exists())
        installer.verify_tree(self.final(original), original)
        self.no_staging()
        # Parent links inside the installation namespace cannot redirect a
        # future build into an unrelated directory owned by the same user.
        versions = self.root / "versions"
        saved = self.root / "saved-versions"
        versions.rename(saved)
        versions.symlink_to(saved, target_is_directory=True)
        with self.assertRaisesRegex(installer.InstallError, "owner-only"):
            self.install(newer, data)
        with self.assertRaises(installer.InstallError):
            installer.inspect(original)
        versions.unlink()
        saved.rename(versions)
        self.root.chmod(0o755)
        with self.assertRaisesRegex(installer.InstallError, "owner-only"):
            self.install(newer, data)
        self.assertEqual(self.root.stat().st_mode & 0o777, 0o755)
        self.root.chmod(0o700)
        installer.verify_tree(self.final(original), original)

    def test_retry_removes_only_marked_abandoned_stages_under_the_install_lock(self):
        self.root.mkdir(mode=0o700)
        abandoned = self.root / ".staging-abandoned"
        abandoned.mkdir()
        (abandoned / ".seekmoon-install-stage").write_bytes(b"seekmoon-upload-v1\n")
        (abandoned / "partial-upload").write_text("partial package")
        unrelated = self.root / ".staging-user-notes"
        unrelated.mkdir()
        (unrelated / "keep").write_text("user notes")
        request, data = self.fixture()
        self.assertEqual(self.install(request, data)["status"], "installed")
        self.assertFalse(abandoned.exists())
        self.assertEqual((unrelated / "keep").read_text(), "user notes")

    def test_concurrent_processes_publish_one_version_and_verify_reuse(self):
        request, data = self.fixture()
        code = "import runpy,sys,json; m=runpy.run_path(sys.argv[1]); print(json.dumps(m['install'](json.loads(sys.argv[2]),sys.stdin.buffer,check_runtime=lambda *_:None)))"
        def run():
            process = subprocess.run([sys.executable, "-B", "-c", code, str(SOURCE), json.dumps(request)], input=data, capture_output=True, timeout=20)
            self.assertEqual(process.returncode, 0, process.stderr.decode())
            return json.loads(process.stdout)
        with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
            replies = list(pool.map(lambda _: run(), range(2)))
        self.assertEqual(sorted(reply["status"] for reply in replies), ["installed", "reused"])
        installer.verify_tree(self.final(request), request)
        self.no_staging()


if __name__ == "__main__":
    unittest.main()
