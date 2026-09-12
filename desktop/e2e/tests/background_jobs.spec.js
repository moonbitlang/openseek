import { test, expect } from '@playwright/test';
import { readFileSync } from 'node:fs';
import { BackgroundJobsHarness } from './support/background_jobs_harness.js';

let app;
test.afterEach(async () => { if (app) await app.cleanup(); app = null; });

async function mount(page) {
  app = new BackgroundJobsHarness(page);
  await app.install(); await app.goto(); await app.openSession(); await app.openJobs();
  await expect(page.getByRole('region', { name: 'Job output' })).toContainText('ready 你好🙂');
}

test('real background output follows, pauses, resumes, copies its file and stops', async ({ page, context }, testInfo) => {
  await context.grantPermissions(['clipboard-read', 'clipboard-write']);
  await mount(page);
  await expect(page.locator('.jobs-id').first()).toHaveText('bg-…456789ab');
  await expect(page.locator('.jobs-id').first()).toHaveAttribute('title', app.liveId);
  await page.getByRole('button', { name: 'Copy job ID', exact: true }).click();
  await expect.poll(() => page.evaluate(() => navigator.clipboard.readText())).toBe(app.liveId);
  const output = page.getByRole('region', { name: 'Job output' });
  app.write('stdout without newline'); app.write('\nstderr captured\n', true);
  await expect(output).toContainText('stdout without newline');
  await expect(output).toContainText('stderr captured');
  await page.getByRole('button', { name: 'Pause', exact: true }).click();
  app.write('while paused\n');
  await expect.poll(() => readFileSync(app.livePath, 'utf8')).toContain('while paused');
  await expect(output).not.toContainText('while paused');
  await page.getByRole('button', { name: 'Follow output', exact: true }).click();
  await expect(output).toContainText('while paused');
  await page.getByRole('button', { name: 'Copy path', exact: true }).click();
  await expect.poll(() => page.evaluate(() => navigator.clipboard.readText())).toBe(app.livePath);
  await page.getByRole('button', { name: 'Copy tail command', exact: true }).click();
  await expect.poll(() => page.evaluate(() => navigator.clipboard.readText())).toContain("'\\''");
  app.write(Array.from({ length: 150 }, (_, i) => `build step ${i} passed\n`).join(''));
  await expect(output).toContainText('build step 149 passed');
  await expect.poll(() => output.evaluate(el => el.scrollHeight - el.scrollTop - el.clientHeight)).toBeLessThan(25);
  await output.evaluate(el => { el.scrollTop = 0; });
  await expect(page.getByRole('button', { name: 'Follow output', exact: true })).toBeVisible();
  const top = await output.evaluate(el => el.scrollTop);
  app.write('new output while reading earlier lines\n');
  await expect.poll(() => readFileSync(app.livePath, 'utf8')).toContain('new output while reading');
  await expect.poll(() => output.evaluate(el => el.scrollTop)).toBe(top);
  await page.screenshot({ path: testInfo.outputPath('jobs-light.png'), fullPage: true });
  await page.emulateMedia({ colorScheme: 'dark' });
  await page.screenshot({ path: testInfo.outputPath('jobs-dark.png'), fullPage: true });
  await page.getByRole('button', { name: 'Stop job', exact: true }).click();
  await expect(page.locator('.jobs-detail-title')).toContainText('Stopped');
  await expect(page.getByRole('button', { name: 'Stop job', exact: true })).toHaveCount(0);
  expect(app.child.signalCode).not.toBeNull();
  expect(readFileSync(app.livePath, 'utf8')).toContain('stderr captured');
  const stop = app.requests.find(r => r.method === 'jobs.stop');
  expect(stop.params).toMatchObject({ scope: { session: 'session-1', workspace: '/workspace' }, generation: 'runtime-new', job_id: app.liveId });
  expect(app.requests.filter(r => r.method === 'jobs.read').every(r => r.params.limit <= 65536)).toBe(true);
  expect(app.pageErrors).toEqual([]);
});

