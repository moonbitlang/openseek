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
  const heartbeat = page.locator('#stream > .transcript-run-status:last-child');
  await expect(heartbeat).toHaveText('Stopping…');
  await expect(page.locator('#task')).toBeEnabled();
  await page.locator('#task').fill('Still editable while stopping');
  // The engine can complete normally in a cancellation race. Its actual
  // terminal status, rather than the accepted Stop, determines the result.
  await app.finishTask(sessionA, 'completed');
  await expect(page.locator('#stop')).toHaveCount(0);
  await expect(heartbeat).toHaveCount(0);
  await expect(page.locator('#task')).toHaveValue('Still editable while stopping');
  expect(app.device.pageErrors).toEqual([]);
});

for (const state of ['running', 'paused']) {
  test(`Cloud saves /feedback as queued text while ${state}`, async ({ page }) => {
    const app = await running(page);
    await app.publishControl(sessionA, { queue: [{ id: 'queued-1', content: 'Original message' }] });
    if (state === 'paused') {
      await app.finishTask(sessionA, 'cancelled');
      await expect(page.locator('#stop')).toHaveCount(0);
    }
    const queued = page.locator('.queued-input-row');
    await queued.getByTitle('Edit', { exact: true }).click();
    const composer = page.locator('#task');
    await expect(composer).toHaveValue('Original message');
    const edited = '/feedback keep this in the queue';
    await composer.fill(edited);
    const feedback = [];
    await page.route('**/v1/sessions/*/feedback', route => {
      feedback.push(route.request().method());
      return route.fulfill({ status: 201, json: { id: 'unexpected-feedback' } });
    });
    const send = page.locator('#send');
    await expect(send).toHaveAttribute('title', 'Save queued message');
    if (state === 'running') await composer.press('Enter');
    else await send.click();
    await expect(queued).toContainText(edited);
    expect(controls(app, 'queue')).toMatchObject([{ action: 'edit', id: 'queued-1' }]);
    expect(feedback).toEqual([]);
  });
}
