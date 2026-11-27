import { test, expect } from './support/test.js';
import { authOrigin, cloudOrigin, CloudHarness, sessionA } from './support/cloud_harness.js';

test('Cloud Jobs lists the current instance and stops only the selected job', async ({ page }) => {
  const app = new CloudHarness(page);
  await app.install();
  let live = false;
  const jobs = ['build', 'watch'].map(id => ({
    schema_version: 1, generation: 'runtime-a', id, revision: 1, command: id,
    state: { kind: 'running' }, started_at_ms: 1000, backgrounded_at_ms: 1000,
    output_persistent: false, output_bytes: 0, output_chars: 0,
    output_truncated: false, invalid_utf8: false,
  }));
  const stops = [];
  let snapshots = 0;
  await page.route(`${cloudOrigin}/v1/sessions/${sessionA}/commands`, async route => {
    if (route.request().method() !== 'POST') return route.fallback();
    const { command } = route.request().postDataJSON();
    const headers = { 'Access-Control-Allow-Origin': authOrigin };
    if (command.command === 'jobs_snapshot') {
      snapshots++;
      if (!live) return route.fulfill({ status: 409, headers, json: { accepted: false, error: 'instance_not_running' } });
      // SSE may precede the HTTP acknowledgement.
      await app.emitSessionEvent(sessionA, 'jobs_snapshot', { request_id: command.request_id, jobs });
    } else if (command.command === 'job_stop') {
      stops.push(command);
    } else {
      return route.fallback();
    }
    return route.fulfill({ status: 202, headers, json: { accepted: true } });
  });
  await app.goto();
  await app.open();
  await page.getByRole('button', { name: 'Show panel', exact: true }).click();
  await page.locator('.dock-launcher').getByRole('button', { name: /^Jobs / }).click();
  const panel = page.locator('.jobs-panel');
  await expect.poll(() => snapshots).toBeGreaterThan(0);
  await expect(panel.locator('.jobs-empty h3')).toHaveText('No background jobs yet');
  live = true;
  await panel.getByRole('button', { name: 'Refresh', exact: true }).click();
  await panel.locator('.jobs-row').filter({ hasText: 'watch' }).click();
  const stop = panel.locator('.jobs-stop');
  await stop.click();
  await expect.poll(() => stops.length).toBe(1);
  const { request_id, generation, job_id } = stops[0];
  expect([generation, job_id]).toEqual(['runtime-a', 'watch']);
  await app.emitSessionEvent(sessionA, 'job_stop_result', { request_id: 'unrelated', generation, job_id, outcome: 'stopped' });
  await expect(stop).toBeDisabled();
  jobs[1].state = { kind: 'stopped', reason: 'user' };
  await app.emitSessionEvent(sessionA, 'job_stop_result', { request_id, generation, job_id, outcome: 'stopped' });
  await expect(panel.locator('.jobs-summary')).toContainText('1 in progress');
  await expect(panel.locator('.jobs-detail-title')).toContainText('Stopped');
  expect(app.requests.filter(request => request.method === 'POST' && request.path === '/v1/sessions')).toHaveLength(0);
});