test('historical selection rejects late reads, reports errors and fits a narrow panel', async ({ page }, testInfo) => {
  await mount(page);
  app.rpcDelays.set('jobs.read', 1200);
  app.write('must stay with the live job\n');
  await expect.poll(() => app.requests.filter(r => r.method === 'jobs.read').length).toBeGreaterThan(1);
  app.rpcDelays.delete('jobs.read');
  await page.getByRole('button', { name: /Earlier failing test run/ }).click();
  const output = page.getByRole('region', { name: 'Job output' });
  await expect(output).toContainText('old failed job output');
  await expect(page.locator('.jobs-detail-title')).toContainText('Failed · exit 7');
  await expect(page.getByRole('button', { name: 'Stop job', exact: true })).toHaveCount(0);
  await page.waitForTimeout(1400); // The deliberately delayed obsolete reply must arrive.
  await expect(output).not.toContainText('must stay with the live job');
  app.rpcErrors.set('jobs.read', 'Output file is missing: ENOENT');
  await page.getByRole('button', { name: 'Reload tail', exact: true }).click();
  await expect(page.getByRole('alert')).toContainText('Output file is missing');
  await expect(page.locator('.jobs-output-note')).toHaveText('Output unavailable · reload to retry.');
  app.rpcErrors.delete('jobs.read');
  await page.getByRole('button', { name: 'Reload tail', exact: true }).click();
  await expect(output).toContainText('old failed job output');
  await page.setViewportSize({ width: 1000, height: 850 });
  await expect.poll(() => page.locator('.jobs-panel').evaluate(el => el.scrollWidth <= el.clientWidth + 1)).toBe(true);
  await expect(page.getByRole('button', { name: 'Copy tail command', exact: true })).toBeInViewport();
  await page.screenshot({ path: testInfo.outputPath('jobs-narrow.png'), fullPage: true });
  expect(app.pageErrors).toEqual([]);
});

test('page reconnect recovers retained job identity and history', async ({ page }) => {
  await mount(page);
  app.write('persist across reconnect\n');
  await expect(page.getByRole('region', { name: 'Job output' })).toContainText('persist across reconnect');
  await page.reload(); await app.openSession(); await app.openJobs();
  await expect(page.getByRole('region', { name: 'Job output' })).toContainText('persist across reconnect');
  await expect(page.getByRole('button', { name: /Earlier failing test run/ })).toBeVisible();
  expect(app.pageErrors).toEqual([]);
});

test('switching conversations cannot display a late log from the previous session', async ({ page }) => {
  app = new BackgroundJobsHarness(page);
  app.liveSessions.push({ id: 'session-2', title: 'Another conversation', updated_at_ms: 2 });
  await app.install(); await app.goto(); await app.openSession(); await app.openJobs();
  await expect(page.getByRole('region', { name: 'Job output' })).toContainText('ready 你好🙂');
  app.rpcDelays.set('jobs.read', 1200);
  const before = app.requests.filter(r => r.method === 'jobs.read').length;
  await page.getByRole('button', { name: 'Reload tail', exact: true }).click();
  await expect.poll(() => app.requests.filter(r => r.method === 'jobs.read').length).toBeGreaterThan(before);
  await page.locator('.conversation-row[title="session-2"]').click();
  await app.openJobs();
  await expect(page.locator('.jobs-panel')).toContainText('No background jobs yet');
  await page.waitForTimeout(1400); // Deliver the first conversation's obsolete reply.
  await expect(page.locator('.jobs-panel')).not.toContainText('ready 你好🙂');
  app.rpcDelays.delete('jobs.read');
  await page.locator('.conversation-row[title="session-1"]').click();
  await expect(page.getByRole('region', { name: 'Job output' })).toContainText('ready 你好🙂');
  expect(app.requests.some(r => r.method === 'jobs.list' && r.params.scope.session === 'session-2')).toBe(true);
  expect(app.pageErrors).toEqual([]);
});


test('selected job beyond the first history page keeps receiving terminal state', async ({ page }) => {
  app = new BackgroundJobsHarness(page);
  for (let i = 2; i <= 101; i++) {
    const view = app.view('runtime-new', `bg-${i}`, app.oldPath, { kind: 'exited', code: 0 });
    view.job.description = `Completed build ${i}`;
    app.jobs.splice(1, 0, view);
  }
  await app.install(); await app.goto(); await app.openSession(); await app.openJobs();
  const selected = app.jobs.find(v => v.job.generation === 'runtime-old');
  selected.job.state = { kind: 'running' };
  await page.getByRole('button', { name: 'Load older jobs', exact: true }).click();
  await page.getByRole('button', { name: /Earlier failing test run/ }).click();
  await page.getByRole('button', { name: 'Pause', exact: true }).click();
  selected.job.state = { kind: 'stopped', reason: 'user' };
  selected.job.revision++;
  await expect(page.locator('.jobs-detail-title')).toContainText('Stopped');
  expect(app.requests.some(r => r.method === 'jobs.list' && r.params.offset === 0 && r.params.selected?.generation === 'runtime-old')).toBe(true);
  expect(app.pageErrors).toEqual([]);
});

