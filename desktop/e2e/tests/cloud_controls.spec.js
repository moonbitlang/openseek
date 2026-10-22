import { test, expect } from '@playwright/test';
import { CloudHarness, sessionA, sessionB } from './support/cloud_harness.js';

function deferred() {
  let resolve;
  const promise = new Promise(done => { resolve = done; });
  return { promise, resolve };
}

function controls(app, operation) {
  return app.requests.filter(request => request.method === 'POST' && request.path.endsWith(`/${operation}`))
    .map(request => JSON.parse(request.body));
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

async function followup(page, content, mode) {
  await page.locator('#task').fill(content);
  const choice = page.getByRole('button', { name: 'Follow-up action', exact: true });
  await choice.click();
  await page.getByRole('option', { name: mode === 'queue' ? /^Queue next/ : /^Steer now/ }).click();
  await page.locator('#send').click();
}

test('Cloud Stop waits for termination and preserves the editable draft', async ({ page }, testInfo) => {
  const app = await running(page);
  const task = app.controlState(sessionA).task_id;
  await page.locator('#task').fill('Keep this next draft');
  await page.locator('#stop').click();
  await expect.poll(() => controls(app, 'stop')).toEqual([{ task_id: task }]);
  await expect(page.locator('#stop')).toBeDisabled();
  await expect(page.locator('.composer')).toContainText('Stopping…');
  await expect(page.locator('#task')).toBeEnabled();
  await page.locator('#task').fill('Still editable while stopping');
  const path = testInfo.outputPath('cloud-stopping.png');
  await page.locator('.composer').screenshot({ path });
  // The engine can complete normally in a cancellation race. Its actual
  // terminal status, rather than the accepted Stop, determines the result.
  await app.finishTask(sessionA, 'completed');
  await expect(page.locator('#stop')).toHaveCount(0);
  await expect(page.locator('#task')).toHaveValue('Still editable while stopping');
  expect(app.controlState(sessionA).data.status).toBe('idle');
  expect(app.device.pageErrors).toEqual([]);
});

test('Cloud Steer settles a receipt before HTTP acceptance without clearing later typing', async ({ page }) => {
  const app = await running(page);
  const held = deferred();
  app.pauseControl = held.promise;
  await followup(page, 'Inspect the login first', 'steer');
  await expect.poll(() => controls(app, 'steer').length).toBe(1);
  const request = controls(app, 'steer')[0];
  expect(request.task_id).toBe(app.controlState(sessionA).task_id);
  expect(request.content).toBe('Inspect the login first');
  await page.locator('#task').fill('A later independent draft');
  await app.emitSessionEvent(sessionA, 'steer_applied', { submission_id: request.submission_id, kind: 'prompt', content: request.content });
  const accepted = page.waitForResponse(response => response.request().method() === 'POST' && new URL(response.url()).pathname.endsWith('/steer'));
  held.resolve();
  await (await accepted).finished();
  await expect(page.locator('.pending-steer-row')).toHaveCount(0);
  await expect(page.locator('#task')).toHaveValue('A later independent draft');
  await expect(page.locator('#stop')).toBeEnabled();
  expect(controls(app, 'steer')).toHaveLength(1);
});

test('Cloud dropped Steer restores its input and preserves a newer draft', async ({ page }) => {
  const app = await running(page);
  await followup(page, 'Keep this rejected instruction', 'steer');
  await expect.poll(() => controls(app, 'steer').length).toBe(1);
  const request = controls(app, 'steer')[0];
  await expect(page.locator('.pending-steer-row')).toContainText('Keep this rejected instruction');
  await page.locator('#task').fill('Newer input');
  await app.emitSessionEvent(sessionA, 'steer_dropped', { submission_id: request.submission_id, content: request.content });
  await expect(page.locator('#task')).toHaveValue(/Keep this rejected instruction/);
  await expect(page.locator('#task')).toHaveValue(/Newer input/);
  await expect(page.locator('.pending-steer-row')).toHaveCount(0);
  expect(controls(app, 'steer')).toHaveLength(1);
});

test('Cloud Steer network failure stays unknown until a server receipt resolves it', async ({ page }) => {
  const app = await running(page);
  const held = deferred();
  app.pauseControl = held.promise;
  await followup(page, 'An uncertain submission', 'steer');
  await expect.poll(() => controls(app, 'steer').length).toBe(1);
  const request = controls(app, 'steer')[0];
  await page.locator('#task').fill('Draft after submission');
  // The server accepted the input, but the client never receives the HTTP
  // result. A missing receipt is not an explicit rejection.
  await app.publishControl(sessionA, { steers: [{ submission_id: request.submission_id, status: 'unknown' }] });
  app.controlOffline = true;
  const reconciled = page.waitForResponse(response => response.request().method() === 'GET' && new URL(response.url()).pathname.endsWith('/control'));
  held.resolve();
  await (await reconciled).finished();
  await expect(page.locator('.pending-steer-row')).toContainText('An uncertain submission');
  await expect(page.locator('#task')).toHaveValue('Draft after submission');
  app.controlOffline = false;
  await app.emitSessionEvent(sessionA, 'steer_applied', { submission_id: request.submission_id, kind: 'prompt', content: request.content });
  await expect(page.locator('.pending-steer-row')).toHaveCount(0);
  await expect(page.locator('#task')).toHaveValue('Draft after submission');
  expect(controls(app, 'steer')).toHaveLength(1);
});
