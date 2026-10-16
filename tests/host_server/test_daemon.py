"""Daemon ownership/recovery through real native and wasm launchers."""
import concurrent.futures
import json
import os
import platform
from pathlib import Path
import shlex
import shutil
import signal
import subprocess
import sys
import tempfile
import time
import unittest
from test_foreground import NATIVE, WASM, Peer, TARGETS


class DaemonFixture(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="host-daemon-", dir="/tmp")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        home = self.root / "home"
        home.mkdir()
        runtime = self.root / "runtime"
        runtime.mkdir(mode=0o700)
        self.env = dict(os.environ, HOME=str(home), PATH="/usr/bin:/bin:/usr/sbin:/sbin", XDG_RUNTIME_DIR=str(runtime))
        self.hosts = []
        self.addCleanup(self.stop_hosts)

    def configure(self, target):
        launcher = self.root / (target + "-launcher")
        command = [str(NATIVE)] if target == "native" else [shutil.which("moonrun"), str(WASM), "--"]
        launcher.write_text("#!/bin/sh\n" + "\n".join("export " + key + "=" + shlex.quote(value) for key, value in {
            "OPENSEEK_HOST_ENGINE": str(launcher), "OPENSEEK_HOST_BUILD_ID": "workspace",
        }.items()) + "\nexec " + shlex.join(command) + ' "$@"\n')
        launcher.chmod(0o700)
        data = self.root / (target + "-data")
        command = [str(launcher), "app-server", "daemon"]
        self.hosts.append((command, data))
        return command, data

    def invoke(self, host, action, *extra, ok=True):
        command, data = host
        result = subprocess.run([*command, action, "--data-dir", str(data), *extra], env=self.env, capture_output=True, timeout=25)
        if ok:
            self.assertEqual(result.returncode, 0, result.stderr.decode() + (data / "daemon.log").read_text() if (data / "daemon.log").exists() else result.stderr.decode())
            return json.loads(result.stdout)
        self.assertNotEqual(result.returncode, 0)
        return result

    def stop_hosts(self):
        for host in self.hosts:
            self.invoke(host, "stop", "--shutdown-grace-seconds", "0")

    def socket(self, data):
        return data / "endpoint.json"