test('follow catches up with a large completed burst without waiting one tick per page', async ({ page }) => {
  await mount(page);
  const output = page.getByRole('region', { name: 'Job output' });
  app.write('x'.repeat(65536 * 9) + '\nBURST FINISHED\n');
  await expect.poll(() => readFileSync(app.livePath, 'utf8').endsWith('BURST FINISHED\n')).toBe(true);
  await page.getByRole('button', { name: 'Stop job', exact: true }).click();
  await expect(output).toContainText('BURST FINISHED', { timeout: 5000 });
  await expect(page.locator('.jobs-detail-title')).toContainText('Stopped');
  expect(await output.evaluate(el => el.textContent.length)).toBeLessThanOrEqual(262144);
  expect(app.pageErrors).toEqual([]);
});

test('pause resume and reload serialize reads and preserve manual paused refresh', async ({ page }) => {
  await mount(page);
  const original = app.replyFor.bind(app);
  let release;
  const gate = new Promise(resolve => { release = resolve; });
  let held = false;
  let readCount = 0;
  app.replyFor = async request => {
    if (request.method === 'jobs.read') {
      readCount++;
      if (!held) { held = true; await gate; }
    }
    return original(request);
  };
  try {
    await expect.poll(() => held).toBe(true);
    await page.getByRole('button', { name: 'Pause', exact: true }).click();
    await page.getByRole('button', { name: 'Follow output', exact: true }).click();
    expect(readCount).toBe(1);
    await page.getByRole('button', { name: 'Pause', exact: true }).click();
    app.write('manual paused reload\n');
    await expect.poll(() => readFileSync(app.livePath, 'utf8')).toContain('manual paused reload');
    await page.getByRole('button', { name: 'Reload tail', exact: true }).click();
    expect(readCount).toBe(1);
    release();
    await expect(page.getByRole('region', { name: 'Job output' })).toContainText('manual paused reload');
    await expect(page.getByRole('button', { name: 'Follow output', exact: true })).toBeVisible();
    expect(readCount).toBe(2);
    expect(app.pageErrors).toEqual([]);
  } finally { release(); }
});

test('a controllable job without a log still exposes Stop and its full ID', async ({ page, context }) => {
  await context.grantPermissions(['clipboard-read', 'clipboard-write']);
  app = new BackgroundJobsHarness(page);
  app.jobs[0].output_path = null;
  app.jobs[0].job.output_file = null;
  await app.install(); await app.goto(); await app.openSession(); await app.openJobs();
  await expect(page.getByRole('button', { name: 'Copy path', exact: true })).toHaveCount(0);
  await expect(page.locator('.jobs-output-note')).toHaveText('No retained log file for this job.');
  await page.getByRole('button', { name: 'Copy job ID', exact: true }).click();
  await expect.poll(() => page.evaluate(() => navigator.clipboard.readText())).toBe(app.liveId);
  await expect(page.getByRole('region', { name: 'Job output' })).toHaveCount(0);
  await page.getByRole('button', { name: 'Stop job', exact: true }).click();
  await expect(page.locator('.jobs-detail-title')).toContainText('Stopped');
  expect(app.child.signalCode).not.toBeNull();
  expect(app.pageErrors).toEqual([]);
});


