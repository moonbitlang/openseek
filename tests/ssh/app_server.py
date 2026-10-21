"""Offline app-server contract test; optionally run the same binary over SSH.

Usage: python3 tests/ssh/app_server.py SERVER ENGINE [SSH argv ...]
SSH mode requires a same-filesystem test sshd (isolated keys/config). The wrapper
sets a private HOME and a scripted HTTP model; it never uses account credentials.
"""
import base64
import json
import os
from pathlib import Path
import queue
import shlex
import socket
import struct
import hashlib
import subprocess
import sys
import tempfile
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


class Model(BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def do_POST(self):
        if self.headers.get('Transfer-Encoding', '').lower() == 'chunked':
            while True:
                n = int(self.rfile.readline().strip(), 16)
                if not n:
                    self.rfile.readline()
                    break
                self.rfile.read(n + 2)
        else:
            self.rfile.read(int(self.headers.get('Content-Length', 0)))
        body = ('data: ' + json.dumps({'choices': [{'delta': {'content': 'SSH_CHAT_OK'}, 'finish_reason': 'stop'}]}) + '\n\ndata: [DONE]\n\n').encode()
        self.send_response(200)
        self.send_header('Content-Type', 'text/event-stream')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)


class Peer:
    def __init__(self, port):
        self.socket = socket.socket(socket.AF_INET)
        self.socket.settimeout(10)
        try:
            self.socket.connect(("127.0.0.1", port))
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

    def close(self):
        self.socket.close()


class Client:
    def __init__(self, peer):
        self.peer = peer
        self.inbox = queue.Queue()
        self.events = []
        self.sequence = 0
        def read():
            try:
                while True:
                    self.inbox.put(peer.receive())
            except Exception as error:
                self.inbox.put(error)
        threading.Thread(target=read, daemon=True).start()

    def receive(self, predicate, timeout=45):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            message = self.inbox.get(timeout=max(.1, deadline - time.monotonic()))
            if isinstance(message, Exception):
                raise message
            if predicate(message):
                return message
            self.events.append(message)
        raise TimeoutError('expected app-server response')

    def request(self, method, params):
        self.sequence += 1
        self.peer.send(json.dumps(dict(jsonrpc='2.0', id=self.sequence, method=method, params=params)).encode())
        reply = self.receive(lambda value: value.get('id') == self.sequence)
        assert 'error' not in reply, (method, reply)
        return reply['result']

    def event(self, method):
        for i, event in enumerate(self.events):
            if event.get('method') == method:
                return self.events.pop(i)['params']
        return self.receive(lambda value: value.get('method') == method)['params']


