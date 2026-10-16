"""Scripted model endpoint; the real OpenSeek engine executes real MoonBit tools."""
import json
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import re
import sys
import threading
import time

root = Path(sys.argv[1]).resolve()
root.mkdir(parents=True, exist_ok=True)


class Model(BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def do_POST(self):
        if self.headers.get("Transfer-Encoding", "").lower() == "chunked":
            chunks = []
            while True:
                size = int(self.rfile.readline().split(b";", 1)[0], 16)
                if size == 0:
                    while self.rfile.readline() != b"\r\n":
                        pass
                    break
                chunks.append(self.rfile.read(size))
                assert self.rfile.read(2) == b"\r\n"
            body = b"".join(chunks)
        else:
            body = self.rfile.read(int(self.headers["Content-Length"]))
        request = json.loads(body)
        serialized = json.dumps(request, ensure_ascii=False)
        match = re.search(r"P2_SCENARIO:([a-z_]+)", serialized)
        if not match:
            self.send_error(400, "missing test scenario")
            return
        scenario = match.group(1)
        with (root / (scenario + ".requests.jsonl")).open("a") as out:
            out.write(serialized + "\n")
        messages = request.get("messages", [])
        tool_outputs = "\n".join(str(item.get("content", "")) for item in messages if item.get("role") == "tool")
        if "REMOTE-WRITE " + scenario in tool_outputs:
            name, args = "finish", {"answer": "REMOTE-FINISHED " + scenario}
        elif (job := re.search(r"moved to the background as job ([A-Za-z0-9_-]{22})", tool_outputs)):
            if "job_wait reason=job_completed" in tool_outputs:
                name, args = "job_output", {"job_id": job.group(1)}
            else:
                name, args = "job_wait", {"job_ids": [job.group(1)]}
        elif tool_outputs:
            name, args = "finish", {"answer": "TOOL-FAILED " + tool_outputs[-3000:]}
        else:
            directory = root / "project"
            started = json.dumps(str(directory / (scenario + ".started")))
            release = json.dumps(str(directory / (scenario + ".release")))
            result = json.dumps(str(directory / (scenario + ".result")))
            content = json.dumps("远端工具 " + scenario + "\n", ensure_ascii=False)
            source = ('import { "moonbitlang/async", "moonbitlang/async/fs", "moonbitlang/openseek_tools@0.2.0" }\nasync fn main {\n'
                      + '  let start = @openseek_tools.call("write", { "path": ' + started + ', "content": "ready" })\n'
                      + '  if start.is_error { fail(start.content) }\n'
                      + '  while !@fs.exists(' + release + ') { @async.sleep(50) }\n'
                      + '  if @fs.exists(' + result + ') { fail("mutation was replayed") }\n'
                      + '  let done = @openseek_tools.call("write", { "path": ' + result + ', "content": ' + content + ' })\n'
                      + '  if done.is_error { fail(done.content) }\n'
                      + '  println("REMOTE-WRITE ' + scenario + '")\n}\n')
            name, args = "mbtx", {"description": "Run held remote lifecycle probe", "source": source}
        response = {"choices": [{"delta": {"tool_calls": [{"index": 0, "id": "call_" + str(time.time_ns()),
                     "type": "function", "function": {"name": name, "arguments": json.dumps(args, ensure_ascii=False)}}]}}]}
        body = ("data: " + json.dumps(response, ensure_ascii=False) + "\n\ndata: [DONE]\n\n").encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


server = ThreadingHTTPServer(("127.0.0.1", 0), Model)
thread = threading.Thread(target=server.serve_forever, daemon=True)
thread.start()
print(json.dumps({"port": server.server_port, "root": str(root)}), flush=True)
sys.stdin.buffer.read()
server.shutdown()
server.server_close()
