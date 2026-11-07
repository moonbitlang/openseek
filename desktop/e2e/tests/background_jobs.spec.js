import { test, expect } from './support/test.js';
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

test('real background output follows, pauses, resumes, copies its file and stops', async ({ page, context }) => {
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
  await page.emulateMedia({ colorScheme: 'dark' });
  await page.getByRole('button', { name: 'Stop job', exact: true }).click();
  await expect(page.locator('.jobs-detail-title')).toContainText('Stopped');
  await expect(page.getByRole('button', { name: 'Stop job', exact: true })).toHaveCount(0);
  expect(app.requests.filter(request => request.method === 'jobs.stop').map(request => request.params.generation)).toEqual(['runtime-new']);
  expect(readFileSync(app.livePath, 'utf8')).toContain('stderr captured');
  const stop = app.requests.find(r => r.method === 'jobs.stop');
  expect(stop.params).toMatchObject({ scope: { session: 'session-1', workspace: '/workspace' }, generation: 'runtime-new', job_id: app.liveId });
  expect(app.requests.filter(r => r.method === 'jobs.read').every(r => r.params.limit <= 65536)).toBe(true);
  expect(app.pageErrors).toEqual([]);
});

test('historical selection rejects late reads, reports errors and fits a narrow panel', async ({ page }) => {
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
  expect(app.requests.filter(request => request.method === 'jobs.stop').map(request => request.params.generation)).toEqual(['runtime-new']);
  expect(app.pageErrors).toEqual([]);
});

test('UUID suffix collisions expand labels while selection and copying retain full IDs', async ({ page, context }) => {
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
  expect(app.pageErrors).toEqual([]);
});

test('completion drains paused output then stops log polling while history stays fresh', async ({ page, context }) => {
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
  expect(app.pageErrors).toEqual([]);
});

test('background program calls update live and retain edit diffs after reload', async ({ page }) => {
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
