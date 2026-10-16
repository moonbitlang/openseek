"""Owner-only, versioned headless installation. Executed over an SSH stdin pipe."""
import contextlib
import fcntl
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import signal
import shutil
import stat
import subprocess
import sys
import tarfile
import tempfile
import time

STAGE_MARKER = b"seekmoon-upload-v1\n"
MAX_ARCHIVE = 1024 ** 3
MAX_FILES = 100000
MAX_BYTES = 4 * 1024 ** 3
MAX_MANIFEST = 8 * 1024 ** 2
PLATFORMS = {"x86_64": "linux-x64", "aarch64": "linux-arm64"}


class InstallError(RuntimeError):
    def __init__(self, stage, message):
        super().__init__(message)
        self.stage = stage


def digest(path):
    value = hashlib.sha256()
    with open(path, "rb") as source:
        for chunk in iter(lambda: source.read(65536), b""):
            value.update(chunk)
    return value.hexdigest()


def probe():
    if sys.version_info < (3, 8):
        raise InstallError("probe", "Python 3.8 or newer is required for package preparation")
    machine = platform.machine()
    if platform.system() != "Linux" or machine not in PLATFORMS:
        raise InstallError("probe", "Only Linux x86_64 and aarch64 working hosts are supported")
    result = subprocess.run(["getconf", "GNU_LIBC_VERSION"], capture_output=True, text=True, timeout=5, check=True)
    match = re.fullmatch(r"glibc (\d+)\.(\d+)\s*", result.stdout)
    if not match or tuple(map(int, match.groups())) < (2, 35):
        raise InstallError("probe", "The headless runtime requires glibc 2.35 or newer")
    home = Path.home().resolve(strict=True)
    return {"platform": PLATFORMS[machine], "home": str(home), "libc": result.stdout.strip()}


def private_directory(path, create=True):
    path = Path(path)
    if not path.is_absolute() or ".." in path.parts:
        raise InstallError("prepare", "Installation root must be an absolute path without parent traversal")
    if create:
        path.mkdir(mode=0o700, parents=True, exist_ok=True)
    info = path.lstat()
    if not stat.S_ISDIR(info.st_mode) or info.st_uid != os.geteuid() or info.st_mode & 0o077:
        raise InstallError("prepare", "Installation directory must be an owner-only directory, not a symlink")
    return path.resolve(strict=True)