test('UUID suffix collisions expand labels while selection and copying retain full IDs', async ({ page, context }, testInfo) => {
  await context.grantPermissions(['clipboard-read', 'clipboard-write']);
  app = new BackgroundJobsHarness(page);
  const otherId = '0194e3c1-2346-7abc-8def-abcd456789ab';
  const other = app.view('runtime-new', otherId, app.oldPath, { kind: 'exited', code: 0 });
  other.job.description = 'Same short suffix';
  app.jobs.push(other);
  await app.install(); await app.goto(); await app.openSession(); await app.openJobs();
  await expect(page.locator('.jobs-id')).toHaveText(['bg-…0123456789ab', 'bg-1', 'bg-…abcd456789ab']);
  await page.getByRole('button', { name: /Same short suffix/ }).click();
  await expect(page.getByRole('region', { name: 'Job output' })).toContainText('old failed job output');
  await page.getByRole('button', { name: 'Copy job ID', exact: true }).click();
  await expect.poll(() => page.evaluate(() => navigator.clipboard.readText())).toBe(otherId);
  expect(app.requests.some(r => r.method === 'jobs.read' && r.params.target.job_id === otherId)).toBe(true);
  await page.setViewportSize({ width: 1000, height: 850 });
  await expect.poll(() => page.locator('.jobs-panel').evaluate(el => el.scrollWidth <= el.clientWidth + 1)).toBe(true);
  await expect(page.getByRole('button', { name: 'Copy job ID', exact: true })).toBeInViewport();
  await page.screenshot({ path: testInfo.outputPath('jobs-uuid-narrow.png'), fullPage: true });
  expect(app.pageErrors).toEqual([]);
});

test('groups lifecycle states and defaults to an active job even after newer history', async ({ page }, testInfo) => {
  app = new BackgroundJobsHarness(page);
  const live = app.jobs[0];
  const fixtures = [
    ['completed', { kind: 'exited', code: 0 }, 'Completed'],
    ['stopped', { kind: 'stopped', reason: 'user' }, 'Stopped'],
    ['interrupted', { kind: 'interrupted' }, 'Interrupted'],
    ['limited', { kind: 'stopped', reason: 'time_limit' }, 'Stopped · time limit reached'],
    ['stopping', { kind: 'stopping' }, 'Stopping…'],
  ];
  for (const [id, state] of fixtures) {
    const view = app.view('runtime-new', id, app.oldPath, state);
    view.job.description = `Lifecycle ${id}`;
    // Even a controllable stopping job must not offer a second stop request.
    view.controllable = state.kind === 'stopping';
    app.jobs.push(view);
  }
  app.jobs.splice(0, 1); app.jobs.splice(1, 0, live);
  await app.install(); await app.goto(); await app.openSession(); await app.openJobs();
  await expect(page.getByRole('region', { name: 'Job output' })).toContainText('ready 你好🙂');
  const active = page.getByRole('group', { name: 'In progress', exact: true });
  const history = page.getByRole('group', { name: 'History', exact: true });
  await expect(active.locator('.jobs-row')).toHaveCount(2);
  await expect(history.locator('.jobs-row')).toHaveCount(5);
  expect(await page.locator('.jobs-group').evaluateAll(groups => groups.map(el => el.getAttribute('aria-label')))).toEqual(['In progress', 'History']);
  for (const [id, , label] of fixtures) {
    await page.getByRole('button', { name: new RegExp(`Lifecycle ${id}`) }).click();
    await expect(page.locator('.jobs-detail-title')).toContainText(label);
    if (id === 'stopping') {
      await expect(page.getByRole('button', { name: 'Stopping…', exact: true })).toBeDisabled();
      await expect(page.getByRole('button', { name: 'Pause', exact: true })).toBeVisible();
    } else {
      await expect(page.locator('.jobs-output-note')).toHaveText('Output ended');
      await expect(page.getByRole('button', { name: /^(Stop job|Pause|Follow output)$/ })).toHaveCount(0);
      if (id === 'interrupted') {
        await expect(page.locator('.jobs-detail')).toContainText('End time unavailable');
        await expect(page.locator('.jobs-detail')).not.toContainText('Running for');
      }
    }
  }
  await page.screenshot({ path: testInfo.outputPath('jobs-lifecycle-light.png'), fullPage: true });
  await page.emulateMedia({ colorScheme: 'dark' });
  await page.screenshot({ path: testInfo.outputPath('jobs-lifecycle-dark.png'), fullPage: true });
  await page.setViewportSize({ width: 1000, height: 850 });
  await page.getByRole('button', { name: /Lifecycle limited/ }).click();
  await expect.poll(() => page.locator('.jobs-panel, .jobs-row, .jobs-status').evaluateAll(elements => elements.every(el => el.scrollWidth <= el.clientWidth + 1))).toBe(true);
  await page.screenshot({ path: testInfo.outputPath('jobs-lifecycle-narrow.png'), fullPage: true });
  expect(app.requests.filter(r => r.method === 'jobs.stop')).toHaveLength(0);
  expect(app.pageErrors).toEqual([]);
});

