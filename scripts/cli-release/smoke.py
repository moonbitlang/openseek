"""Run a standalone native CLI in a clean home, using real HTTPS and an offline model.

CI-only Python harness. The installed CLI itself needs neither Python nor Node.
"""
import functools
import http.server
import json
import os
from pathlib import Path
import shutil
import ssl
import subprocess
import sys
import tempfile
import threading


def run(binary, assets, platform):
    binary, assets = Path(binary).resolve(), Path(assets).resolve()
    manifest = json.loads((assets / f"runtime-{platform}.json").read_text())
    with tempfile.TemporaryDirectory(prefix="openseek-release-smoke-") as temporary:
        root = Path(temporary)
        home = root / "home"
        home.mkdir()
        (home / ".bashrc").write_text("# existing shell profile\n")
        (home / ".moon").mkdir()
        (home / ".moon/marker").write_text("existing SDK")
        (home / "registry").mkdir()
        (home / "registry/marker").write_text("existing registry")
        cli = root / "bootstrap/bin/openseek"
        cli.parent.mkdir(parents=True)
        (root / "bootstrap/share").mkdir()
        (root / "bootstrap/share/wrong-resource").write_text("must not shadow the managed release resources")
        shutil.copyfile(binary, cli)
        cli.chmod(0o755)
        cert, key = root / "cert.pem", root / "key.pem"
        subprocess.run(["openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-days", "1",
                        "-subj", "/CN=localhost", "-addext", "subjectAltName=DNS:localhost,IP:127.0.0.1",
                        "-keyout", str(key), "-out", str(cert)], check=True, capture_output=True)
        handler = functools.partial(http.server.SimpleHTTPRequestHandler, directory=str(assets))
        server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), handler)
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.load_cert_chain(cert, key)
        server.socket = context.wrap_socket(server.socket, server_side=True)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        environment = {**os.environ, "HOME": str(home), "XDG_DATA_HOME": str(home / "data"),
                       "MOON_HOME": str(home / "registry"), "PATH": "/usr/bin:/bin",
                       "CURL_CA_BUNDLE": str(cert), "NO_PROXY": "127.0.0.1,localhost", "no_proxy": "127.0.0.1,localhost"}
        def invoke(args, timeout=1000):
            result = subprocess.run([str(cli), *args], env=environment, cwd=root, capture_output=True, text=True, timeout=timeout)
            assert result.returncode == 0, (result.returncode, result.stdout, result.stderr)
            return result
        try:
            invoke(["--help"])
            url = f"https://127.0.0.1:{server.server_port}/openseek-runtime-{platform}.tar.gz"
            events = [json.loads(line) for line in invoke(["setup", "--json", "--runtime-url", url]).stdout.splitlines()]
            ready = events[-1]
            assert ready["event"] == "ready" and not ready["reused"], events
            assert ready["release"] == manifest["id"] and ready["platform"] == platform, ready
            runtime = Path(ready["runtime_dir"])
            assert runtime.name == manifest["sha256"]
            assert (runtime / "share/doc/moonbit/index.md").is_file()
        finally:
            server.shutdown()
            server.server_close()
            thread.join()
        # No download server is running. Idempotence must not depend on network.
        reused = [json.loads(line) for line in invoke(["setup", "--json", "--runtime-url", url]).stdout.splitlines()]
        assert reused[-1]["event"] == "ready" and reused[-1]["reused"], reused
        assert not any(item.get("stage") == "download" for item in reused), reused
        assert "OpenSeek is ready:" in invoke(["setup"]).stdout
        assert (home / ".bashrc").read_text() == "# existing shell profile\n"
        assert (home / ".moon/marker").read_text() == "existing SDK"
        assert (home / "registry/marker").read_text() == "existing registry"
        source = root / "sample.mbtx"
        source.write_text('fn main { println("CLI-SETUP-OK") }\n')
        tools_env = {**environment, "PATH": f"{runtime}/toolchain/bin:{runtime}/bin:/usr/bin:/bin"}
        program = subprocess.run([str(runtime / "toolchain/bin/moon"), "run", str(source)], env=tools_env,
                                 cwd=root, text=True, capture_output=True, timeout=120)
        assert program.returncode == 0 and "CLI-SETUP-OK" in program.stdout, (program.stdout, program.stderr)
        subprocess.run([str(runtime / "bin/rg"), "CLI-SETUP-OK", str(source)], check=True, capture_output=True)

        # A new CLI process must activate its managed PATH and resources itself.
        # The fake model asks for a real mbtx tool call and checks its output.
        state = {"requests": 0, "failure": None}
        class Model(http.server.BaseHTTPRequestHandler):
            def log_message(self, *args):
                pass
            def do_POST(self):
                try:
                    if self.headers.get("Transfer-Encoding", "").lower() == "chunked":
                        chunks = []
                        while True:
                            size = int(self.rfile.readline().split(b";")[0], 16)
                            if size == 0:
                                self.rfile.readline()
                                break
                            chunks.append(self.rfile.read(size))
                            assert self.rfile.read(2) == b"\r\n"
                        raw = b"".join(chunks)
                    else:
                        raw = self.rfile.read(int(self.headers["Content-Length"]))
                    body = json.loads(raw)
                    state["requests"] += 1
                    if state["requests"] == 1:
                        assert str(runtime / "share") in json.dumps(body), "managed documentation missing from prompt"
                        name, args = "mbtx", {"source": source.read_text()}
                    else:
                        assert state["requests"] == 2, body
                        assert any(m.get("role") == "tool" and "CLI-SETUP-OK" in str(m.get("content")) for m in body["messages"]), body
                        name, args = "finish", {"answer": "SETUP-AGENT-PASSED"}
                    delta = {"tool_calls": [{"index": 0, "id": f"setup-{state['requests']}", "type": "function",
                                            "function": {"name": name, "arguments": json.dumps(args)}}]}
                    payload = ("data: " + json.dumps({"choices": [{"delta": delta}]}) + "\n\ndata: [DONE]\n\n").encode()
                    self.send_response(200)
                    self.send_header("Content-Type", "text/event-stream")
                    self.send_header("Content-Length", str(len(payload)))
                    self.end_headers()
                    self.wfile.write(payload)
                except Exception as error:
                    state["failure"] = repr(error)
                    self.send_error(500, str(error))
        model = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Model)
        worker = threading.Thread(target=model.serve_forever, daemon=True)
        worker.start()
        try:
            response = invoke(["run", "--no-session", "--dir", str(root), "--api-key", "fixture", "--model", "deepseek-flash",
                               "--api-url", f"http://127.0.0.1:{model.server_port}/chat/completions", "--max-steps", "3",
                               "--retry-attempts", "1", "Verify the installed runtime."])
            assert state["failure"] is None, state
            assert state["requests"] == 2 and "SETUP-AGENT-PASSED" in response.stdout, response.stdout
        finally:
            model.shutdown()
            model.server_close()
            worker.join()
        print(json.dumps({"platform": platform, "release": manifest["id"], "setup": "passed", "reuse": "passed", "agent": "passed"}))


if __name__ == "__main__":
    run(*sys.argv[1:])