class DaemonTests(DaemonFixture):
    def test_concurrent_start_ready_probe_and_restart_both_targets(self):
        for target in TARGETS:
            with self.subTest(target=target):
                host = self.configure(target)
                with concurrent.futures.ThreadPoolExecutor(max_workers=4) as workers:
                    replies = list(workers.map(lambda _: self.invoke(host, "start"), range(4)))
                self.assertEqual(len({r["instance_id"] for r in replies}), 1)
                self.assertEqual({r["status"] for r in replies}, {"ready"})
                first = replies[0]
                self.assertEqual(self.invoke(host, "status")["instance_id"], first["instance_id"])
                again = self.invoke(host, "restart", "--shutdown-grace-seconds", "0")
                self.assertNotEqual(again["instance_id"], first["instance_id"])
                self.assertEqual(again["server_id"], first["server_id"])
                stopped = self.invoke(host, "stop", "--shutdown-grace-seconds", "0")
                self.assertEqual(stopped["status"], "not_running")
                self.assertFalse(stopped["recovery_required"])
                self.assertFalse(self.socket(host[1]).exists())

    def test_upgrade_barrier_preserves_pending_login_then_drains_idle(self):
        tool_bin = self.root / "upgrade-tools"
        tool_bin.mkdir()
        (tool_bin / "moon").write_text("#!/bin/sh\nexit 0\n")
        (tool_bin / "moon").chmod(0o700)
        self.env["PATH"] = str(tool_bin) + ":" + self.env["PATH"]
        mock = self.root / "upgrade-codex"
        mock.write_text(f"#!{sys.executable}\n" + r'''import json, sys
for line in sys.stdin:
    request = json.loads(line)
    if "id" not in request:
        continue
    result = {"loginId": "pending", "authUrl": "https://example.test/login"} if request["method"] == "account/login/start" else {}
    print(json.dumps({"jsonrpc": "2.0", "id": request["id"], "result": result}), flush=True)
''')
        mock.chmod(0o700)
        for target in TARGETS:
            with self.subTest(target=target):
                host = self.configure(target)
                first = self.invoke(host, "start", "--codex-command", str(mock))
                peer = Peer(self.socket(host[1]))
                self.addCleanup(peer.close)
                peer.initialize()
                self.assertIn("result", peer.request("workspace.add", {"path": str(self.root)}))
                request = {"instance_id": first["instance_id"]}
                wrong = peer.request("server.prepare_upgrade", {"instance_id": "stale-owner"})
                self.assertIn("identity mismatch", json.dumps(wrong))
                self.assertEqual(self.invoke(host, "status")["status"], "ready")
                login = peer.request("codex.account.login.start", {"type": "chatgpt", "useHostedLoginSuccessPage": False, "appBrand": "codex"})
                self.assertEqual(login["result"]["loginId"], "pending")
                self.assertEqual(peer.request("server.prepare_upgrade", request)["result"]["status"], "busy")
                self.assertIn("result", peer.request("codex.account.login.cancel", {"loginId": "pending"}))
                deadline = time.monotonic() + 10
                while True:
                    reply = peer.request("server.prepare_upgrade", request)["result"]
                    if reply["status"] == "draining":
                        break
                    self.assertLess(time.monotonic(), deadline, "cancelled login did not settle")
                    time.sleep(0.02)
                peer.close()
                deadline = time.monotonic() + 10
                while self.socket(host[1]).exists() and time.monotonic() < deadline:
                    time.sleep(0.02)
                stopped = self.invoke(host, "status")
                self.assertEqual(stopped["status"], "not_running")
                self.assertFalse(stopped["recovery_required"])

    def test_upgrade_identity_pin_precedes_reuse_and_stopped_activation(self):
        for target in TARGETS:
            with self.subTest(target=target):
                host = self.configure(target)
                first = self.invoke(host, "start")
                wrong = self.invoke(host, "upgrade", "--expected-server-id", "different-server", ok=False)
                self.assertIn(b"server identity changed", wrong.stderr)
                self.assertEqual(self.invoke(host, "status")["instance_id"], first["instance_id"])
                same = self.invoke(host, "upgrade", "--expected-server-id", first["server_id"])
                self.assertEqual(same["instance_id"], first["instance_id"])
                self.invoke(host, "stop")
                wrong = self.invoke(host, "upgrade", "--expected-server-id", "different-server", ok=False)
                self.assertIn(b"server identity changed", wrong.stderr)
                self.assertEqual(self.invoke(host, "status")["status"], "not_running")
                restored = self.invoke(host, "upgrade", "--expected-server-id", first["server_id"])
                self.assertNotEqual(restored["instance_id"], first["instance_id"])
                self.assertEqual(restored["server_id"], first["server_id"])

    def upgrade_candidate(self, host, build="upgrade-target"):
        old = Path(host[0][0])
        launcher = self.root / (old.name + "-" + build)
        launcher.write_text(old.read_text().replace(str(old), str(launcher)).replace("OPENSEEK_HOST_BUILD_ID=workspace", "OPENSEEK_HOST_BUILD_ID=" + build))
        launcher.chmod(0o700)
        candidate = ([str(launcher), "app-server", "daemon"], host[1])
        # Cleanup must use the current build when the candidate owns the socket.
        self.hosts.remove(host)
        self.hosts.append(candidate)
        return candidate

    def test_upgrade_serializes_busy_barrier_and_preserves_explicit_codex(self):
        mock = self.root / "persistent Codex"
        mock.write_text(f"#!{sys.executable}\n" + r'''import json, sys
for line in sys.stdin:
    request = json.loads(line)
    if "id" not in request:
        continue
    result = {"loginId": "pending", "authUrl": "https://example.test/login"} if request["method"] == "account/login/start" else {"requiresOpenaiAuth": True} if request["method"] == "account/read" else {}
    print(json.dumps({"jsonrpc": "2.0", "id": request["id"], "result": result}), flush=True)
''')
        mock.chmod(0o700)
        for target in TARGETS:
            with self.subTest(target=target):
                old = self.configure(target)
                first = self.invoke(old, "start", "--codex-command", str(mock))
                candidate = self.upgrade_candidate(old)
                # Until activation, cleanup must still be able to stop the old owner.
                self.hosts.remove(candidate)
                self.hosts.append(old)
                sentinel = old[1] / "preserved-data"
                sentinel.write_text("existing state")
                peer = Peer(self.socket(old[1]))
                self.addCleanup(peer.close)
                peer.initialize()
                self.assertIn("result", peer.request("codex.account.login.start", {"type": "chatgpt", "useHostedLoginSuccessPage": False, "appBrand": "codex"}))
                busy = self.invoke(candidate, "upgrade")
                self.assertEqual(busy["status"], "busy")
                self.assertEqual(busy["instance_id"], first["instance_id"])
                self.assertEqual(json.loads(Path(busy["upgrade_record"]).read_text())["phase"], "busy")
                self.assertEqual(self.invoke(old, "status")["status"], "ready")
                self.assertIn("result", peer.request("codex.account.login.cancel", {"loginId": "pending"}))
                peer.close()
                self.hosts.remove(old)
                self.hosts.append(candidate)
                with concurrent.futures.ThreadPoolExecutor(max_workers=2) as workers:
                    results = list(workers.map(lambda _: self.invoke(candidate, "upgrade"), range(2)))
                self.assertEqual({r["status"] for r in results}, {"ready"})
                self.assertEqual(len({r["instance_id"] for r in results}), 1)
                self.assertNotEqual(results[0]["instance_id"], first["instance_id"])
                self.assertEqual(results[0]["server_id"], first["server_id"])
                self.assertEqual(sentinel.read_text(), "existing state")
                launch = json.loads((old[1] / "launch.json").read_text())
                self.assertEqual(launch["codex_command"], str(mock))
                self.assertEqual(launch["build_id"], "upgrade-target")
                records = [json.loads(p.read_text()) for p in (old[1] / "upgrades").glob("*.json")]
                self.assertEqual(sorted(r["phase"] for r in records), ["busy", "ready"])
                self.assertTrue(all(r["migration"] == "none" and not r["automatic_rollback"] for r in records))
                peer = Peer(self.socket(old[1]))
                self.addCleanup(peer.close)
                self.assertIn("result", peer.request("server.initialize", {"build_id": "upgrade-target", "protocol_version": 1}))
                self.assertEqual(peer.request("codex.account.read", {"refreshToken": False})["result"]["requiresOpenaiAuth"], True)
                peer.close()

    def test_upgrade_rejects_schema_and_intent_errors_before_stop_and_records_failed_launch(self):
        for target in TARGETS:
            with self.subTest(target=target):
                old = self.configure(target)
                first = self.invoke(old, "start")
                candidate = self.upgrade_candidate(old)
                self.hosts.remove(candidate)
                self.hosts.append(old)
                owner_path = old[1] / "owner.json"
                valid_owner = owner_path.read_bytes()
                malformed_owner = json.loads(valid_owner)
                malformed_owner.pop("instance_id")
                owner_path.write_text(json.dumps(malformed_owner))
                bad_owner = self.invoke(candidate, "upgrade", ok=False)
                self.assertIn(b"cannot verify old owner identity", bad_owner.stderr)
                self.assertEqual(self.invoke(old, "status")["instance_id"], first["instance_id"])
                owner_path.write_bytes(valid_owner)
                schema = old[1] / "data-schema.json"
                schema.write_text('{"version":2}')
                rejected = self.invoke(candidate, "upgrade", ok=False)
                self.assertIn(b"unsupported working-host data schema", rejected.stderr)
                self.assertEqual(self.invoke(old, "status")["instance_id"], first["instance_id"])
                self.assertEqual(schema.read_text(), '{"version":2}')
                schema.write_text('{"version":1}')
                launch = old[1] / "launch.json"
                saved = launch.read_bytes()
                launch.unlink()
                legacy = self.invoke(candidate, "upgrade", ok=False)
                self.assertIn(b"no matching launch record", legacy.stderr)
                self.assertEqual(self.invoke(old, "status")["instance_id"], first["instance_id"])
                malformed = json.loads(saved)
                malformed["codex_command"] = 7
                launch.write_text(json.dumps(malformed))
                corrupt = self.invoke(candidate, "upgrade", ok=False)
                self.assertIn(b"invalid saved Codex executable", corrupt.stderr)
                self.assertEqual(self.invoke(old, "status")["instance_id"], first["instance_id"])
                launch.write_bytes(saved)
                records = old[1] / "upgrades"
                records.write_text("do not overwrite")
                self.invoke(candidate, "upgrade", ok=False)
                self.assertEqual(records.read_text(), "do not overwrite")
                self.assertEqual(self.invoke(old, "status")["instance_id"], first["instance_id"])
                records.unlink()
                outside = self.root / (target + "-unrelated-records")
                outside.mkdir()
                (outside / "note").write_text("preserve")
                records.symlink_to(outside, target_is_directory=True)
                self.invoke(candidate, "upgrade", ok=False)
                self.assertEqual(list(p.name for p in outside.iterdir()), ["note"])
                self.assertEqual(self.invoke(old, "status")["instance_id"], first["instance_id"])
                records.unlink()
                broken = self.root / (target + "-unstartable-engine")
                broken.write_text("#!/bin/sh\nexit 1\n")
                broken.chmod(0o700)
                failure = self.invoke(candidate, "upgrade", "--engine", str(broken), ok=False)
                self.assertIn(b"inspect", failure.stderr)
                attempts = [json.loads(p.read_text()) for p in records.glob("*.json")]
                self.assertEqual(len(attempts), 1)
                self.assertEqual(attempts[0]["phase"], "failed")
                self.assertEqual(attempts[0]["detail"]["last_phase"], "starting")
                self.assertEqual(attempts[0]["previous_launch"]["engine"], str(Path(old[0][0]).resolve()))
                self.assertEqual(self.invoke(old, "status")["status"], "not_running")
                # The controller does not restart an old binary on its own.
                # An explicit same-schema activation can restore that selected build.
                restored = self.invoke(old, "upgrade")
                self.assertEqual(restored["status"], "ready")
                self.assertEqual(restored["server_id"], first["server_id"])
                self.assertEqual(json.loads(schema.read_text()), {"version": 1})

    def test_explicit_codex_path_survives_detach_and_restart(self):
        selected = self.root / "chosen Codex executable"
        selected.write_text(f"#!{sys.executable}\n" + r'''import json, os, sys
from pathlib import Path
home = Path(os.environ["CODEX_HOME"])
with (home / "selected-executable.jsonl").open("a") as log:
    log.write(json.dumps({"command": sys.argv[0], "home": str(home)}) + "\n")
for line in sys.stdin:
    request = json.loads(line)
    if "id" not in request:
        continue
    result = {"account": None, "requiresOpenaiAuth": True} if request["method"] == "account/read" else {}
    print(json.dumps({"jsonrpc": "2.0", "id": request["id"], "result": result}), flush=True)
''')
        selected.chmod(0o700)
        for target in TARGETS:
            with self.subTest(target=target):
                host = self.configure(target)
                # This path is outside PATH and deliberately contains spaces.
                first = self.invoke(host, "start", "--codex-command", str(selected))
                peer = Peer(self.socket(host[1]))
                peer.initialize()
                self.assertEqual(peer.request("codex.account.read", {"refreshToken": False})["result"],
                                 {"requiresOpenaiAuth": True})
                peer.close()
                launches = host[1] / "codex/selected-executable.jsonl"
                entries = [json.loads(line) for line in launches.read_text().splitlines()]
                self.assertEqual(entries, [{"command": str(selected), "home": str((host[1] / "codex").resolve())}])
                invalid = self.invoke(host, "restart", "--codex-command", "relative-codex", ok=False)
                self.assertIn(b"must be an absolute", invalid.stderr)
                self.assertEqual(self.invoke(host, "status")["instance_id"], first["instance_id"])
                self.env["OPENSEEK_HOST_CODEX_COMMAND"] = str(selected)
                try:
                    again = self.invoke(host, "restart", "--shutdown-grace-seconds", "0")
                    self.assertNotEqual(again["instance_id"], first["instance_id"])
                    peer = Peer(self.socket(host[1]))
                    peer.initialize()
                    self.assertIn("requiresOpenaiAuth", peer.request("codex.account.read", {"refreshToken": False})["result"])
                    peer.close()
                finally:
                    self.env.pop("OPENSEEK_HOST_CODEX_COMMAND")
                self.assertEqual(len(launches.read_text().splitlines()), 2)

    def test_missing_explicit_codex_does_not_fall_back_or_block_host(self):
        bin_dir = self.root / "bin"
        bin_dir.mkdir()
        marker = self.root / "wrong-codex"
        fallback = bin_dir / "codex"
        fallback.write_text("#!/bin/sh\ntouch " + shlex.quote(str(marker)) + "\nexit 1\n")
        fallback.chmod(0o700)
        self.env["PATH"] = str(bin_dir) + ":" + self.env["PATH"]
        for target in TARGETS:
            with self.subTest(target=target):
                host = self.configure(target)
                missing = self.root / "missing Codex"
                self.assertEqual(self.invoke(host, "start", "--codex-command", str(missing))["status"], "ready")
                peer = Peer(self.socket(host[1]))
                peer.initialize()
                response = peer.request("codex.account.read", {"refreshToken": False})
                self.assertIn(str(missing), json.dumps(response))
                self.assertFalse(marker.exists())
                self.assertIn("result", peer.request("workspace.list", {}))
                peer.close()

    def test_explicit_moonbit_seed_survives_detach_and_rejects_invalid_restart(self):
        host_platform = platform.system() + "-" + platform.machine()
        seed_platform = {"Linux-x86_64": "linux-x64", "Linux-aarch64": "linux-arm64", "Darwin-arm64": "macos-arm64"}[host_platform]
        seed = self.root / "explicit seed with spaces"
        (seed / "bin").mkdir(parents=True)
        (seed / "lib/core").mkdir(parents=True)
        (seed / ".openseek-moonbit-seed-version").write_text("test-seed-v1")
        (seed / "bin/moonc").write_text("compiler fixture")
        moon = seed / "bin/moon"
        moon.write_text(f"#!{sys.executable}\n" + r'''import json, os, sys
from pathlib import Path
root = Path(__file__).resolve().parent.parent
with (root / "calls.jsonl").open("a") as log:
    log.write(json.dumps({"argv": sys.argv[1:], "executable": str(Path(__file__).resolve()), "moon_home": os.environ.get("MOON_HOME")}) + "\n")
if sys.argv[1] == "bundle":
    for target in ("native", "wasm-gc"):
        probe = root / ("lib/core/_build/" + target + "/release/bundle/prelude/prelude.mi")
        probe.parent.mkdir(parents=True, exist_ok=True)
        probe.touch()
else:
    print("{}")
''')
        moon.chmod(0o755)
        self.env["MOON_HOME"] = str(self.root / "registry identity")
        for target in TARGETS:
            with self.subTest(target=target):
                host = self.configure(target)
                first = self.invoke(host, "start", "--moonbit-platform", seed_platform, "--moonbit-seed-dir", str(seed))
                workspace = self.root / (target + "-moon-project")
                workspace.mkdir()
                (workspace / "moon.mod.json").write_text('{"name":"fixture/project","version":"0.0.0"}')
                (workspace / "moon.pkg.json").write_text('{}')
                (workspace / "main.mbt").write_text('fn main {}')
                peer = Peer(self.socket(host[1]))
                self.addCleanup(peer.close)
                peer.initialize()
                self.assertIn("result", peer.request("workspace.add", {"path": str(workspace)}))
                self.assertIn("result", peer.request("lsp.hover", {"session":"seed-test", "root": str(workspace), "path":"main.mbt", "line":0, "character":0}))
                payload = host[1] / "toolchains/moonbit" / seed_platform
                entries = [json.loads(line) for line in (payload / "calls.jsonl").read_text().splitlines()]
                self.assertEqual([e["argv"][0] for e in entries], ["bundle", "bundle", "ide"])
                self.assertTrue(all(e["executable"] == str((payload / "bin/moon").resolve()) for e in entries))
                self.assertTrue(all(e["moon_home"] == self.env["MOON_HOME"] for e in entries))
                # Old prepared desktop payloads may lack the installer alias.
                (payload / "bin/moonx").unlink()
                search = peer.request("fs.search_semantic", {
                    "root": str(workspace), "patterns": ["answer"], "include_glob": "", "exclude_glob": "",
                    "session_key": "seed-search", "generation": 1, "max_results": 10,
                })
                self.assertIn("result", search)
                self.assertNotIn("error", search["result"])
                entries = [json.loads(line) for line in (payload / "calls.jsonl").read_text().splitlines()]
                self.assertEqual(entries[-1]["executable"], str((payload / "bin/moonx").resolve()))
                self.assertEqual(entries[-1]["argv"][:3], ["moonbit-community/moongrep@0.3.5", "--", "scan"])
                self.assertEqual(entries[-1]["moon_home"], self.env["MOON_HOME"])
                self.assertFalse((seed / "calls.jsonl").exists())
                for extra in [
                    ["--moonbit-platform", seed_platform],
                    ["--moonbit-platform", "unsupported", "--moonbit-seed-dir", str(seed)],
                    ["--moonbit-platform", "linux-arm64" if seed_platform != "linux-arm64" else "linux-x64", "--moonbit-seed-dir", str(seed)],
                    ["--moonbit-platform", seed_platform, "--moonbit-seed-dir", "relative"],
                    ["--moonbit-platform", seed_platform, "--moonbit-seed-dir", str(self.root / "missing seed")],
                    ["--viz-dir", "relative"],
                ]:
                    self.invoke(host, "restart", *extra, ok=False)
                    self.assertEqual(self.invoke(host, "status")["instance_id"], first["instance_id"])
                peer.close()

    def test_export_assets_survive_detach_and_oversize_keeps_connection(self):
        for target in TARGETS:
            with self.subTest(target=target):
                host = self.configure(target)
                assets = self.root / (target + "-viz assets")
                assets.mkdir()
                (assets / "index.html").write_text('<html><script src="/viz_app.js"></script></html>')
                (assets / "viz_app.js").write_text('window.fixtureBuild = "export-demo";')
                self.invoke(host, "start", "--viz-dir", str(assets))
                peer = Peer(self.socket(host[1]))
                self.addCleanup(peer.close)
                peer.initialize()
                workspace = self.root / (target + "-workspace")
                workspace.mkdir()
                self.assertIn("result", peer.request("workspace.add", {"path": str(workspace)}))
                record = workspace / ".openseek/sessions/export-demo/openseek_session-export-demo.jsonl"
                record.parent.mkdir(parents=True)
                record.write_text('{"version":1,"id":"export-demo","system_prompt":"remote marker"}\n')
                source = {"workspace": str(workspace), "session": "export-demo", "title": "Demo", "archived": False}
                response = peer.request("session.export_content", source)
                self.assertIn("result", response)
                content = response["result"]
                self.assertIn("remote marker", content["json"])
                self.assertIn('window.fixtureBuild = "export-demo"', content["html"])
                record.write_bytes(b"x" * (4 * 1024 * 1024 + 1))
                oversized = peer.request("session.export_content", source)
                self.assertIn("size limit", oversized["error"]["message"])
                self.assertIn("result", peer.request("agent.runs", {}))

    def test_intent_write_failure_prevents_workspace_effect(self):
        for target in TARGETS:
            with self.subTest(target=target):
                host = self.configure(target)
                identity = self.invoke(host, "start")
                directory = host[1] / "recovery" / identity["instance_id"]
                saved = directory.with_name(directory.name + ".saved")
                directory.rename(saved)
                directory.write_text("not a directory")
                peer = Peer(self.socket(host[1]))
                self.addCleanup(peer.close)
                peer.initialize()
                destination = self.root / (target + "-must-not-exist")
                try:
                    response = peer.request("fs.create_directory", {"parent": str(destination.parent), "name": destination.name})
                    self.assertIn("error", response)
                    self.assertFalse(destination.exists())
                finally:
                    directory.unlink()
                    saved.rename(directory)
                self.assertIn("result", peer.request("fs.create_directory", {"parent": str(destination.parent), "name": destination.name}))
                self.assertTrue(destination.is_dir())

    def test_sigkill_recovery_persists_across_restart_and_requires_acknowledgement(self):
        for target in TARGETS:
            with self.subTest(target=target):
                host = self.configure(target)
                original = self.invoke(host, "start")
                data = host[1]
                peer = Peer(self.socket(data))
                self.addCleanup(peer.close)
                peer.initialize()
                workspace = self.root / (target + "-workspace")
                workspace.mkdir()
                response = peer.request("workspace.add", {"path": str(workspace)})
                self.assertIn("result", response)
                records = list((data / "recovery" / original["instance_id"]).glob("*.intent.json"))
                self.assertTrue(any(json.loads(path.read_text())["kind"] == "workspace.add" for path in records))
                owner = json.loads((data / "daemon-process.json").read_text())
                os.kill(owner["pid"], signal.SIGKILL)
                deadline = time.monotonic() + 5
                # SIGKILL delivery is asynchronous, and the crashed process
                # leaves endpoint.json behind. Wait for released ownership.
                while True:
                    stopped = subprocess.run([*host[0], "status", "--data-dir", str(data)],
                                             env=self.env, capture_output=True, timeout=15)
                    if stopped.returncode == 0 and json.loads(stopped.stdout)["status"] == "not_running":
                        break
                    self.assertLess(time.monotonic(), deadline, stopped.stderr.decode())
                    time.sleep(0.02)
                recovered = self.invoke(host, "start")
                self.assertEqual(recovered["status"], "recovery_required")
                peer.close()
                peer = Peer(self.socket(data))
                self.addCleanup(peer.close)
                peer.initialize()
                self.assertIn("error", peer.request("workspace.add", {"path": str(workspace)}))
                report = peer.request("server.recovery", {})["result"]
                self.assertIn(original["instance_id"], {i["instance_id"] for i in report["unsettled_instances"]})
                self.assertEqual(self.invoke(host, "restart", "--shutdown-grace-seconds", "0")["status"], "recovery_required")
                self.invoke(host, "recover", "--acknowledge-instance", original["instance_id"], ok=False)
                self.invoke(host, "recover", "--acknowledge-instance", original["instance_id"], "--confirm-external-tools-stopped")
                self.assertEqual(self.invoke(host, "restart", "--shutdown-grace-seconds", "0")["status"], "ready")


if __name__ == "__main__":
    unittest.main()
