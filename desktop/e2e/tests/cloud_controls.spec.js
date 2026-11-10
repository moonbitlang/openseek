import { test, expect } from './support/test.js';
import { CloudHarness, sessionA } from './support/cloud_harness.js';

function controls(app, operation) {
  return app.requests.filter(request => request.method === 'POST')
    .filter(request => operation === 'queue' ? request.path.endsWith('/queue')
      : request.path.endsWith('/commands') && JSON.parse(request.body).command.command === (operation === 'stop' ? 'cancel' : operation))
    .map(request => { const body = JSON.parse(request.body); return body.command ? { task_id: body.task_id, ...body.command } : body; });
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

test('Cloud Stop waits for termination and preserves the editable draft', async ({ page }) => {
  const app = await running(page);
  const task = app.controlState(sessionA).task_id;
  await page.locator('#task').fill('Keep this next draft');
  await page.locator('#stop').click();
  await expect.poll(() => controls(app, 'stop')).toEqual([{ task_id: task, command: 'cancel' }]);
  await expect(page.locator('#stop')).toBeDisabled();
  await expect(page.locator('.composer')).toContainText('Stopping…');
  await expect(page.locator('#task')).toBeEnabled();
  await page.locator('#task').fill('Still editable while stopping');
  // The engine can complete normally in a cancellation race. Its actual
  // terminal status, rather than the accepted Stop, determines the result.
  await app.finishTask(sessionA, 'completed');
  await expect(page.locator('#stop')).toHaveCount(0);
  await expect(page.locator('#task')).toHaveValue('Still editable while stopping');
  expect(app.device.pageErrors).toEqual([]);
});