test('completion drains paused output then stops log polling while history stays fresh', async ({ page, context }, testInfo) => {
  await context.grantPermissions(['clipboard-read', 'clipboard-write']);
  await mount(page);
  await page.getByRole('button', { name: 'Pause', exact: true }).click();
  app.write('x'.repeat(65536 * 9) + '\nCOMPLETED WHILE PAUSED\n');
  app.child.stdin.end();
  const output = page.getByRole('region', { name: 'Job output' });
  await expect(page.locator('.jobs-detail-title')).toContainText('Completed');
  await expect(page.getByRole('group', { name: 'In progress', exact: true })).toHaveCount(0);
  await expect(page.getByRole('group', { name: 'History', exact: true }).locator('.jobs-row.selected')).toContainText('Watch build output');
  await expect(output).toContainText('COMPLETED WHILE PAUSED');
  await expect(page.locator('.jobs-output-note')).toContainText('Output ended');
  await expect(page.getByRole('button', { name: /^(Stop job|Pause|Follow output)$/ })).toHaveCount(0);
  const timing = page.locator('.jobs-detail-meta').filter({ hasText: 'Ended' });
  const finalTiming = await timing.textContent();
  expect(finalTiming).toContain('Total');
  const reads = app.requests.filter(r => r.method === 'jobs.read').length;
  const lists = app.requests.filter(r => r.method === 'jobs.list').length;
  await expect.poll(() => app.requests.filter(r => r.method === 'jobs.list').length).toBeGreaterThan(lists + 1);
  expect(app.requests.filter(r => r.method === 'jobs.read')).toHaveLength(reads);
  await expect(timing).toHaveText(finalTiming);
  await page.getByRole('button', { name: 'Copy tail command', exact: true }).click();
  expect(await page.evaluate(() => navigator.clipboard.readText())).not.toContain(' -f ');
  await page.getByRole('button', { name: 'Reload tail', exact: true }).click();
  await expect(output).toContainText('COMPLETED WHILE PAUSED');
  await expect(page.locator('.jobs-output-note')).toContainText('Output ended');
  expect(app.requests.filter(r => r.method === 'jobs.read').length).toBeGreaterThan(reads);
  await page.setViewportSize({ width: 1000, height: 850 });
  await expect.poll(() => page.locator('.jobs-panel').evaluate(el => el.scrollWidth <= el.clientWidth + 1)).toBe(true);
  await page.screenshot({ path: testInfo.outputPath('jobs-completed-narrow.png'), fullPage: true });
  expect(app.pageErrors).toEqual([]);
});

test('interrupted jobs drain final diagnostics despite stale persisted byte counts', async ({ page }) => {
  await mount(page);
  await page.getByRole('button', { name: 'Pause', exact: true }).click();
  const original = app.replyFor.bind(app);
  app.replyFor = async request => {
    const reply = await original(request);
    if (request.method === 'jobs.list') {
      for (const view of reply.jobs) {
        if (view.job.state.kind === 'interrupted') view.job.output_bytes = 1;
      }
    }
    return reply;
  };
  app.write('FINAL DIAGNOSTICS BEFORE ENGINE CRASH\n');
  await expect.poll(() => readFileSync(app.livePath, 'utf8')).toContain('FINAL DIAGNOSTICS');
  app.child.once('close', () => {
    app.jobs[0].job.state = { kind: 'interrupted' };
    app.jobs[0].job.finished_at_ms = null;
  });
  app.child.kill();
  await expect(page.locator('.jobs-detail-title')).toContainText('Interrupted');
  await expect(page.getByRole('region', { name: 'Job output' })).toContainText('FINAL DIAGNOSTICS BEFORE ENGINE CRASH');
  await expect(page.locator('.jobs-output-note')).toHaveText('Output ended');
  const reads = app.requests.filter(r => r.method === 'jobs.read').length;
  const lists = app.requests.filter(r => r.method === 'jobs.list').length;
  await expect.poll(() => app.requests.filter(r => r.method === 'jobs.list').length).toBeGreaterThan(lists + 1);
  expect(app.requests.filter(r => r.method === 'jobs.read')).toHaveLength(reads);
  expect(app.pageErrors).toEqual([]);
});
