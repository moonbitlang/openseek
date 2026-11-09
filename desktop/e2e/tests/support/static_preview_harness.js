import { spawn } from 'node:child_process';
import { createInterface } from 'node:readline';
import { mkdtemp, mkdir, writeFile, readFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const repository = fileURLToPath(new URL('../../../../', import.meta.url));

export class StaticPreviewHarness {
  async start() {
    const wasm = process.env.OPENSEEK_DESKTOP_PREVIEW_WASM;
    if (!wasm) throw new Error('Set OPENSEEK_DESKTOP_PREVIEW_WASM to the preview serve.wasm artifact');
    const runtime = process.env.OPENSEEK_DESKTOP_PREVIEW_MOONRUN || 'moonrun';
    this.root = await mkdtemp(join(tmpdir(), 'seekmoon-static-preview-'));
    await mkdir(join(this.root, 'pages'));
    await mkdir(join(this.root, 'assets'));
    await writeFile(join(this.root, 'assets/font.ttf'), await readFile(new URL('../../../dist/browser/assets/fonts/LiberationSans-Regular.ttf', import.meta.url)));
    await writeFile(join(this.root, 'pages/index.html'), `<!doctype html><meta charset="utf-8">
      <title>Local static preview</title><link rel="stylesheet" href="../assets/style.css">
      <h1>Local static preview</h1><img src="../assets/icon.svg" alt="Preview image">
      <button id="action">Run JavaScript</button><output id="result">Ready</output>
      <script type="module" src="../assets/main.mjs"></script>`);
    await writeFile(join(this.root, 'assets/style.css'), '@font-face { font-family: PreviewFont; src: url("./font.ttf") } body { font: 16px system-ui; padding: 24px; background: rgb(241, 245, 249) } h1 { color: rgb(30, 64, 175) } img { display:block; width:96px; margin:16px 0 } button { padding:10px 16px } output { display:block; margin-top:16px }');
    await writeFile(join(this.root, 'assets/icon.svg'), '<svg xmlns="http://www.w3.org/2000/svg" width="96" height="64"><rect width="96" height="64" rx="8" fill="#3b82f6"/><text x="48" y="38" text-anchor="middle" fill="white">HTML</text></svg>');
    await writeFile(join(this.root, 'assets/main.mjs'), `document.querySelector('#action').onclick = async () => {
      const { label } = await import('./dynamic.mjs');
      const data = await fetch('../assets/data.json').then(r => r.json());
      document.querySelector('#result').textContent = label + ': ' + data.value;
    };`);
    await writeFile(join(this.root, 'assets/dynamic.mjs'), 'export const label = "Dynamic import + fetch";');
    await writeFile(join(this.root, 'assets/data.json'), '{"value":"loaded"}');
    const executable = process.env.OPENSEEK_DESKTOP_PREVIEW_SERVER;
    const args = executable ? [] : ['run', '--target', 'native', 'desktop/backend/static_preview/test_server', '--'];
    this.child = spawn(executable || 'moon', [...args, resolve(wasm), runtime], { cwd: repository, stdio: ['pipe', 'pipe', 'pipe'] });
    this.errors = '';
    this.child.stderr.on('data', chunk => { this.errors += chunk; });
    this.pending = [];
    const ready = Promise.withResolvers();
    this.child.once('error', error => ready.reject(error));
    this.child.once('exit', code => {
      const error = new Error(`Preview fixture exited ${code}: ${this.errors}`);
      ready.reject(error);
      for (const pending of this.pending.splice(0)) pending.reject(error);
    });
    createInterface({ input: this.child.stdout }).on('line', line => {
      if (!line.startsWith('{')) return;
      const reply = JSON.parse(line);
      if (reply.ready) ready.resolve();
      else {
        const pending = this.pending.shift();
        if (reply.error) pending?.reject(new Error(reply.error));
        else pending?.resolve(reply);
      }
    });
    try {
      await ready.promise;
    } catch (error) {
      await rm(this.root, { recursive: true, force: true });
      throw error;
    }
    return this;
  }

  request(value) {
    const reply = Promise.withResolvers();
    this.pending.push(reply);
    this.child.stdin.write(`${JSON.stringify(value)}\n`);
    return reply.promise;
  }

  open(id = 1) {
    return this.request({ id, path: join(this.root, 'pages/index.html'), root: this.root });
  }

  async close() {
    this.child?.stdin.end();
    if (this.child && this.child.exitCode === null && this.child.signalCode === null) {
      await new Promise(resolve => this.child.once('exit', resolve));
    }
    await rm(this.root, { recursive: true, force: true });
  }
}
