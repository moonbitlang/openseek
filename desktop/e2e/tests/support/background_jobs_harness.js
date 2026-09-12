import { DesktopBrowserHarness } from './desktop_browser_harness.js';
import { spawn } from 'node:child_process';
import { once } from 'node:events';
import { mkdtempSync, writeFileSync, appendFileSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

// Real subprocess output and retained files behind the existing transport
// seam. The browser is the production bundle; native host tests cover the
// matching metadata, ownership and UTF-8 byte-page implementation.
export class BackgroundJobsHarness extends DesktopBrowserHarness {
  constructor(page) {
    super(page);
    this.directory = mkdtempSync(join(tmpdir(), "OpenSeek jobs 'test "));
    this.livePath = join(this.directory, 'live.out');
    this.oldPath = join(this.directory, 'old.out');
    writeFileSync(this.livePath, '');
    writeFileSync(this.oldPath, 'old failed job output\n');
    this.liveId = '0194e3c1-2345-7abc-8def-0123456789ab';
    this.jobs = [this.view('runtime-new', this.liveId, this.livePath, { kind: 'running' }),
      this.view('runtime-old', 'bg-1', this.oldPath, { kind: 'exited', code: 7 })];
    this.child = spawn(process.execPath, ['-e', `
      process.stdout.write('ready 你好🙂\\n');
      let input = ''; process.stdin.setEncoding('utf8');
      process.stdin.on('data', chunk => { input += chunk; for (;;) {
        const index = input.indexOf('\\n'); if (index < 0) break;
        const command = JSON.parse(input.slice(0, index)); input = input.slice(index + 1);
        (command.stderr ? process.stderr : process.stdout).write(command.text);
      }});
    `], { stdio: ['pipe', 'pipe', 'pipe'] });
    const append = chunk => appendFileSync(this.livePath, chunk);
    this.child.stdout.on('data', append);
    this.child.stderr.on('data', append);
    const live = this.jobs[0];
    this.child.on('close', (code, signal) => {
      live.job.state = signal ? { kind: 'stopped', reason: 'user' } : { kind: 'exited', code };
      live.job.finished_at_ms = Date.now();
      live.job.revision += 1;
      live.controllable = false;
    });
  }
  view(generation, id, path, state) {
    const now = Date.now();
    return { job: { schema_version: 1, generation, id, revision: 1,
      command: generation === 'runtime-new' ? 'node worker.js --watch' : 'just test',
      description: generation === 'runtime-new' ? 'Watch build output' : 'Earlier failing test run',
      cwd: '/workspace', state, started_at_ms: now - 6000, backgrounded_at_ms: now - 5000,
      finished_at_ms: state.kind === 'exited' ? now - 2000 : null,
      last_output_at_ms: now, output_file: generation === 'runtime-new' ? 'live.out' : 'old.out',
      output_persistent: true, output_bytes: 0, output_chars: 0,
      output_truncated: false, invalid_utf8: false,
      output_error: null, persistence_error: null, cleanup_error: null,
    }, output_path: path, controllable: state.kind === 'running', error: null };
  }
  write(text, stderr = false) { this.child.stdin.write(JSON.stringify({ text, stderr }) + '\n'); }
  async replyFor(request) {
    const p = request.params;
    if (request.method === 'session.load') {
      const result = super.replyFor(request);
      result.session.id = p.session;
      return result;
    }
    if (request.method === 'jobs.list') {
      const jobs = p.scope.session === 'session-1' ? this.jobs : [];
      for (const view of jobs) {
        if (view.output_path == null) continue;
        const bytes = readFileSync(view.output_path);
        view.job.output_bytes = bytes.length;
        view.job.output_chars = [...bytes.toString()].length;
      }
      const selected = p.selected ? jobs.find(v => v.job.generation === p.selected.generation && v.job.id === p.selected.job_id) : null;
      return { jobs: jobs.slice(p.offset, p.offset + 100), selected,
        next_offset: p.offset + 100 < jobs.length ? p.offset + 100 : null, errors: [] };
    }
    if (request.method === 'jobs.read') {
      const view = this.jobs.find(v => v.job.generation === p.target.generation && v.job.id === p.target.job_id);
      const bytes = readFileSync(view.output_path);
      let start = p.offset ?? Math.max(0, bytes.length - p.limit);
      if (p.offset == null && start > 0) while (start < bytes.length && (bytes[start] & 0xc0) === 0x80) start++;
      let end = Math.min(start + p.limit, bytes.length);
      while (end < bytes.length && (bytes[end] & 0xc0) === 0x80) end--;
      return { text: bytes.subarray(start, end).toString(), start_offset: start, next_offset: end,
        size: bytes.length, more: end < bytes.length, output_path: view.output_path };
    }
    if (request.method === 'jobs.stop') {
      if (p.generation !== 'runtime-new') return { outcome: 'wrong_runtime' };
      if (this.child.exitCode === null && this.child.signalCode === null) {
        const exited = once(this.child, 'close'); this.child.kill(); await exited;
      }
      return { outcome: 'stopped' };
    }
    return super.replyFor(request);
  }
  async openJobs() {
    const show = this.page.getByRole('button', { name: 'Show panel', exact: true });
    if (await show.isVisible()) await show.click();
    await this.page.getByRole('button', { name: /Jobs Follow background/ }).click();
    await this.page.locator('.jobs-panel').waitFor();
  }
  async cleanup() {
    // Stop browser polling before removing files used by the transport fixture.
    // The page fixture normally closes after afterEach, leaving a small race.
    if (!this.page.isClosed()) await this.page.close();
    if (this.child.exitCode === null && this.child.signalCode === null) {
      const exited = once(this.child, 'close'); this.child.kill(); await exited;
    }
    rmSync(this.directory, { recursive: true, force: true });
  }
}
