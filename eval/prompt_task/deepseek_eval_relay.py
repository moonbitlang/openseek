"""Loopback-only evaluation relay with a pinned DeepSeek address and verified TLS.

For a locally broken DNS route, --upstream-ip may name an address obtained from
an independent lookup of api.deepseek.com. TLS still authenticates that exact
hostname. Request bodies are forwarded unchanged. Logs contain only byte counts,
status, timing and body hashes; never credentials, prompts or response contents.
"""

import argparse
import hashlib
from http.client import HTTPException, HTTPSConnection
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import ipaddress
import json
import socket
import ssl
import threading
import time

HOST = 'api.deepseek.com'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--upstream-ip', required=True, type=ipaddress.ip_address)
    parser.add_argument('--port', type=int, default=18764)
    args = parser.parse_args()
    context = ssl.create_default_context()
    log_lock = threading.Lock()

    class Upstream(HTTPSConnection):
        def connect(self):
            raw = socket.create_connection((str(args.upstream_ip), 443), timeout=15)
            try:
                self.sock = context.wrap_socket(raw, server_hostname=HOST)
            except BaseException:
                raw.close()
                raise
            self.sock.settimeout(180)

    class Handler(BaseHTTPRequestHandler):
        protocol_version = 'HTTP/1.1'

        def log_message(self, *args):
            pass

        def do_GET(self):
            body = b'healthy\n'
            self.send_response(200)
            self.send_header('Content-Length', str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def do_POST(self):
            if self.path != '/chat/completions':
                self.send_error(404)
                return
            limit = 16 * 1024 * 1024
            try:
                if self.headers.get('Transfer-Encoding', '').lower() == 'chunked':
                    chunks = []
                    total = 0
                    while True:
                        line = self.rfile.readline(4096)
                        size = int(line.split(b';', 1)[0].strip(), 16)
                        if size == 0:
                            while self.rfile.readline(8192) not in (b'\r\n', b'\n', b''):
                                pass
                            break
                        total += size
                        if size < 0 or total > limit:
                            raise ValueError('request size')
                        chunk = self.rfile.read(size)
                        if len(chunk) != size or self.rfile.read(2) != b'\r\n':
                            raise ValueError('incomplete chunk')
                        chunks.append(chunk)
                    body = b''.join(chunks)
                else:
                    length = int(self.headers.get('Content-Length', '0'))
                    if not 0 < length <= limit:
                        raise ValueError('request size')
                    body = self.rfile.read(length)
                    if len(body) != length:
                        raise ValueError('incomplete request')
            except (ValueError, OSError):
                self.send_error(400, 'Invalid request body')
                return
            upstream = Upstream(HOST, context=context)
            started = time.monotonic()
            status, error = None, None
            response_bytes = 0
            sent_headers = False
            try:
                headers = {'Content-Type': 'application/json', 'Accept-Encoding': 'identity'}
                if 'Authorization' in self.headers:
                    headers['Authorization'] = self.headers['Authorization']
                upstream.request('POST', '/chat/completions', body=body, headers=headers)
                response = upstream.getresponse()
                status = response.status
                self.send_response(status)
                self.send_header('Content-Type', response.getheader('Content-Type', 'application/json'))
                self.send_header('Connection', 'close')
                self.end_headers()
                sent_headers = True
                self.close_connection = True
                while chunk := response.read1(16384):
                    self.wfile.write(chunk)
                    self.wfile.flush()
                    response_bytes += len(chunk)
            except (OSError, ValueError, HTTPException) as exc:
                error = type(exc).__name__
                if not sent_headers:
                    self.send_error(502, 'Upstream connection failed')
                self.close_connection = True
            finally:
                upstream.close()
                with log_lock:
                    print(json.dumps({'started_unix': round(time.time() - (time.monotonic() - started), 3),
                        'status': status, 'error_type': error, 'request_bytes': len(body),
                        'request_sha256': hashlib.sha256(body).hexdigest(),
                        'response_bytes': response_bytes,
                        'elapsed_s': round(time.monotonic() - started, 3)}), flush=True)

    server = ThreadingHTTPServer(('127.0.0.1', args.port), Handler)
    print(json.dumps({'event': 'ready', 'listen': f'127.0.0.1:{args.port}',
                      'upstream_host': HOST, 'upstream_ip': str(args.upstream_ip),
                      'tls_hostname_verification': True}), flush=True)
    server.serve_forever()


if __name__ == '__main__':
    main()
