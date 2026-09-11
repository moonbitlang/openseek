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
  await expect(page.getByRole('button', { name: 'Stop job', exact: true })).toBeDisabled();
  expect(app.child.signalCode).not.toBeNull();
  expect(readFileSync(app.livePath, 'utf8')).toContain('stderr captured');
  const stop = app.requests.find(r => r.method === 'jobs.stop');
  expect(stop.params).toMatchObject({ scope: { session: 'session-1', workspace: '/workspace' }, generation: 'runtime-new', job_id: 'bg-1' });
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
  await expect(page.getByRole('button', { name: 'Stop job', exact: true })).toBeDisabled();
  await page.waitForTimeout(1400); // The deliberately delayed obsolete reply must arrive.
  await expect(output).not.toContainText('must stay with the live job');
  app.rpcErrors.set('jobs.read', 'Output file is missing: ENOENT');
  await page.getByRole('button', { name: 'Reload tail', exact: true }).click();
  await expect(page.getByRole('alert')).toContainText('Output file is missing');
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
  await page.getByRole('button', { name: 'Load older jobs', exact: true }).click();
  await page.getByRole('button', { name: /Earlier failing test run/ }).click();
  await page.getByRole('button', { name: 'Pause', exact: true }).click();
  const selected = app.jobs.find(v => v.job.generation === 'runtime-old');
  selected.job.state = { kind: 'stopped', reason: 'user' };
  selected.job.revision++;
  await expect(page.locator('.jobs-detail-title')).toContainText('Stopped');
  expect(app.requests.some(r => r.method === 'jobs.list' && r.params.offset === 0 && r.params.selected?.generation === 'runtime-old')).toBe(true);
  expect(app.pageErrors).toEqual([]);
});
