"""Exercise the built headless server using only Python's standard library."""
import http.client
import json
import os
from pathlib import Path
import signal
import socket
import struct
import subprocess
import sys
import tempfile
import time
from urllib.parse import urlsplit


def wait_until(check, message):
    deadline = time.monotonic() + 15
    while time.monotonic() < deadline:
        if check():
            return
        time.sleep(0.05)
    raise AssertionError(message)


class WebSocket:
    def __init__(self, url, headers, expected=101):
        target = urlsplit(url)
        self.socket = socket.create_connection((target.hostname, target.port), 5)
        self.stream = self.socket.makefile("rb")
        request = [
            f"GET {target.path} HTTP/1.1", f"Host: {target.netloc}",
            "Connection: Upgrade", "Upgrade: websocket",
            "Sec-WebSocket-Version: 13",
            "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==",
            *[f"{key}: {value}" for key, value in headers.items()], "", "",
        ]
        self.socket.sendall("\r\n".join(request).encode())
        status = int(self.stream.readline().split()[1])
        while self.stream.readline() not in (b"\r\n", b""):
            pass
        if status != expected:
            self.close()
            raise AssertionError(f"WebSocket status {status}, expected {expected}")
        self.sequence = 0

    def close(self):
        self.stream.close()
        self.socket.close()

    def send(self, payload):
        data = json.dumps(payload).encode()
        mask = os.urandom(4)
        header = bytes([0x81, 0x80 | len(data)]) if len(data) < 126 else (
            bytes([0x81, 0x80 | 126]) + struct.pack("!H", len(data))
        )
        self.socket.sendall(header + mask + bytes(
            byte ^ mask[index % 4] for index, byte in enumerate(data)
        ))

    def receive(self):
        header = self.stream.read(2)
        assert len(header) == 2, "socket closed before RPC reply"
        assert header[0] & 15 == 1, "expected a text message"
        size = header[1] & 127
        if size == 126:
            size = struct.unpack("!H", self.stream.read(2))[0]
        elif size == 127:
            size = struct.unpack("!Q", self.stream.read(8))[0]
        return json.loads(self.stream.read(size))

    def call(self, method, params):
        self.sequence += 1
        self.send({"jsonrpc": "2.0", "id": self.sequence,
                   "method": method, "params": params})
        while True:
            reply = self.receive()
            if reply.get("id") == self.sequence:
                assert "error" not in reply, reply
                return reply["result"]


def running(pid):
    try:
        os.kill(pid, 0)
        return True
    except ProcessLookupError:
        return False


def main():
    executable = str(Path(sys.argv[1]).resolve())
    with tempfile.TemporaryDirectory(prefix="seekmoon-server-smoke-") as temporary:
        root = Path(temporary).resolve()
        home = root / "home"
        home.mkdir()
        frontend = root / "frontend"
        frontend.mkdir()
        (frontend / "index.html").write_text('<script src="app.js"></script>')
        (frontend / "app.js").write_text("window.smoke = true;")
        workspace = root / "workspace"
        workspace.mkdir()
        subprocess.run(["git", "init", "--quiet", str(workspace)], check=True)
        env = {key: value for key, value in os.environ.items()
               if not key.startswith("OPENSEEK_")}
        env.setdefault("MOON_HOME", str(Path.home() / ".moon"))
        env.update(HOME=str(home), CODEX_HOME=str(home / ".codex"), SHELL="/bin/sh")
        ready_path = root / "ready.json"
        child_pid = None
        client = None
        with (root / "stdout").open("w+") as stdout, (root / "stderr").open("w+") as stderr:
            process = subprocess.Popen([
                executable, "--port", "0", "--runtime-dir", str(root / "runtime"),
                "--root", str(frontend), "--ready-file", str(ready_path),
            ], env=env, stdout=stdout, stderr=stderr, start_new_session=True)
            try:
                wait_until(lambda: ready_path.exists() or process.poll() is not None,
                           "server did not report readiness")
                assert ready_path.exists(), "server exited before readiness"
                ready = json.loads(ready_path.read_text())
                assert ready_path.stat().st_mode & 0o777 == 0o600
                target = urlsplit(ready["url"])
                cookie = f"seekmoon_session_{target.port}={ready['token']}"
                for headers, expected in [({}, 401), ({"Cookie": "wrong"}, 401),
                        ({"Cookie": cookie, "Origin": "https://unrelated.example"}, 401)]:
                    rejected = WebSocket(ready["url"], headers, expected)
                    rejected.close()
                page = urlsplit(ready["entry_url"])
                connection = http.client.HTTPConnection(page.hostname, page.port, timeout=5)
                connection.request("GET", page.path + "?" + page.query)
                response = connection.getresponse()
                assert response.status == 200
                assert cookie in response.getheader("Set-Cookie")
                assert b'app.js' in response.read()
                connection.close()
                connection = http.client.HTTPConnection(page.hostname, page.port, timeout=5)
                connection.request("GET", "/app.js", headers={"Cookie": cookie})
                response = connection.getresponse()
                assert response.status == 200
                assert response.read() == b"window.smoke = true;"
                connection.close()
                client = WebSocket(ready["url"], {"Cookie": cookie})
                client.call("app.language_set", {"language": "zh-Hans"})
                assert client.call("app.language_get", {}) == {"language": "zh-Hans"}
                client.call("workspace.add", {"path": str(workspace)})
                pid_file = workspace / "child.pid"
                client.call("terminal.open", {
                    "session": "server-smoke", "workspace": str(workspace),
                    "cols": 80, "rows": 24,
                    "command": "echo $$ > child.pid; exec sleep 120",
                })
                wait_until(pid_file.exists, "PTY child did not start")
                child_pid = int(pid_file.read_text())
                assert running(child_pid)
                process.send_signal(signal.SIGTERM)
                status = process.wait(timeout=15)
                # async unwinds its tasks, then re-raises the original signal.
                assert status == -signal.SIGTERM, f"unexpected exit: {status}"
                wait_until(lambda: not running(child_pid), "PTY child survived server termination")
                stdout.seek(0)
                lines = stdout.read().splitlines()
                assert len(lines) == 1 and json.loads(lines[0]) == ready
                print("Server smoke passed: auth, frontend assets, shared RPC, SIGTERM, PTY cleanup")
            except BaseException:
                stderr.seek(0)
                print(stderr.read(), file=sys.stderr)
                raise
            finally:
                if client:
                    client.close()
                if process.poll() is None:
                    process.terminate()
                    try:
                        process.wait(timeout=15)
                    except subprocess.TimeoutExpired:
                        os.killpg(process.pid, signal.SIGKILL)
                        process.wait()
                if child_pid and running(child_pid):
                    os.kill(child_pid, signal.SIGKILL)


if __name__ == "__main__":
    main()
