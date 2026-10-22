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

