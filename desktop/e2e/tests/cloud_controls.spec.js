import { test, expect } from './support/test.js';
import { CloudHarness, sessionA, sessionB } from './support/cloud_harness.js';

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

async function followup(page, content, mode) {
  await page.locator('#task').fill(content);
  const choice = page.getByRole('button', { name: 'Follow-up action', exact: true });
  await choice.click();
  await page.getByRole('option', { name: mode === 'queue' ? /^Queue next/ : /^Steer now/ }).click();
  await page.locator('#send').click();
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

test('Cloud uses the shared queue editor, withdrawal and conversion to Steer', async ({ page }) => {
  const app = await running(page);
  await followup(page, 'First queued input', 'queue');
  const rows = page.locator('.queued-input-row');
  await expect(rows).toContainText('First queued input');
  await expect(page.locator('#task')).toHaveValue('');
  expect(app.postCount).toBe(1);
  const first = controls(app, 'queue')[0];
  await rows.getByTitle('Edit', { exact: true }).click();
  await expect(page.locator('#task')).toHaveValue('First queued input');
  await page.locator('#task').fill('Edited queued input');
  await page.getByTitle('Save queued message', { exact: true }).click();
  await expect(rows).toContainText('Edited queued input');
  await expect(page.locator('#task')).toHaveValue('');
  expect(controls(app, 'queue')[1]).toMatchObject({ task_id: first.task_id, action: 'edit', id: first.id, content: 'Edited queued input' });
  await followup(page, 'Withdraw this input', 'queue');
  await expect(rows).toHaveCount(2);
  await expect(page.locator('#task')).toHaveValue('');
  await rows.filter({ hasText: 'Withdraw this input' }).getByTitle('Delete', { exact: true }).click();
  await expect(rows).toHaveCount(1);
  await rows.getByTitle('Steer', { exact: true }).click();
  await expect(rows).toHaveCount(0);
  await expect(page.locator('.pending-steer-row')).toContainText('Edited queued input');
  expect(controls(app, 'queue').at(-1)).toEqual({ task_id: first.task_id, action: 'steer', id: first.id });
  await app.emitSessionEvent(sessionA, 'steer_dropped', { submission_id: first.id, content: 'Edited queued input' });
  await expect(page.locator('#task')).toHaveValue('Edited queued input');
  await expect(rows).toHaveCount(0);
});

test('Cloud conversation switching restores drafts and paused queue controls', async ({ page }) => {
  const app = await running(page);
  await followup(page, 'Retained after stopping', 'queue');
  await expect(page.locator('.queued-input-row')).toBeVisible();
  await page.locator('#task').fill('Draft belonging to A');
  await app.open(sessionB);
  await expect(page.locator('#stop')).toHaveCount(0);
  await expect(page.locator('.queued-input-row')).toHaveCount(0);
  await page.locator('#task').fill('Draft belonging to B');
  await app.finishTask(sessionA, 'failed');
  await app.open(sessionA);
  await expect(page.locator('#stop')).toHaveCount(0);
  await expect(page.locator('#task')).toHaveValue('Draft belonging to A');
  const row = page.locator('.queued-input-row');
  await expect(row).toContainText('Retained after stopping');
  await expect(row.getByTitle('Edit', { exact: true })).toBeEnabled();
  await expect(row.getByTitle('Delete', { exact: true })).toBeEnabled();
  await expect(row.getByTitle('Steer', { exact: true })).toBeDisabled();
  await page.locator('#send').click();
  await expect(page.locator('#stop')).toBeEnabled();
  const task = app.controlState(sessionA).task_id;
  await expect(row.getByTitle('Edit', { exact: true })).toBeEnabled();
  await app.finishTask(sessionA);
  const queued = app.controlState(sessionA).data.queue[0];
  await app.emitSessionEvent(sessionA, 'task_started', { submission_id: queued.id, previous_task_id: task }, { task: 'queued-next-task' });
  await expect(page.locator('#stop')).toBeEnabled();
  await expect(row).toHaveCount(0);
  await app.open(sessionB);
  await expect(page.locator('#task')).toHaveValue('Draft belonging to B');
});
