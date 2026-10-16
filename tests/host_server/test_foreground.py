"""Actual native/wasm CLI with an independent RFC6455 wire peer."""
import base64
import hashlib
import json
import os
from pathlib import Path
import select
import shutil
import signal
import socket
import struct
import sys
import subprocess
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[2]
NATIVE = ROOT / "_build/native/debug/build/moonbitlang/openseek/openseek.exe"
TARGETS = os.environ.get("OPENSEEK_HOST_TEST_TARGETS", "native,wasm").split(",")
WASM = ROOT / "_build/wasm/debug/build/moonbitlang/openseek/openseek.wasm"


class Peer:
    def __init__(self, path):
        endpoint = json.loads(Path(path).read_text())
        self.socket = socket.socket(socket.AF_INET)
        self.socket.settimeout(10)
        try:
            self.socket.connect(("127.0.0.1", endpoint["port"]))
        except OSError:
            self.socket.close()
            raise
        key = base64.b64encode(os.urandom(16)).decode()
        self.socket.sendall((f"GET /host HTTP/1.1\r\nHost: working-host\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Version: 13\r\nSec-WebSocket-Key: {key}\r\n\r\n").encode())
        header = bytearray()
        while not header.endswith(b"\r\n\r\n"):
            header += self.exact(1)
        accept = base64.b64encode(hashlib.sha1((key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").encode()).digest())
        if not header.startswith(b"HTTP/1.1 101") or accept not in header:
            raise AssertionError(f"invalid upgrade: {header!r}")
        self.next_id = 0

    def exact(self, size):
        result = bytearray()
        while len(result) < size:
            chunk = self.socket.recv(size - len(result))
            if not chunk:
                raise EOFError("WebSocket closed")
            result += chunk
        return bytes(result)

    def send(self, payload, opcode=1):
        mask = os.urandom(4)
        size = len(payload)
        if size < 126:
            header = bytes([0x80 | opcode, 0x80 | size])
        elif size < 65536:
            header = bytes([0x80 | opcode, 0x80 | 126]) + struct.pack("!H", size)
        else:
            header = bytes([0x80 | opcode, 0x80 | 127]) + struct.pack("!Q", size)
        self.socket.sendall(header + mask + bytes(byte ^ mask[i % 4] for i, byte in enumerate(payload)))

    def receive(self):
        payload = bytearray()
        while True:
            a, b = self.exact(2)
            size = b & 127
            if size == 126:
                size = struct.unpack("!H", self.exact(2))[0]
            elif size == 127:
                size = struct.unpack("!Q", self.exact(8))[0]
            if b & 128:
                raise AssertionError("server frame was masked")
            body = self.exact(size)
            opcode = a & 15
            if opcode == 8:
                raise EOFError("WebSocket close frame")
            if opcode == 9:
                self.send(body, 10)
                continue
            if opcode == 10:
                continue
            payload += body
            if a & 128:
                return json.loads(payload)

    def request(self, method, params):
        self.next_id += 1
        ident = self.next_id
        self.send(json.dumps({"jsonrpc": "2.0", "id": ident, "method": method, "params": params}).encode())
        while True:
            response = self.receive()
            if response.get("id") == ident:
                return response

    def initialize(self):
        response = self.request("server.initialize", {"build_id": "workspace", "protocol_version": 1})
        return response["result"]

    def close(self):
        self.socket.close()


class ForegroundTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="host-server-", dir="/tmp")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.home = self.root / "home"
        self.home.mkdir()
        self.env = dict(os.environ, HOME=str(self.home), PATH="/usr/bin:/bin:/usr/sbin:/sbin")
        self.processes = []
        self.addCleanup(self.cleanup_processes)

    def cleanup_processes(self):
        for p in self.processes:
            if p.poll() is None:
                p.terminate()
                try:
                    p.wait(timeout=15)
                except subprocess.TimeoutExpired:
                    p.kill()
                    p.wait()
            p.stdin.close()
            p.stdout.close()
            p.stderr.close()

    def start(self, target, suffix="", data=None):
        command = [str(NATIVE)] if target == "native" else [shutil.which("moonrun"), str(WASM), "--"]
        data = data or self.root / ("data" + suffix)
        path = data / "endpoint.json"
        p = subprocess.Popen([*command, "app-server", "--listen", "127.0.0.1:0", "--data-dir", str(data),
                              "--engine", str(NATIVE), "--build-id", "workspace"],
                             env=self.env, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                             stderr=subprocess.PIPE, bufsize=0)
        self.processes.append(p)
        return p, path, data

    def ready(self, p, path):
        deadline = time.monotonic() + 15
        while time.monotonic() < deadline:
            if p.poll() is not None:
                self.fail(f"foreground exited {p.returncode}: {p.stderr.read().decode()}")
            try:
                peer = Peer(path)
                self.addCleanup(peer.close)
                return peer, peer.initialize()
            except (FileNotFoundError, ConnectionRefusedError):
                time.sleep(0.02)
        self.fail("foreground initialize deadline")

    def test_loopback_needs_no_token_and_rejects_browser_origin(self):
        for target in TARGETS:
            with self.subTest(target=target):
                p, path, data = self.start(target, suffix=target)
                peer, identity = self.ready(p, path)
                endpoint = json.loads(path.read_text())
                self.assertEqual(path.stat().st_mode & 0o777, 0o600)
                self.assertEqual(data.stat().st_mode & 0o777, 0o700)
                self.assertNotIn("token", endpoint)
                for request_path, extra in [("/host", "Origin: https://example.test\r\n"), ("/unknown", "")]:
                    with self.subTest(path=request_path, headers=extra):
                        with socket.create_connection(("127.0.0.1", endpoint["port"]), timeout=3) as client:
                            key = base64.b64encode(os.urandom(16)).decode()
                            client.sendall((f"GET {request_path} HTTP/1.1\r\nHost: working-host\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Version: 13\r\nSec-WebSocket-Key: " + key + "\r\n" + extra + "\r\n").encode())
                            try:
                                response = client.recv(4096)
                            except ConnectionResetError:
                                response = b""
                            self.assertEqual(response, b"", "rejected Upgrade must close without accepting")
                self.assertEqual(peer.request("server.status", {})["result"]["instance_id"], identity["instance_id"])

    def test_incomplete_upgrade_times_out_without_closing_other_connections(self):
        for target in TARGETS:
            with self.subTest(target=target):
                p, path, _ = self.start(target, suffix=target)
                peer, identity = self.ready(p, path)
                endpoint = json.loads(path.read_text())
                with socket.create_connection(("127.0.0.1", endpoint["port"]), timeout=15) as client:
                    began = time.monotonic()
                    client.sendall(b"GET /host HTTP/1.1\r\nHost: ")
                    self.assertEqual(peer.request("server.status", {})["result"]["instance_id"], identity["instance_id"])
                    self.assertEqual(client.recv(4096), b"")
                    self.assertGreaterEqual(time.monotonic() - began, 9)
                self.assertEqual(peer.request("server.status", {})["result"]["instance_id"], identity["instance_id"])

    def test_non_loopback_bind_is_rejected(self):
        result = subprocess.run([str(NATIVE), "app-server", "--listen", "0.0.0.0:0",
                                 "--data-dir", str(self.root / "data"), "--engine", str(NATIVE),
                                 "--build-id", "workspace"], env=self.env, capture_output=True, timeout=10)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(b"must listen on 127.0.0.1", result.stderr)

    def test_connection_owned_login_cancels_on_disconnect_even_after_a_late_reply(self):
        bin_dir = self.root / "bin"
        bin_dir.mkdir()
        mock = bin_dir / "codex"
        mock.write_text(f"#!{sys.executable}\n" + r'''import json, os, sys, time
from pathlib import Path
home = Path(os.environ["CODEX_HOME"])
if sys.argv[1:] == ["login", "--help"]:
    print("login --device-auth")
    sys.exit(0)
count = 0
for line in sys.stdin:
    request = json.loads(line)
    if "id" not in request:
        continue
    method = request["method"]
    result = {}
    if method == "account/login/start":
        count += 1
        (home / ("started-" + str(count))).write_text("started")
        if count == 2:
            deadline = time.monotonic() + 10
            while not (home / "release").exists() and time.monotonic() < deadline:
                time.sleep(0.01)
        result = {"loginId": "login-" + str(count), "authUrl": "https://example.test/login"}
    elif method == "account/login/cancel":
        with (home / "cancelled").open("a") as log:
            log.write(request["params"]["loginId"] + "\n")
        result = {"status": "canceled"}
    print(json.dumps({"jsonrpc": "2.0", "id": request["id"], "result": result}), flush=True)
''')
        mock.chmod(0o700)
        self.env["PATH"] = str(bin_dir) + ":" + self.env["PATH"]

        def wait_for(predicate):
            deadline = time.monotonic() + 10
            while time.monotonic() < deadline:
                if predicate():
                    return
                time.sleep(0.01)
            self.fail("Codex login lifecycle observation deadline")

        payload = {"type": "chatgpt", "useHostedLoginSuccessPage": False, "appBrand": "codex"}
        for target in TARGETS:
            with self.subTest(target=target):
                p, path, data = self.start(target, "login-" + target)
                first, _ = self.ready(p, path)
                second = Peer(path)
                self.addCleanup(second.close)
                second.initialize()
                config = first.request("codex.config.prepare", {})
                expected_config = data.resolve() / "codex" / "config.toml"
                self.assertEqual(config["result"], {
                    "path": str(expected_config),
                    "terminal_login": {
                        "kind": "ready",
                        "command": f"CODEX_HOME='{expected_config.parent}' '{mock}' login --device-auth",
                        "device_auth": True,
                    },
                })
                expected_config.write_text('model = "qa-preserved"\n')
                self.assertEqual(second.request("codex.config.prepare", {})["result"], config["result"])
                self.assertEqual(expected_config.read_text(), 'model = "qa-preserved"\n')
                self.assertEqual(expected_config.stat().st_mode & 0o777, 0o600)
                result = first.request("codex.account.login.start", payload)
                self.assertIn("result", result)
                self.assertEqual(result["result"]["loginId"], "login-1")
                denied = second.request("codex.account.login.cancel", {"loginId": "login-1"})
                self.assertIn("not owned", json.dumps(denied))
                home = data / "codex"
                cancelled = home / "cancelled"
                self.assertFalse(cancelled.exists())
                first.close()
                wait_for(lambda: cancelled.exists())
                self.assertEqual(cancelled.read_text().splitlines(), ["login-1"])
                second.send(json.dumps({"jsonrpc": "2.0", "id": 1000,
                                        "method": "codex.account.login.start", "params": payload}).encode())
                wait_for(lambda: (home / "started-2").exists())
                second.close()
                # Closing the socket precedes releasing the blocked start;
                # cleanup must also work when admission delivers the ID late.
                (home / "release").write_text("release")
                wait_for(lambda: len(cancelled.read_text().splitlines()) == 2)
                self.assertEqual(cancelled.read_text().splitlines(), ["login-1", "login-2"])
                remaining = Peer(path)
                self.addCleanup(remaining.close)
                remaining.initialize()
                self.assertIn("result", remaining.request("agent.runs", {}))
                remaining.request("server.shutdown", {"grace_seconds": 0})
                p.wait(timeout=10)
                self.assertEqual(p.returncode, 0)

    def test_native_and_wasm_file_shutdown_identity_and_owner_lock(self):
        for target in TARGETS:
            with self.subTest(target=target):
                p, path, data = self.start(target, target)
                peer, first = self.ready(p, path)
                self.assertEqual(first["status"], "ready")
                self.assertEqual(first["data_dir"], str(data.resolve()))
                self.assertEqual(first["home"], str(self.home.resolve()))
                fixture = self.root / "unicode.txt"
                fixture.write_text("working-host\n工作机")
                reply = peer.request("fs.read_file", {"path": str(fixture)})
                self.assertEqual(reply["result"]["content"], fixture.read_text())
                self.assertEqual(peer.request("fs.read_file", {"path": 7})["error"]["code"], -32602)
                self.assertEqual(peer.request("auth.connect", {})["error"]["code"], -32601)
                conflicting, _, _ = self.start(target, target + "conflict", data)
                self.assertNotEqual(conflicting.wait(timeout=10), 0)
                self.assertIn(b"already owns", conflicting.stderr.read())
                self.assertEqual(peer.request("server.status", {})["result"]["instance_id"], first["instance_id"])
                self.assertEqual(peer.request("server.shutdown", {"shutdown_grace_seconds": 0})["result"]["status"], "draining")
                self.assertEqual(p.wait(timeout=12), 0)
                self.assertFalse(path.exists())
                restarted, new_path, _ = self.start(target, target + "again", data)
                again, second = self.ready(restarted, new_path)
                self.assertEqual(second["server_id"], first["server_id"])
                self.assertNotEqual(second["instance_id"], first["instance_id"])
                again.request("server.shutdown", {"shutdown_grace_seconds": 0})
                self.assertEqual(restarted.wait(timeout=12), 0)
                self.assertEqual(p.stdout.read(), b"")

    def test_sigterm_joins_service_and_removes_listener_on_both_targets(self):
        for target in TARGETS:
            with self.subTest(target=target):
                p, path, _ = self.start(target, target)
                self.ready(p, path)
                p.send_signal(signal.SIGTERM)
                p.wait(timeout=12)
                self.assertFalse(path.exists())


if __name__ == "__main__":
    unittest.main()
