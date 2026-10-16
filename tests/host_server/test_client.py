"""Native HostClient against real local service, using an inspectable SSH stand-in."""
import json
import base64
import os
import re
import select
import shlex
import signal
import subprocess
import sys
import time
import unittest
from test_daemon import DaemonFixture
from test_foreground import NATIVE
from pathlib import Path


def remote_payload(command):
    # Inspect the encoded carrier without executing its payload.
    match = re.search(r"`printf %s ([A-Za-z0-9+/=]+) \| /usr/bin/base64 -d`", command)
    assert match, command
    words = shlex.split(base64.b64decode(match.group(1), validate=True).decode("utf8"))
    assert len(words) == 5 and words[:2] == ["/bin/sh", "-c"] and words[3] == "sh", words
    return base64.b64decode(words[4], validate=True).decode("utf8")


class JsonlClient:
    def __init__(self, command, env):
        self.process = subprocess.Popen(command, env=env, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, bufsize=0)
        self.events = []
        self.sequence = 0
        self.buffer = bytearray()

    def send(self, method, params):
        self.sequence += 1
        self.process.stdin.write((json.dumps({"jsonrpc": "2.0", "id": self.sequence, "method": method, "params": params}) + "\n").encode())
        return self.sequence

    def read(self, timeout=20):
        deadline = time.monotonic() + timeout
        while b"\n" not in self.buffer:
            if not select.select([self.process.stdout], [], [], max(0, deadline - time.monotonic()))[0]:
                raise TimeoutError("native client output deadline")
            data = os.read(self.process.stdout.fileno(), 65536)
            if not data:
                raise EOFError(self.process.stderr.read().decode())
            self.buffer += data
        line, _, rest = self.buffer.partition(b"\n")
        self.buffer = bytearray(rest)
        return json.loads(line)

    def response(self, ident, timeout=20):
        deadline = time.monotonic() + timeout
        while True:
            value = self.read(max(0, deadline - time.monotonic()))
            if value.get("id") == ident:
                return value
            self.events.append(value)

    def request(self, method, params, timeout=20):
        reply = self.response(self.send(method, params), timeout)
        if "error" in reply:
            raise AssertionError(reply)
        return reply["result"]

    def close(self):
        self.process.stdin.close()
        try:
            self.process.wait(timeout=10)
        except subprocess.TimeoutExpired:
            self.process.kill()
            self.process.wait()
        self.process.stdout.close()
        self.process.stderr.close()


class ReconnectingClient(JsonlClient):
    def __init__(self, command, env):
        super().__init__([*command, "--reconnect", "--host-id", "ssh_test"], env)
        self.epoch = None

    def wait_connection(self, kind="connected", timeout=20):
        deadline = time.monotonic() + timeout
        while True:
            value = self.read(max(0, deadline - time.monotonic()))
            self.events.append(value)
            if value.get("method") == "host.connection" and value["params"]["kind"] == kind:
                event = value["params"]
                if kind == "connected":
                    self.epoch = event["epoch"]
                return event

    def send(self, method, params):
        self.sequence += 1
        self.process.stdin.write((json.dumps({"id": self.sequence, "epoch": self.epoch,
                                             "method": method, "params": params}) + "\n").encode())
        return self.sequence


