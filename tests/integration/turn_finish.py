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


def run_case(executable, serve=False, read_workflow=False):
    with tempfile.TemporaryDirectory(prefix="openseek-turn-finish-") as directory:
        release = Path(directory) / "release"
        source = '''import { "moonbitlang/async", "moonbitlang/async/fs" }
async fn main {
  while !@fs.exists("release") { @async.sleep(10) }
  println("BACKGROUND-RESULT")
}'''
        requests = []
        errors = []
        process = None
        if read_workflow:
            (Path(directory) / "sample.mbt").write_text("first\nselected\nlast\n")
            (Path(directory) / "note.txt").write_text("whole file")

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
                    if read_workflow:
                        names = [tool["function"]["name"] for tool in body["tools"]
                                 if tool.get("type") == "function"]
                        assert "mbtx" in names and "read" not in names, names
                        assert "@builtin/read.mbtx" in messages, messages
                        assert "path:start:end" in messages, messages
                        if step == 1:
                            name, args = "mbtx", {
                                "filename": "@builtin/read.mbtx",
                                "args": ["sample.mbt:2:3", "note.txt"],
                            }
                        elif step == 2:
                            outputs = [message["content"] for message in body["messages"]
                                       if message.get("role") == "tool"]
                            assert len(outputs) == 1, outputs
                            assert '=== "sample.mbt" ===\n2 |selected\n3 |last\n' in outputs[0], outputs
                            assert "start_line=2 shown_lines=2 total_lines=4 truncated=false" in outputs[0], outputs
                            assert '=== "note.txt" ===\n1 |whole file\n' in outputs[0], outputs
                            name, args = "finish", {"answer": "checked the read workflow"}
                        else:
                            raise AssertionError(f"unexpected read workflow request {step}")
                    elif step == 1:
                        name, args = "mbtx", {"source": source}
                    elif step == 2:
                        assert "moved to the background" in messages, messages
                        self.respond({"content": "Waiting for the test result."})
                        return
                    elif step == 3:
                        assert "Background jobs still need a decision" in messages, messages
                        name, args = "job_wait", {"job_ids": ["bg-1"]}
                    elif step == 4 and serve:
                        assert "user_input" in messages, messages
                        assert "[goal cleared]" in messages, messages
                        assert not release.exists(), "job completed before goal wake"
                        name, args = "finish", {"answer": "checked the background result"}
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
                        if serve:
                            process.stdin.write(json.dumps({"command": "goal", "action": "clear"}) + "\n")
                            process.stdin.flush()
                        else:
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
            if read_workflow:
                env["OPENSEEK_REFERENCES"] = str(Path(__file__).resolve().parents[2] / "share")
            command = [
                executable, "serve" if serve else "run", "--no-session", "--dir", directory,
                "--api-key", "test", "--model", "deepseek-v4-flash",
                "--api-url", f"http://127.0.0.1:{server.server_port}/chat/completions",
                "--max-steps", "8", "--mcp-config", "",
            ]
            if serve:
                with tempfile.TemporaryFile(mode="w+") as stderr:
                    process = subprocess.Popen(command, env=env, stdin=subprocess.PIPE,
                                               stdout=subprocess.PIPE, stderr=stderr, text=True)
                    timer = threading.Timer(120, process.kill)
                    timer.start()
                    try:
                        process.stdin.write(json.dumps({"command": "prompt", "text": "Run a background job."}) + "\n")
                        process.stdin.flush()
                        lines = []
                        for line in process.stdout:
                            lines.append(line)
                            if line.startswith("{") and json.loads(line).get("event") == "agent_finished":
                                process.stdin.close()
                                process.stdin = None
                        process.wait(timeout=10)
                        stderr.seek(0)
                        run = subprocess.CompletedProcess(command, process.returncode, "".join(lines), stderr.read())
                    finally:
                        timer.cancel()
                        if process.poll() is None:
                            process.kill()
                            process.wait()
            else:
                prompt = ("Read sample.mbt lines 2 through 3 and all of note.txt, then report the result."
                          if read_workflow else "Run a background job and process its result.")
                run = subprocess.run(command + [prompt],
                                     env=env, capture_output=True, text=True, timeout=120)
            assert not errors, errors
            assert run.returncode == 0, (run.stdout, run.stderr)
            assert len(requests) == (2 if read_workflow else 4 if serve else 5), (requests, run.stdout, run.stderr)
            events = [json.loads(line) for line in run.stdout.splitlines() if line.startswith("{")]
            finishes = [event for event in events if event.get("event") == "agent_finished"]
            assert len(finishes) == 1, finishes
            assert finishes[0]["answer"] == ("checked the read workflow" if read_workflow else "checked the background result"), finishes
            if read_workflow:
                results = [event for event in events if event.get("event") == "tool_result"
                           and event.get("tool_name") == "mbtx"]
                assert len(results) == 1 and not results[0]["is_error"], results
            print("PASS: real CLI advertises the read workflow, omits read, and returns ranged batch output" if read_workflow else
                  "PASS: serve goal clear wakes job_wait while the job is still running" if serve else
                  "PASS: real CLI preserves background work through wait, notice, read, and finish")
        finally:
            server.shutdown()
            server.server_close()
            thread.join()


if __name__ == "__main__":
    executable = str(Path(sys.argv[1]).resolve())
    run_case(executable)
    run_case(executable, serve=True)
    run_case(executable, read_workflow=True)
