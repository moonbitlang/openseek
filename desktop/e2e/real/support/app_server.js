import { spawn } from 'node:child_process';
import { mkdir } from 'node:fs/promises';
import { createInterface } from 'node:readline';
import { homedir } from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const checkout = fileURLToPath(new URL('../../../../', import.meta.url));
const build = path.join(checkout, '_build/native/debug/build');

// `just test-browser-real-build` (desktop/justfile) builds both binaries here.
export const appServerBinary = process.env.OPENSEEK_E2E_APP_SERVER ??
  path.join(build, 'openseek_desktop/backend/server/server.exe');
export const engineBinary = process.env.OPENSEEK_E2E_ENGINE ??
  path.join(build, 'moonbitlang/openseek/openseek.exe');
export const bundleDir = fileURLToPath(new URL('../../../dist/browser', import.meta.url));

function firstLine(stream, parse) {
  return new Promise((resolve, reject) => {
    const lines = createInterface({ input: stream });
    lines.on('line', line => {
      let value;
      try { value = parse(JSON.parse(line)); } catch { return; }
      if (value === undefined) return;
      lines.removeAllListeners('line');
      resolve(value);
    });
    lines.on('close', () => reject(new Error('app-server exited before announcing')));
  });
}

// The real headless `openseek-app-server`, serving the built browser bundle
// through its loopback console (`OPENSEEK_APP_SERVER_CONSOLE`). The fixture
// owns the service through the app-server protocol's initialize handshake:
// the process lives exactly as long as that socket.
export class AppServer {
  constructor({ home, modelUrl }) {
    this.home = home;
    this.modelUrl = modelUrl;
    this.nextId = 1;
    this.pending = new Map();
    this.stderr = '';
    this.timings = {};
  }

  async start() {
    const started = performance.now();
    await mkdir(this.home, { recursive: true });
    const moonHome = process.env.MOON_HOME ?? path.join(homedir(), '.moon');
    // A clean environment: no inherited model keys, account tokens or user
    // configuration reach the engine.
    this.child = spawn(appServerBinary, [], {
      cwd: this.home,
      stdio: ['pipe', 'pipe', 'pipe'],
      env: {
        HOME: this.home,
        TMPDIR: process.env.TMPDIR ?? '/tmp',
        PATH: `${path.join(moonHome, 'bin')}:/usr/bin:/bin:/usr/sbin:/sbin`,
        MOON_HOME: moonHome,
        OPENSEEK_ENGINE: engineBinary,
        OPENSEEK_APP_SERVER_CONSOLE: bundleDir,
      },
    });
    this.child.stderr.setEncoding('utf8');
    this.child.stderr.on('data', chunk => {
      // Keep a bounded tail for startup failure reports.
      this.stderr = (this.stderr + chunk).slice(-20_000);
    });
    this.exited = new Promise(resolve => this.child.once('exit', code => resolve(code)));
    const [announcement, origin] = await Promise.all([
      firstLine(this.child.stdout, value => value.port === undefined ? undefined : value),
      firstLine(this.child.stderr, value => value.console),
    ]);
    this.timings.announce = performance.now() - started;
    this.origin = origin;
    // Node's WebSocket sends no Origin header, which `/host` requires.
    this.socket = new WebSocket(`ws://127.0.0.1:${announcement.port}/host`);
    await new Promise((resolve, reject) => {
      this.socket.onopen = resolve;
      this.socket.onerror = () => reject(new Error(`app-server socket failed:\n${this.stderr}`));
    });
    this.socket.onmessage = event => this.receive(JSON.parse(event.data));
    await this.request('initialize', { instance: announcement.instance, protocol: 1 });
    this.timings.initialized = performance.now() - started;
    await this.request('settings.set', {
      provider: 'custom',
      custom_api_url: this.modelUrl,
      custom_api_key: 'fixture',
    });
    this.timings.ready = performance.now() - started;
  }

  receive(message) {
    if (message.id === undefined) return;
    const pending = this.pending.get(message.id);
    if (!pending) return;
    this.pending.delete(message.id);
    if (message.error) pending.reject(new Error(`${pending.method}: ${JSON.stringify(message.error)}`));
    else pending.resolve(message.result);
  }

  request(method, params) {
    const id = this.nextId++;
    return new Promise((resolve, reject) => {
      this.pending.set(id, { method, resolve, reject });
      this.socket.send(JSON.stringify({ jsonrpc: '2.0', id, method, params }));
    });
  }

  // Closing the owner socket ends the service.
  async stop() {
    if (!this.child) return;
    this.socket?.close();
    this.child.stdin.end();
    const code = await Promise.race([
      this.exited,
      new Promise(resolve => setTimeout(() => resolve('timeout'), 10_000)),
    ]);
    if (code === 'timeout') this.child.kill('SIGKILL');
  }
}