class HostClientTests(DaemonFixture):
    def setUp(self):
        super().setUp()
        self.env["SHELL"] = "/bin/sh"
        self.host = self.configure("native")
        self.host = (self.host[0], self.root / "data with quote' and $dollar\n中文")
        self.hosts[-1] = self.host
        self.log = self.root / "ssh-argv.jsonl"
        self.ssh = self.root / "ssh-test"
        forwarder = r"""
import socket, select, threading
if '-N' in sys.argv:
    local_host, local_port, remote_host, remote_port = sys.argv[sys.argv.index('-L') + 1].split(':')
    listener = socket.socket()
    listener.bind((local_host, int(local_port)))
    listener.listen()
    def relay(client):
        remote = socket.create_connection((remote_host, int(remote_port)))
        try:
            while True:
                for source in select.select([client, remote], [], [])[0]:
                    data = source.recv(65536)
                    if not data:
                        return
                    (remote if source is client else client).sendall(data)
        finally:
            client.close()
            remote.close()
    while True:
        client, _ = listener.accept()
        threading.Thread(target=relay, args=(client,), daemon=True).start()
os.write(1, b'welcome without newline___')
os.execv('/bin/sh', ['sh', '-c', sys.argv[-1]])
"""
        self.ssh.write_text("#!" + sys.executable + "\nimport json, os, sys\n"
                            "with open(" + repr(str(self.log)) + ", 'a') as log: log.write(json.dumps(sys.argv[1:]) + '\\n')\n"
                            + forwarder)
        self.ssh.chmod(0o700)

    def command(self):
        return [str(NATIVE), "app-server", "remote", "--ssh", str(self.ssh), "--host", "test-alias",
                "--launcher", self.host[0][0], "--data-dir", str(self.host[1]), "--build-id", "workspace"]

    def test_banner_quoting_rpc_and_connection_scope(self):
        login_shell = self.root / "login-shell"
        login_shell.write_text('#!/bin/sh\ntest "$1" = -l && test "$2" = -i && test "$3" = -c || exit 19\nexport SSH_QA_LOGIN=loaded\nprintf "login banner without newline"\nexec /bin/sh -c "$4"\n')
        login_shell.chmod(0o700)
        self.env["SHELL"] = str(login_shell)
        launcher = Path(self.host[0][0])
        environment_log = self.root / "launch-environment"
        launcher.write_text(launcher.read_text().replace("\nexec ", "\nprintf '%s\\n' \"$SSH_QA_LOGIN\" >> " + shlex.quote(str(environment_log)) + "\nexec "))
        path = self.root / "远端 fixture.txt"
        path.write_text("from working host")
        client = JsonlClient(self.command(), self.env)
        self.addCleanup(client.close)
        # Input may arrive before bootstrap finishes; bootstrap cannot consume it.
        result = client.request("fs.read_file", {"path": str(path)})
        self.assertEqual(result["content"], path.read_text())
        identity = next(x["params"] for x in client.events if x.get("method") == "host.connected")
        client.close()
        self.assertEqual(set(environment_log.read_text().splitlines()), {"loaded"})
        self.assertEqual(self.invoke(self.host, "status")["instance_id"], identity["instance_id"])
        invocations = [json.loads(line) for line in self.log.read_text().splitlines()]
        self.assertEqual(len(invocations), 3)
        for args in invocations:
            self.assertIn("BatchMode=yes", args)
            self.assertIn("ForwardAgent=no", args)
            self.assertIn("ServerAliveInterval=15", args)
            self.assertIn("ServerAliveCountMax=12", args)
            self.assertNotIn("StrictHostKeyChecking=no", args)
            self.assertEqual(args[-1] if "-N" in args else args[-2], "test-alias")
        self.assertIn("status", remote_payload(invocations[0][-1]))
        self.assertIn("start", remote_payload(invocations[1][-1]))
        tunnel = invocations[2]
        self.assertIn("-N", tunnel)
        self.assertIn("ExitOnForwardFailure=yes", tunnel)
        self.assertIn("ControlMaster=no", tunnel)
        self.assertIn("ControlPath=none", tunnel)
        self.assertRegex(tunnel[tunnel.index("-L") + 1], r"^127\.0\.0\.1:[0-9]+:127\.0\.0\.1:[0-9]+$")

    def test_forwarding_failure_is_reported_without_restarting_running_service(self):
        started = self.invoke(self.host, "start")
        source = self.ssh.read_text()
        source = source.replace("import socket, select, threading", "if '-N' in sys.argv:\n    sys.stderr.write('forwarding refused by SSH policy\\n'); sys.exit(255)\nimport socket, select, threading")
        self.ssh.write_text(source)
        result = subprocess.run(self.command(), env=self.env, input=b"", capture_output=True, timeout=15)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(b"forwarding refused by SSH policy", result.stderr)
        self.assertEqual(self.invoke(self.host, "status")["instance_id"], started["instance_id"])
        self.assertEqual(len(self.log.read_text().splitlines()), 2)

    def stub_upgrade(self, response):
        source = self.ssh.read_text()
        start = source.index("    def relay(client):")
        end = source.index("    while True:\n        client, _ = listener.accept()", start)
        accepts = self.root / "upgrade-accepts"
        accepts.write_text("")
        handler = f'''    def relay(client):
        with open({str(accepts)!r}, 'a') as log: log.write('accepted\\n')
        try:
            header = bytearray()
            while not header.endswith(b'\\r\\n\\r\\n'):
                part = client.recv(1)
                if not part: return
                header += part
            response = {response!r}
            if response is not None: client.sendall(response)
            while client.recv(1): pass
        finally:
            client.close()
'''
        self.ssh.write_text(source[:start] + handler + source[end:])
        return accepts

    def test_rejected_upgrade_is_not_retried_or_restarted(self):
        started = self.invoke(self.host, "start")
        for response in [b"HTTP/1.1 403 Forbidden\r\nContent-Length: 0\r\n\r\n",
                         b"HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: invalid\r\n\r\n"]:
            with self.subTest(response=response):
                accepts = self.stub_upgrade(response)
                result = subprocess.run(self.command(), env=self.env, input=b"", capture_output=True, timeout=5)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(b"HandshakeRejected", result.stderr)
                self.assertEqual(accepts.read_text().splitlines(), ["accepted"])
                self.assertEqual(self.invoke(self.host, "status")["instance_id"], started["instance_id"])

    def test_stalled_upgrade_expires_without_restarting_service(self):
        started = self.invoke(self.host, "start")
        accepts = self.stub_upgrade(None)
        began = time.monotonic()
        result = subprocess.run(self.command(), env=self.env, input=b"", capture_output=True, timeout=15)
        self.assertGreaterEqual(time.monotonic() - began, 9)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(b"SSH loopback WebSocket Upgrade deadline exceeded", result.stderr)
        self.assertEqual(accepts.read_text().splitlines(), ["accepted"])
        self.assertEqual(self.invoke(self.host, "status")["instance_id"], started["instance_id"])

    def test_missing_login_shell_refuses_before_starting_service(self):
        for value in ("", str(self.root / "missing-shell")):
            with self.subTest(shell=value):
                environment = dict(self.env)
                environment["SHELL"] = value
                result = subprocess.run(self.command(), env=environment, input=b"", capture_output=True, timeout=10)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(b"requires SHELL to name an executable login shell", result.stderr)
                self.assertEqual(self.invoke(self.host, "status")["status"], "not_running")
                invocations = [json.loads(line) for line in self.log.read_text().splitlines()]
                self.assertTrue(all("start" not in remote_payload(args[-1]) for args in invocations))

    def test_changed_server_identity_does_not_restart_service(self):
        started = self.invoke(self.host, "start")
        result = subprocess.run([*self.command(), "--expected-server-id", "different-server"], env=self.env,
                                input=b"", capture_output=True, timeout=10)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(b"server identity changed", result.stderr)
        self.assertEqual(self.invoke(self.host, "status")["instance_id"], started["instance_id"])
        self.assertEqual(len(self.log.read_text().splitlines()), 1)

    def test_running_service_reconnect_discovers_and_forwards(self):
        started = self.invoke(self.host, "start")
        for _ in range(2):
            client = JsonlClient(self.command(), self.env)
            try:
                status = client.request("server.status", {})
                self.assertEqual(status["instance_id"], started["instance_id"])
            finally:
                client.close()
        invocations = [json.loads(line) for line in self.log.read_text().splitlines()]
        self.assertEqual(len(invocations), 4)
        self.assertEqual(sum("-N" in args for args in invocations), 2)
        self.assertTrue(all("status" in remote_payload(args[-1]) for args in invocations if "-N" not in args))

    def test_failed_status_probe_never_starts_service(self):
        self.ssh.write_text("#!" + sys.executable + "\nimport json, os, sys\n"
                            "with open(" + repr(str(self.log)) + ", 'a') as log: log.write(json.dumps(sys.argv[1:]) + '\\n')\n"
                            # More than a pipe buffer: retain the diagnosis, drain the tail.
                            "sys.stderr.write('Permission denied (publickey).\\n' + 'x' * 262144); sys.stderr.flush()\n"
                            "sys.exit(255)\n")
        result = subprocess.run(self.command(), env=self.env, input=b"", capture_output=True, timeout=10)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(b"Permission denied (publickey)", result.stderr)
        self.assertLess(len(result.stderr), 10000)
        invocations = [json.loads(line) for line in self.log.read_text().splitlines()]
        self.assertEqual(len(invocations), 1)
        self.assertIn("status", remote_payload(invocations[0][-1]))
        self.assertTrue(all("start" not in remote_payload(args[-1]) for args in invocations))
        client = ReconnectingClient(self.command(), self.env)
        try:
            event = client.wait_connection("disconnected", timeout=10)
            self.assertIn("Permission denied (publickey)", event["message"])
            self.assertLess(len(event["message"]), 9000)
        finally:
            client.close()
        self.assertTrue(all("start" not in remote_payload(json.loads(line)[-1]) for line in self.log.read_text().splitlines()))

    def test_window_supervisor_reconnects_and_fences_retired_epoch(self):
        client = ReconnectingClient(self.command(), self.env)
        self.addCleanup(client.close)
        first = client.wait_connection()
        self.invoke(self.host, "stop")
        second = client.wait_connection()
        self.assertGreater(second["epoch"], first["epoch"])
        self.assertEqual(second["identity"]["server_id"], first["identity"]["server_id"])
        self.assertNotEqual(second["identity"]["instance_id"], first["identity"]["instance_id"])
        client.epoch = first["epoch"]
        response = client.response(client.send("server.status", {}))
        self.assertEqual(response["error"]["data"]["outcome"], "unsent")
        client.epoch = second["epoch"]
        self.assertEqual(client.request("server.status", {})["instance_id"], second["identity"]["instance_id"])

    def test_closing_one_window_preserves_other_connection_and_service(self):
        first = ReconnectingClient(self.command(), self.env)
        self.addCleanup(first.close)
        identity = first.wait_connection()["identity"]
        second = ReconnectingClient(self.command(), self.env)
        self.addCleanup(second.close)
        self.assertEqual(second.wait_connection()["identity"]["instance_id"], identity["instance_id"])
        first.close()
        self.assertEqual(first.process.returncode, 0)
        self.assertEqual(second.request("server.status", {})["instance_id"], identity["instance_id"])
        self.assertEqual(self.invoke(self.host, "status")["instance_id"], identity["instance_id"])

    def test_supervisor_eof_flushes_final_response(self):
        client = ReconnectingClient(self.command(), self.env)
        self.addCleanup(client.close)
        identity = client.wait_connection()["identity"]
        request = client.send("server.status", {})
        client.process.stdin.close()
        self.assertEqual(client.response(request)["result"]["instance_id"], identity["instance_id"])
        self.assertEqual(client.process.wait(timeout=10), 0)

    def test_supervisor_blocks_identity_replacement_until_explicit_reassociation(self):
        client = ReconnectingClient(self.command(), self.env)
        self.addCleanup(client.close)
        first = client.wait_connection()
        os.kill(client.process.pid, signal.SIGSTOP)
        try:
            self.invoke(self.host, "stop")
            (self.host[1] / "server-id").write_text("replacement-test-server")
            self.invoke(self.host, "start")
        finally:
            os.kill(client.process.pid, signal.SIGCONT)
        blocked = client.wait_connection("identity_blocked")
        self.assertGreater(blocked["epoch"], first["epoch"])
        self.assertIn("identity changed", blocked["message"])
        response = client.response(client.send("server.status", {}))
        self.assertEqual(response["error"]["data"]["outcome"], "unsent")
        self.assertEqual(self.invoke(self.host, "status")["server_id"], "replacement-test-server")


if __name__ == "__main__":
    unittest.main()