def main():
    executable, engine = map(lambda p: str(Path(p).resolve()), sys.argv[1:3])
    with tempfile.TemporaryDirectory(prefix='seekmoon-ssh-contract-') as directory:
        root = Path(directory).resolve()
        home, workspace = root / 'home', root / 'workspace'
        home.mkdir()
        workspace.mkdir()
        (workspace / 'hello.mbt').write_text('///|\nfn answer() -> Int { 42 }\n')
        (workspace / 'moon.mod').write_text('name = "test/ssh"\n')
        (workspace / 'moon.pkg').write_text('')
        subprocess.run(['git', 'init', '-q', str(workspace)], check=True)
        model = ThreadingHTTPServer(('127.0.0.1', 0), Model)
        threading.Thread(target=model.serve_forever, daemon=True).start()
        env = {**os.environ, 'HOME': str(home), 'OPENSEEK_ENGINE': engine,
               'MOON_HOME': os.environ.get('MOON_HOME', str(Path.home() / '.moon'))}
        # No caller credentials may turn this offline fixture into a live run.
        for key in ['DEEPSEEK_API_KEY', 'GLM_API_KEY', 'OPENAI_API_KEY', 'CODEX_API_KEY']:
            env.pop(key, None)
        wrapper = root / 'server.sh'
        wrapper.write_text('#!/bin/sh\n' + '\n'.join('export ' + key + '=' + shlex.quote(env[key]) for key in ['HOME', 'OPENSEEK_ENGINE', 'MOON_HOME', 'PATH']) + '\nexec ' + shlex.quote(executable) + '\n')
        wrapper.chmod(0o700)
        command = sys.argv[3:] + ['exec ' + shlex.quote(str(wrapper))] if len(sys.argv) > 3 else [str(wrapper)]
        with (root / 'stderr.log').open('w+') as errors:
            process = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=errors, text=True, env=env)
            tunnel = None
            peer = None
            try:
                endpoint = json.loads(process.stdout.readline())
                port = endpoint['port']
                if len(sys.argv) > 3:
                    reservation = socket.socket()
                    reservation.bind(('127.0.0.1', 0))
                    local_port = reservation.getsockname()[1]
                    reservation.close()
                    tunnel = subprocess.Popen(sys.argv[3:-1] + ['-oExitOnForwardFailure=yes', '-oControlMaster=no', '-oControlPath=none', '-N', '-L', f'127.0.0.1:{local_port}:127.0.0.1:{port}', sys.argv[-1]], stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=errors)
                    port = local_port
                deadline = time.monotonic() + 15
                while True:
                    try:
                        peer = Peer(port)
                        break
                    except OSError:
                        if time.monotonic() > deadline:
                            raise
                        time.sleep(.025)
                client = Client(peer)
                # Browser-origin and stale-instance clients must not enter the
                # host command catalog, even when the loopback port is known.
                with socket.create_connection(('127.0.0.1', port), timeout=10) as browser:
                    browser.sendall(b'GET /host HTTP/1.1\r\nHost: localhost\r\nOrigin: https://unrelated.invalid\r\n\r\n')
                    assert browser.recv(4096).startswith(b'HTTP/1.1 403')
                wrong = Peer(port)
                try:
                    wrong.send(json.dumps({'jsonrpc': '2.0', 'id': 1, 'method': 'initialize', 'params': {'protocol': 1, 'instance': 'retired-instance'}}).encode())
                    try:
                        unexpected = wrong.receive()
                    except EOFError:
                        pass
                    else:
                        raise AssertionError(('stale instance accepted', unexpected))
                finally:
                    wrong.close()
                assert client.request('initialize', {'protocol': 1, 'instance': endpoint['instance']}) == {'protocol': 1, 'instance': endpoint['instance']}
                listing = client.request('fs.browse', {'path': str(workspace)})
                assert listing['path'] == str(workspace)
                attached = client.request('workspace.add', {'path': str(workspace)})
                assert str(workspace) in attached['workspaces']
                content = client.request('fs.read_file', {'path': str(workspace / 'hello.mbt')})
                assert '42' in content['content']
                client.request('fs.watch', {'path': str(workspace), 'files': ['hello.mbt'], 'directories': [''], 'generation': 'ssh-test'})
                client.request('settings.set', {'provider': 'custom', 'custom_api_url': f'http://127.0.0.1:{model.server_port}/v1/chat/completions', 'custom_api_key': 'offline-test'})
                started = client.request('agent.start', {'session': 'ssh-contract', 'workspace': str(workspace), 'task': 'Reply SSH_CHAT_OK.', 'images': [], 'model': 'deepseek-flash', 'max_steps': 2})
                finished = client.event('agent.finished')
                assert finished['run_id'] == started['run_id'], (started, finished)
                loaded = client.request('session.load', {'session': 'ssh-contract', 'workspace': str(workspace)})
                assert 'SSH_CHAT_OK' in json.dumps(loaded), (loaded, finished, client.events)
                terminal = client.request('terminal.open', {'session': 'ssh-contract', 'workspace': str(workspace), 'cols': 80, 'rows': 24, 'command': "printf SSH_TERMINAL_OK; printf '///|\\nfn answer() -> Int { 43 }\\n' > hello.mbt"})
                chunks = []
                while True:
                    event = client.event('terminal.output')
                    chunks.append(base64.b64decode(event['data']))
                    client.request('terminal.ack', {'id': event['id'], 'sequence': event['sequence']})
                    if b'SSH_TERMINAL_OK' in b''.join(chunks):
                        break
                exited = client.event('terminal.exit')
                assert exited['id'] == terminal['id'] and exited['code'] == 0, exited
                changed = client.event('fs.changed')
                while 'hello.mbt' not in json.dumps(changed):
                    changed = client.event('fs.changed')
                assert 'hello.mbt' in json.dumps(changed), changed
                assert '43' in client.request('fs.read_file', {'path': str(workspace / 'hello.mbt')})['content']
                changes = client.request('git.changes', {'session': 'ssh-contract', 'workspace': str(workspace)})
                assert 'hello.mbt' in json.dumps(changes), changes
                hover = client.request('lsp.hover', {'session': 'ssh-contract', 'root': str(workspace), 'path': 'hello.mbt', 'line': 1, 'character': 4})
                assert 'Int' in json.dumps(hover), hover
                peer.close()
                process.stdin.close()
                assert process.wait(timeout=15) == 0
                print('PASS: TCP/SSH -L/WebSocket handshake, project, chat/history, files/watch, PTY/output/exit, Git, MoonBit hover, EOF cleanup')
            except BaseException:
                errors.seek(0)
                print(errors.read()[-8000:], file=sys.stderr)
                raise
            finally:
                if peer is not None:
                    peer.close()
                if tunnel is not None:
                    tunnel.terminate()
                    tunnel.wait(timeout=10)
                if process.poll() is None:
                    process.kill()
                    process.wait()
                model.shutdown()
                model.server_close()


if __name__ == '__main__':
    main()
