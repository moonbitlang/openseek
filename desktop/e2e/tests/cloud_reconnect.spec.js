import { test, expect } from './support/test.js';
import { CloudHarness, sessionA } from './support/cloud_harness.js';

function deferred() {
  let resolve;
  const promise = new Promise(done => { resolve = done; });
  return { promise, resolve };
}

function observations(app, session = sessionA) {
  return app.requests.filter(request => request.method === 'GET' && request.path === `/v1/sessions/${session}/events`);
}

async function running(page) {
  const app = new CloudHarness(page);
  app.manualTasks = true;
  await app.install();
  await app.goto();
  await app.open();
  await page.locator('#task').fill('Start a Cloud turn');
  await page.locator('#send').click();
  await expect(page.locator('#stop')).toBeEnabled();
  await expect(page.locator('#task')).toHaveValue('');
  return app;
}

test('Cloud reconnects after EOF without resubmitting input', async ({ page }) => {
  const app = await running(page);
  await app.emitSessionEvent(sessionA, 'assistant_message', { content: 'Already confirmed.' });
  await expect(page.locator('#transcript')).toContainText('Already confirmed.');
  await page.locator('#task').fill('Keep my draft');
  const next = deferred();
  app.pauseSessionEvents = next.promise;
  await app.disconnectSession(sessionA);
  await expect(page.locator('.composer-banner')).toContainText('reconnecting');
  await expect(page.locator('#transcript')).not.toContainText('Cloud is unreachable');
  await expect(page.locator('#task')).toBeEnabled();
  await expect(page.locator('#send')).toBeDisabled();
  await expect.poll(() => observations(app).length).toBe(2);
  app.pauseSessionEvents = null;
  next.resolve();
  await expect(page.locator('.composer-banner')).not.toBeVisible();
  await expect(page.locator('#stop')).toBeEnabled();
  await app.emitSessionEvent(sessionA, 'assistant_delta', { content: 'Live after reconnection' });
  await expect(page.locator('#transcript')).toContainText('Live after reconnection');
  await expect(page.locator('#transcript').getByText('Already confirmed.', { exact: true })).toHaveCount(1);
  await expect(page.locator('#task')).toHaveValue('Keep my draft');
  expect(app.postCount).toBe(1);
  expect(app.requests.filter(request => request.method === 'POST' && /\/(stop|steer|queue)$/.test(request.path))).toEqual([]);
  expect(await page.evaluate(() => window.cloudSessionStreams.get('11111111-1111-4111-8111-111111111111')?.size)).toBe(1);
  expect(app.device.pageErrors).toEqual([]);
});
