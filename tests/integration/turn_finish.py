"""Offline, real-CLI lifecycle test: python3 tests/integration/turn_finish.py EXE.

The local scripted provider launches a real mbtx job, requests a plain-text
finish, then waits, reads the output, and explicitly finishes. A file gate
keeps the job alive until the model selects job_wait; no timed job completion
or external model credentials are needed.
"""

import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


def main():
    executable = str(Path(sys.argv[1]).resolve())
    with tempfile.TemporaryDirectory(prefix="openseek-turn-finish-") as directory:
        release = Path(directory) / "release"
        source = '''import { "moonbitlang/async", "moonbitlang/async/fs" }
async fn main {
  while !@fs.exists("release") { @async.sleep(10) }
  println("BACKGROUND-RESULT")
}'''
        requests = []
        errors = []

        class Provider(BaseHTTPRequestHandler):
            def log_message(self, *_args):
                pass

            def do_POST(self):
                try:
                    if self.headers.get("Transfer-Encoding", "").lower() == "chunked":
                        chunks = []
                        while True:
                            size = int(self.rfile.readline().split(b";", 1)[0], 16)
                            if size == 0:
                                while self.rfile.readline().strip():
                                    pass
                                break
                            chunks.append(self.rfile.read(size))
                            assert self.rfile.read(2) == b"\r\n"
                        raw = b"".join(chunks)
                    else:
                        raw = self.rfile.read(int(self.headers["Content-Length"]))
                    body = json.loads(raw)
                    requests.append(body)
                    step = len(requests)
                    messages = json.dumps(body["messages"])
                    if step == 1:
                        name, args = "mbtx", {"source": source}
                    elif step == 2:
                        assert "moved to the background" in messages, messages
                        self.respond({"content": "Waiting for the test result."})
                        return
                    elif step == 3:
                        assert "Background jobs still need a decision" in messages, messages
                        name, args = "job_wait", {"job_ids": ["bg-1"]}
                    elif step == 4:
                        assert "job_completed" in messages, messages
                        assert "background job bg-1 finished" in messages, messages
                        name, args = "job_output", {"job_id": "bg-1"}
                    elif step == 5:
                        assert "BACKGROUND-RESULT" in messages, messages
                        name, args = "finish", {"answer": "checked the background result"}
                    else:
                        raise AssertionError(f"unexpected model request {step}")
                    self.respond({"tool_calls": [{
                        "index": 0, "id": f"call-{step}", "type": "function",
                        "function": {"name": name, "arguments": json.dumps(args)},
                    }]})
                    if step == 3:
                        release.touch()
                except Exception as error:
                    errors.append(error)
                    self.send_error(500)

            def respond(self, delta):
                self.send_response(200)
                self.send_header("Content-Type", "text/event-stream")
                self.end_headers()
                self.wfile.write(("data: " + json.dumps({"choices": [{"delta": delta}]})
                                  + "\n\ndata: [DONE]\n\n").encode())
                self.wfile.flush()

        server = ThreadingHTTPServer(("127.0.0.1", 0), Provider)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            env = {**os.environ, "DEEPSEEK": "test", "OPENSEEK_RETRY_ATTEMPTS": "1"}
            run = subprocess.run([
                executable, "run", "--no-session", "--dir", directory,
                "--api-key", "test", "--model", "deepseek-v4-flash",
                "--api-url", f"http://127.0.0.1:{server.server_port}/chat/completions",
                "--max-steps", "8", "--mcp-config", "",
                "Run a background job and process its result.",
            ], env=env, capture_output=True, text=True, timeout=120)
            assert not errors, errors
            assert run.returncode == 0, (run.stdout, run.stderr)
            assert len(requests) == 5, (requests, run.stdout, run.stderr)
            events = [json.loads(line) for line in run.stdout.splitlines() if line.startswith("{")]
            finishes = [event for event in events if event.get("event") == "agent_finished"]
            assert len(finishes) == 1, finishes
            assert finishes[0]["answer"] == "checked the background result", finishes
            print("PASS: real CLI preserves background work through wait, notice, read, and finish")
        finally:
            server.shutdown()
            server.server_close()
            thread.join()


if __name__ == "__main__":
    main()
