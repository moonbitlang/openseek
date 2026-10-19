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

async function expandHistory(page) {
  const toggle = page.locator('.jobs-history-toggle');
  if (await toggle.getAttribute('aria-expanded') === 'false') await toggle.click();
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
  await expandHistory(page);
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
  await expect(page.getByRole('button', { name: /Earlier failing test run/ })).toHaveCount(0);
  await expandHistory(page);
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
  await expandHistory(page);
  await page.getByRole('button', { name: 'Load older jobs', exact: true }).click();
  await expandHistory(page);
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
  await expandHistory(page);
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
  await expect(page.locator('.jobs-history-toggle')).toHaveAttribute('aria-expanded', 'false');
  await expandHistory(page);
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


test('history stays folded by default while active jobs remain visible across refreshes', async ({ page }, testInfo) => {
  await mount(page);
  const toggle = page.locator('.jobs-history-toggle');
  const active = page.getByRole('group', { name: 'In progress', exact: true });
  const oldJob = page.getByRole('button', { name: /Earlier failing test run/ });
  await expect(toggle).toHaveAttribute('aria-expanded', 'false');
  await expect(active.getByRole('button', { name: /Watch build output/ })).toBeVisible();
  await expect(oldJob).toHaveCount(0);
  await page.locator('.jobs-panel').getByRole('button', { name: 'Refresh', exact: true }).click();
  await expect(toggle).toHaveAttribute('aria-expanded', 'false');
  await toggle.focus(); await page.keyboard.press('Enter');
  await expect(oldJob).toBeVisible();
  const lists = app.requests.filter(r => r.method === 'jobs.list').length;
  await expect.poll(() => app.requests.filter(r => r.method === 'jobs.list').length).toBeGreaterThan(lists);
  await expect(toggle).toHaveAttribute('aria-expanded', 'true');
  await oldJob.click();
  await expect(page.getByRole('region', { name: 'Job output' })).toContainText('old failed job output');
  await toggle.click();
  await expect(oldJob).toHaveCount(0);
  await expect(active.getByRole('button', { name: /Watch build output/ })).toBeVisible();
  await active.getByRole('button', { name: /Watch build output/ }).click();
  await page.screenshot({ path: testInfo.outputPath('jobs-history-folded.png'), fullPage: true });
  // A completing selection remains readable without opening its History group.
  await page.getByRole('button', { name: 'Stop job', exact: true }).click();
  await expect(page.locator('.jobs-detail-title')).toContainText('Stopped');
  await expect(toggle).toHaveAttribute('aria-expanded', 'false');
  expect(app.pageErrors).toEqual([]);
});

test('history-only sessions wait for explicit selection before loading a log', async ({ page }) => {
  app = new BackgroundJobsHarness(page);
  const live = app.jobs.shift();
  await app.install(); await app.goto(); await app.openSession(); await app.openJobs();
  await expect(page.locator('.jobs-history-toggle')).toHaveAttribute('aria-expanded', 'false');
  await expect(page.locator('.jobs-detail')).toHaveCount(0);
  expect(app.requests.filter(r => r.method === 'jobs.read')).toHaveLength(0);
  await expandHistory(page);
  await page.getByRole('button', { name: /Earlier failing test run/ }).click();
  await expect(page.getByRole('region', { name: 'Job output' })).toContainText('old failed job output');
  app.jobs.unshift(live);
  await expect(page.getByRole('group', { name: 'In progress', exact: true })).toBeVisible();
  await expect(page.locator('.jobs-detail-title')).toContainText('Failed');
  await expect(page.locator('.jobs-history-toggle')).toHaveAttribute('aria-expanded', 'true');
  expect(app.pageErrors).toEqual([]);
});

test('font size settings scale Jobs with the transcript', async ({ page }, testInfo) => {
  await mount(page);
  const jobs = page.locator('.jobs-panel');
  const prose = page.locator('.transcript .msg-content').first();
  const command = jobs.locator('.jobs-command').first();
  const output = jobs.locator('.jobs-output pre');
  await expect(command).toHaveCSS('font-size', '14px');
  await expect(jobs.locator('.jobs-group-title').first()).toHaveCSS('font-size', '13px');
  await expect(jobs.locator('.jobs-group-count').first()).toHaveCSS('font-size', '12px');
  await expect(command).toHaveCSS('font-family', await prose.evaluate(el => getComputedStyle(el).fontFamily));
  await expect(jobs.locator('.jobs-row-meta').first()).toHaveCSS('font-size', '12px');
  await expect(output).toHaveCSS('font-size', '13px');
  await page.screenshot({ path: testInfo.outputPath('jobs-font-default.png'), fullPage: true });

  await page.getByRole('button', { name: 'Settings', exact: true }).click();
  await page.getByRole('slider', { name: 'Font size', exact: true }).fill('18');
  await app.openSession();
  await expect(prose).toHaveCSS('font-size', '18px');
  await expect(command).toHaveCSS('font-size', '18px');
  await expect(jobs.locator('.jobs-group-title').first()).toHaveCSS('font-size', '17px');
  await expect(jobs.locator('.jobs-group-count').first()).toHaveCSS('font-size', '16px');
  await expect(jobs.locator('.jobs-row-meta').first()).toHaveCSS('font-size', '16px');
  await expect(jobs.locator('.jobs-action').first()).toHaveCSS('font-size', '17px');
  await expect(output).toHaveCSS('font-size', '17px');
  await expect(output).toHaveCSS('font-family', /ui-monospace/);
  await expect(jobs.locator('.jobs-full-command')).toHaveCSS('font-family', await output.evaluate(el => getComputedStyle(el).fontFamily));
  await expect(prose).not.toHaveCSS('font-family', /Menlo/);

  await page.reload();
  await app.openSession();
  await app.openJobs();
  await expect(command).toHaveCSS('font-size', '18px');
  await expect(output).toHaveCSS('font-size', '17px');
  await expect(output).toHaveCSS('font-family', /ui-monospace/);
  await page.setViewportSize({ width: 1000, height: 850 });
  await expect.poll(() => jobs.evaluate(el => el.scrollWidth <= el.clientWidth + 1)).toBe(true);
  await page.screenshot({ path: testInfo.outputPath('jobs-font-large-light.png'), fullPage: true });
  await page.emulateMedia({ colorScheme: 'dark' });
  await page.screenshot({ path: testInfo.outputPath('jobs-font-large-dark.png'), fullPage: true });

  await page.getByRole('button', { name: 'Settings', exact: true }).click();
  await page.getByRole('slider', { name: 'Font size', exact: true }).fill('12');
  await app.openSession();
  await expect(command).toHaveCSS('font-size', '12px');
  await expect(output).toHaveCSS('font-size', '11px');
  await page.setViewportSize({ width: 390, height: 844 });
  await expect(page.locator('.sidebar-toggle')).toHaveAttribute('aria-label', 'Show sidebar');
  await expect.poll(() => jobs.evaluate(el => el.scrollWidth <= el.clientWidth + 1)).toBe(true);
  await page.screenshot({ path: testInfo.outputPath('jobs-font-small-narrow.png'), animations: 'disabled' });
  expect(app.pageErrors).toEqual([]);
});

test('background program calls update live and retain edit diffs after reload', async ({ page }, testInfo) => {
  app = new BackgroundJobsHarness(page);
  const job = app.jobs[0].job;
  job.data = { ptc_calls: [
    { name: 'edit', arguments: { path: 'note.txt', start_line: 1, old_string: 'before', new_string: 'after' }, status: 'running' },
  ] };
  await app.install(); await app.goto(); await app.openSession(); await app.openJobs();
  const trace = page.locator('.job-program-calls');
  await trace.locator(':scope > summary').click();
  await expect(trace.locator('.tool-status-spinner')).toBeVisible();
  job.data.ptc_calls[0].status = 'done';
  job.data.ptc_calls[0].result = { content: 'Updated note.txt', is_error: false };
  job.revision++;
  await page.locator('.jobs-panel').getByRole('button', { name: 'Refresh', exact: true }).click();
  await expect(trace.getByRole('img', { name: 'Tool succeeded' })).toBeVisible();
  await expect(trace.locator('.tool-status-spinner')).toHaveCount(0);
  await page.reload(); await app.openSession(); await app.openJobs();
  await trace.locator(':scope > summary').click();
  const edit = trace.locator('details.tool-call').first();
  await edit.locator(':scope > summary').click();
  await expect(edit).toContainText('before');
  await expect(edit).toContainText('after');
  await expect(edit.getByRole('img', { name: 'Tool succeeded' })).toBeVisible();
  await page.screenshot({ path: testInfo.outputPath('background-program-calls.png') });
  job.cleanup_error = 'PTC script exited with unfinished tool calls';
  job.state = { kind: 'exited', code: 0 };
  job.revision++;
  await page.locator('.jobs-panel').getByRole('button', { name: 'Refresh', exact: true }).click();
  await expect(page.locator('.jobs-detail-title')).toContainText('Failed · cleanup incomplete');
  await expect(page.getByRole('alert')).toContainText('unfinished tool calls');
  job.cleanup_error = null;
  job.state = { kind: 'interrupted' };
  job.data.ptc_calls[0] = { name: 'edit', arguments: { path: 'note.txt' }, status: 'running' };
  job.revision++;
  await page.reload(); await app.openSession(); await app.openJobs();
  await expandHistory(page);
  await page.getByRole('button', { name: /Watch build output/ }).click();
  await trace.locator(':scope > summary').click();
  await expect(trace.getByRole('img', { name: 'Tool failed' })).toBeVisible();
  await expect(trace.locator('.tool-status-spinner')).toHaveCount(0);
  expect(app.pageErrors).toEqual([]);
});

test('subagent jobs read as agents with their outcome, spend and transcript', async ({ page }, testInfo) => {
  app = new BackgroundJobsHarness(page);
  const live = app.view('runtime-new', 'agent-live', app.oldPath, { kind: 'running' });
  live.job.command = 'openseek run --kind explore --session session-1-sr-1';
  live.job.subagent = {
    kind: 'explore', label: 'where is the parser built?', session: 'session-1-sr-1',
    launch: { kind: 'direct' }, workspace: { kind: 'in_place' },
  };
  const done = app.view('runtime-new', 'agent-done', app.oldPath, { kind: 'exited', code: 0 });
  done.job.command = 'openseek run --kind review --session session-1-sr-2';
  done.job.subagent = {
    kind: 'review', label: 'audit the CSV change', session: 'session-1-sr-2',
    launch: { kind: 'direct' }, workspace: { kind: 'in_place' },
    outcome: { kind: 'captured' },
    usage: { kind: 'known', steps: 12, prompt_tokens: 1000, completion_tokens: 200, source: 'result' },
    report: { kind: 'stored' },
  };
  app.jobs.splice(0, app.jobs.length, live, done);
  await app.install(); await app.goto(); await app.openSession(); await app.openJobs();
  const active = page.getByRole('group', { name: 'In progress', exact: true });
  await expect(active.locator('.jobs-row')).toHaveCount(1);
  await expect(active.locator('.jobs-command')).toHaveText('explore: where is the parser built?');
  await expandHistory(page);
  const history = page.getByRole('group', { name: 'History', exact: true });
  const row = history.locator('.jobs-row');
  await expect(row.locator('.jobs-command')).toHaveText('review: audit the CSV change');
  await expect(row.locator('.jobs-status')).toHaveText('Reported');
  await expect(row.locator('.jobs-row-meta')).toContainText('12 steps · 1200 tokens');
  await row.click();
  await expect(page.locator('.jobs-detail')).toContainText('Session: session-1-sr-2');
  await expect(page.getByRole('button', { name: 'Open transcript', exact: true })).toBeVisible();
  await page.screenshot({ path: testInfo.outputPath('jobs-subagents-light.png'), fullPage: true });
  await page.emulateMedia({ colorScheme: 'dark' });
  await page.screenshot({ path: testInfo.outputPath('jobs-subagents-dark.png'), fullPage: true });
  expect(app.pageErrors).toEqual([]);
});

test('a worker job shows its worktree, where its changes stand and why', async ({ page }, testInfo) => {
  app = new BackgroundJobsHarness(page);
  const worktree = (state) => ({
    name: 'csv-quotes', path: '/work/demo/.worktrees/csv-quotes',
    branch: 'openseek/csv-quotes--1a2b3c4d-sr-3', base: '5e1f0a7', allowed_paths: ['src/csv'], state,
  });
  const committed = app.view('runtime-new', 'agent-worker', app.oldPath, { kind: 'exited', code: 0 });
  committed.job.command = 'openseek run --kind worker --session session-1-sr-3';
  committed.job.subagent = {
    kind: 'worker', label: 'handle escaped quotes', session: 'session-1-sr-3',
    launch: { kind: 'direct' },
    workspace: { kind: 'worktree', worktree: worktree({ kind: 'committed', commit: '9c41d2e8f0b7a6c5d4e3f2a1b0c9d8e7f6a5b4c3' }) },
    outcome: { kind: 'captured' },
    usage: { kind: 'known', steps: 21, prompt_tokens: 3000, completion_tokens: 400, source: 'result' },
    report: { kind: 'stored' },
  };
  const rejected = app.view('runtime-new', 'agent-stray', app.oldPath, { kind: 'exited', code: 0 });
  rejected.job.command = 'openseek run --kind worker --session session-1-sr-4';
  rejected.job.subagent = {
    kind: 'worker', label: 'rename the reader', session: 'session-1-sr-4',
    launch: { kind: 'direct' },
    workspace: { kind: 'worktree', worktree: { ...worktree({ kind: 'unmergeable', defects: ['out-of-scope changes (allowed: src/csv): src/main.mbt'] }), name: 'reader', path: '/work/demo/.worktrees/reader', branch: 'openseek/reader--1a2b3c4d-sr-4' } },
    outcome: { kind: 'captured' },
    report: { kind: 'stored' },
  };
  app.jobs.splice(0, app.jobs.length, committed, rejected);
  await app.install(); await app.goto(); await app.openSession(); await app.openJobs();
  await expandHistory(page);
  const history = page.getByRole('group', { name: 'History', exact: true });
  await history.locator('.jobs-row', { hasText: 'worker: handle escaped quotes' }).click();
  const detail = page.locator('.jobs-detail');
  await expect(detail).toContainText('Worktree csv-quotes · branch openseek/csv-quotes--1a2b3c4d-sr-3');
  await expect(detail.locator('.jobs-worktree-state')).toHaveText('Worktree: committed 9c41d2e8f0 on its branch, ready to take');
  await expect(detail).toContainText('/work/demo/.worktrees/csv-quotes');
  await expect(page.getByRole('button', { name: 'Copy worktree path', exact: true })).toBeVisible();
  await page.screenshot({ path: testInfo.outputPath('jobs-worker-committed.png'), fullPage: true });
  await history.locator('.jobs-row', { hasText: 'worker: rename the reader' }).click();
  await expect(detail.locator('.jobs-worktree-state')).toHaveText('Worktree: not mergeable; kept for inspection');
  await expect(detail.locator('.jobs-worktree-reason')).toHaveText('out-of-scope changes (allowed: src/csv): src/main.mbt');
  await page.screenshot({ path: testInfo.outputPath('jobs-worker-unmergeable.png'), fullPage: true });
  await page.emulateMedia({ colorScheme: 'dark' });
  await page.screenshot({ path: testInfo.outputPath('jobs-worker-unmergeable-dark.png'), fullPage: true });
  expect(app.pageErrors).toEqual([]);
});