@contextlib.contextmanager
def locked(root):
    fd = os.open(root / "install.lock", os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
    try:
        info = os.fstat(fd)
        if not stat.S_ISREG(info.st_mode) or info.st_uid != os.geteuid() or info.st_mode & 0o077:
            raise InstallError("lock", "Unsafe installation lock")
        deadline = time.monotonic() + 10
        while True:
            try:
                fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
                break
            except BlockingIOError:
                if time.monotonic() >= deadline:
                    raise InstallError("lock", "Another package installation is still running")
                time.sleep(0.05)
        # Stages are created only after acquiring this lock. A marked stage
        # left by a dead uploader cannot belong to an active installation.
        for abandoned in root.glob(".staging-*"):
            info = abandoned.lstat()
            if not stat.S_ISDIR(info.st_mode) or info.st_uid != os.geteuid():
                continue
            marker = abandoned / ".seekmoon-install-stage"
            try:
                info = marker.lstat()
            except FileNotFoundError:
                continue
            if stat.S_ISREG(info.st_mode) and info.st_uid == os.geteuid() and info.st_size == len(STAGE_MARKER) and marker.read_bytes() == STAGE_MARKER:
                shutil.rmtree(abandoned)
        yield
    finally:
        os.close(fd)


def valid_path(path):
    return isinstance(path, str) and len(path) <= 1024 and "\\" not in path and not re.search(r"[\x00-\x1f\x7f]", path) and all(p not in ("", ".", "..") for p in path.split("/"))


def expected_fields(request):
    if not isinstance(request, dict) or not isinstance(request.get("build_id"), str) or not re.fullmatch(r"[a-zA-Z0-9][a-zA-Z0-9._-]{0,199}", request["build_id"]):
        raise InstallError("validate", "Invalid build ID")
    if request.get("platform") not in PLATFORMS.values() or not isinstance(request.get("manifest_sha256"), str) or not re.fullmatch(r"[a-f0-9]{64}", request["manifest_sha256"]):
        raise InstallError("validate", "Invalid platform or manifest digest")


def manifest_bytes(data, expected):
    if len(data) > MAX_MANIFEST or hashlib.sha256(data).hexdigest() != expected["manifest_sha256"]:
        raise InstallError("verify", "Manifest digest mismatch or size limit exceeded")
    manifest = json.loads(data)
    if not isinstance(manifest, dict) or any(type(manifest.get(field)) is not int for field in ("schema_version", "protocol_version", "data_schema_version")) or manifest.get("schema_version") != 1 or manifest.get("build_id") != expected["build_id"] or manifest.get("platform") != expected["platform"] or manifest.get("protocol_version") != 1 or manifest.get("data_schema_version") != 1:
        raise InstallError("verify", "Manifest build, platform or schema differs from the requested package")
    if manifest.get("runtime_requirements") != {"os": "Linux", "libc": "glibc", "minimum_glibc": "2.35"}:
        raise InstallError("verify", "Unsupported runtime requirements")
    if not isinstance(manifest.get("moonbit_version"), str) or not manifest["moonbit_version"]:
        raise InstallError("verify", "Missing MoonBit version")
    if not isinstance(manifest.get("resource_sha256"), str) or not re.fullmatch(r"[a-f0-9]{64}", manifest["resource_sha256"]):
        raise InstallError("verify", "Invalid shared-resource digest")
    files = manifest.get("files")
    if not isinstance(files, list) or not 0 < len(files) <= MAX_FILES:
        raise InstallError("verify", "Invalid manifest file list")
    entries = {}
    total = 0
    for entry in files:
        if not isinstance(entry, dict) or not valid_path(entry.get("path")) or entry["path"] == "manifest.json" or entry["path"] in entries or type(entry.get("size")) is not int or entry["size"] < 0 or type(entry.get("mode")) is not int or entry["mode"] not in (0o644, 0o755) or not isinstance(entry.get("sha256"), str) or not re.fullmatch(r"[a-f0-9]{64}", entry["sha256"]):
            raise InstallError("verify", "Invalid or duplicate manifest entry")
        total += entry["size"]
        if total > MAX_BYTES:
            raise InstallError("verify", "Package size limit exceeded")
        entries[entry["path"]] = entry
    seed = "toolchains/moonbit/" + manifest["platform"]
    executables = ["bin/openseek", "bin/moonrun", "bin/rg"] + [seed + "/bin/" + name for name in ["moon", "moonc", "moonx", "moonrun"]]
    required = executables + ["lib/openseek.wasm", "share/doc/moonbit/index.md", "web/viz/index.html", "web/viz/viz_app.js", seed + "/.openseek-moonbit-seed-version"]
    if any(name not in entries for name in required) or not any(seed + "/lib/core/" + name in entries for name in ["moon.mod", "moon.mod.json"]):
        raise InstallError("verify", "Required headless resources are missing")
    if any(entries[name]["mode"] != 0o755 for name in executables):
        raise InstallError("verify", "Required executable lacks executable permissions")
    if any(name == "web/frontend.js" or re.search(r"(^|/)(CEF|Chromium Embedded Framework|libcef\.so|proton)(/|$)", name, re.I) for name in entries):
        raise InstallError("verify", "GUI payload is not a headless package")
    return manifest, entries


def verify_tree(root, expected):
    manifest_path = root / "manifest.json"
    info = manifest_path.lstat()
    if not stat.S_ISREG(info.st_mode) or info.st_size > MAX_MANIFEST:
        raise InstallError("verify", "Invalid installed manifest")
    manifest, entries = manifest_bytes(manifest_path.read_bytes(), expected)
    found = set()
    for directory, dirs, files in os.walk(root, followlinks=False):
        for name in dirs:
            if (Path(directory) / name).is_symlink():
                raise InstallError("verify", "Installed package contains a directory symlink")
        for name in files:
            path = Path(directory) / name
            relative = path.relative_to(root).as_posix()
            info = path.lstat()
            if not stat.S_ISREG(info.st_mode):
                raise InstallError("verify", "Installed package contains a non-regular file")
            if relative == "manifest.json":
                continue
            entry = entries.get(relative)
            if not entry or info.st_size != entry["size"] or stat.S_IMODE(info.st_mode) != entry["mode"] or digest(path) != entry["sha256"]:
                raise InstallError("verify", "Installed file differs from manifest: " + relative)
            found.add(relative)
    if found != entries.keys():
        raise InstallError("verify", "Installed package file set is incomplete")
    return manifest


def runtime_command(args):
    try:
        return subprocess.run(args, stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=10, check=True)
    except subprocess.CalledProcessError as error:
        raise InstallError("runtime", Path(args[0]).name + " failed: " + error.stderr[:4096]) from error
    except (OSError, subprocess.TimeoutExpired) as error:
        raise InstallError("runtime", str(error)) from error


def runtime_check(root, manifest):
    runtime_command([str(root / "bin/moonrun"), "--version"])


def unpack(archive, destination, expected):
    with tarfile.open(archive, "r:gz") as tar:
        members = []
        seen = set()
        raw_manifest = None
        total = 0
        for member in tar:
            name = member.name[2:] if member.name.startswith("./") else member.name
            if name in ("", ".") and member.isdir():
                continue
            if not valid_path(name) or name in seen or not (member.isfile() or member.isdir()):
                raise InstallError("unpack", "Unsafe, duplicate or linked archive entry")
            seen.add(name)
            if len(seen) > MAX_FILES * 2:
                raise InstallError("unpack", "Archive entry limit exceeded")
            if member.size < 0 or member.size > MAX_BYTES:
                raise InstallError("unpack", "Invalid archive member size")
            total += member.size
            if total > MAX_BYTES + MAX_MANIFEST:
                raise InstallError("unpack", "Expanded archive size limit exceeded")
            if name == "manifest.json":
                if not member.isfile() or member.size > MAX_MANIFEST:
                    raise InstallError("unpack", "Invalid archive manifest")
                raw_manifest = tar.extractfile(member).read(MAX_MANIFEST + 1)
            members.append((name, member))
        if raw_manifest is None:
            raise InstallError("unpack", "Archive has no manifest")
        manifest, entries = manifest_bytes(raw_manifest, expected)
        written = set()
        for name, member in members:
            path = destination / name
            if member.isdir():
                path.mkdir(parents=True, exist_ok=True)
                continue
            entry = entries.get(name)
            if name != "manifest.json" and (not entry or member.size != entry["size"]):
                raise InstallError("unpack", "Archive file set or size differs from manifest")
            path.parent.mkdir(parents=True, exist_ok=True)
            hash_value = hashlib.sha256()
            with tar.extractfile(member) as source, path.open("xb") as output:
                for chunk in iter(lambda: source.read(65536), b""):
                    output.write(chunk)
                    hash_value.update(chunk)
                output.flush()
                os.fsync(output.fileno())
            path.chmod(entry["mode"] if entry else 0o644)
            if entry and hash_value.hexdigest() != entry["sha256"]:
                raise InstallError("verify", "Archive file checksum mismatch: " + name)
            if entry:
                written.add(name)
        if written != entries.keys():
            raise InstallError("verify", "Archive is missing manifest files")
    return manifest


def result(root, expected, status):
    return {"status": status, "build_id": expected["build_id"], "platform": expected["platform"], "manifest_sha256": expected["manifest_sha256"], "launcher": str(root / "bin/openseek")}


def inspect(request):
    expected_fields(request)
    root = Path(request["root"])
    try:
        root = private_directory(root, create=False)
    except FileNotFoundError:
        return {"status": "missing"}
    with locked(root):
        try:
            versions = private_directory(root / "versions", create=False)
            build = private_directory(versions / request["build_id"], create=False)
            final = private_directory(build / request["platform"], create=False)
        except FileNotFoundError:
            return {"status": "missing"}
        verify_tree(final, request)
        return result(final, request, "reused")


def install(request, input_stream, check_runtime=runtime_check):
    expected_fields(request)
    if type(request.get("archive_size")) is not int or not 0 < request["archive_size"] <= MAX_ARCHIVE or not isinstance(request.get("archive_sha256"), str) or not re.fullmatch(r"[a-f0-9]{64}", request["archive_sha256"]):
        raise InstallError("upload", "Invalid archive size or checksum")
    root = private_directory(request["root"])
    with locked(root), tempfile.TemporaryDirectory(prefix=".staging-", dir=root) as temporary:
        temporary = Path(temporary)
        (temporary / ".seekmoon-install-stage").write_bytes(STAGE_MARKER)
        archive = temporary / "upload.tar.gz"
        remaining = request["archive_size"]
        hash_value = hashlib.sha256()
        with archive.open("xb") as output:
            while remaining:
                chunk = input_stream.read(min(65536, remaining))
                if not chunk:
                    raise InstallError("upload", "Interrupted package upload")
                remaining -= len(chunk)
                output.write(chunk)
                hash_value.update(chunk)
        if input_stream.read(1) or hash_value.hexdigest() != request["archive_sha256"]:
            raise InstallError("upload", "Package archive checksum or length mismatch")
        versions = private_directory(root / "versions")
        final_parent = private_directory(versions / request["build_id"])
        final = final_parent / request["platform"]
        try:
            private_directory(final, create=False)
        except FileNotFoundError:
            pass
        else:
            verify_tree(final, request)
            return result(final, request, "reused")
        candidate = temporary / "package"
        candidate.mkdir(mode=0o700)
        manifest = unpack(archive, candidate, request)
        check_runtime(candidate, manifest)
        # The install lock owns the absent destination through the rename.
        # No service/data-dir/current-version pointer is changed here.
        for directory, _dirs, _files in os.walk(candidate, topdown=False):
            directory_fd = os.open(directory, os.O_RDONLY | os.O_DIRECTORY)
            try:
                os.fsync(directory_fd)
            finally:
                os.close(directory_fd)
        os.rename(candidate, final)
        fd = os.open(final_parent, os.O_RDONLY | os.O_DIRECTORY)
        try:
            os.fsync(fd)
        finally:
            os.close(fd)
        return result(final, request, "installed")


def main():
    request = json.loads(sys.argv[1])
    info = probe()
    if request.get("action") == "probe":
        return info
    expected_fields(request)
    if request["platform"] != info["platform"]:
        raise InstallError("probe", "Package architecture does not match working host")
    if request.get("action") == "inspect":
        return inspect(request)
    if request.get("action") == "install":
        return install(request, sys.stdin.buffer)
    raise InstallError("validate", "Unknown installer action")


if __name__ == "__main__":
    def interrupted(_signal, _frame):
        raise InstallError("upload", "Installation interrupted")
    for name in (signal.SIGHUP, signal.SIGTERM):
        signal.signal(name, interrupted)
    try:
        print(json.dumps({"ok": True, "result": main()}), flush=True)
    except Exception as error:
        print(json.dumps({"ok": False, "stage": getattr(error, "stage", "install"), "error": str(error)[:4096]}), flush=True)
        sys.exit(1)
