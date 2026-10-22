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

for (const receiptFirst of [true, false]) {
  test(`Cloud Steer settles a receipt ${receiptFirst ? 'before' : 'after'} HTTP acceptance without clearing later typing`, async ({ page }) => {
    const app = await running(page);
    const held = deferred();
    app.pauseControl = receiptFirst ? held.promise : null;
    const accepted = page.waitForResponse(response => response.request().method() === 'POST' && new URL(response.url()).pathname.endsWith('/steer'));
    await followup(page, 'Inspect the login first', 'steer');
    if (!receiptFirst) await (await accepted).finished();
    await expect.poll(() => controls(app, 'steer').length).toBe(1);
    const request = controls(app, 'steer')[0];
    expect(request.task_id).toBe(app.controlState(sessionA).task_id);
    expect(request.content).toBe('Inspect the login first');
    await page.locator('#task').fill('A later independent draft');
    await app.emitSessionEvent(sessionA, 'user', { submission_id: request.submission_id, content: request.content });
    await app.emitSessionEvent(sessionA, 'steer_applied', { submission_id: request.submission_id, kind: 'prompt', content: request.content });
    held.resolve();
    await (await accepted).finished();
    await expect(page.locator('.pending-steer-row')).toHaveCount(0);
    await expect(page.locator('#task')).toHaveValue('A later independent draft');
    await expect(page.locator('#stop')).toBeEnabled();
    expect(controls(app, 'steer')).toHaveLength(1);
    await expect(page.locator('#transcript').getByText(request.content, { exact: true })).toHaveCount(1);
    await app.open(sessionB);
    await app.open(sessionA);
    await expect(page.locator('#transcript').getByText(request.content, { exact: true })).toHaveCount(1);
    await expect(page.locator('#task')).toHaveValue('A later independent draft');
  });
}

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
  await expect(page.locator('#transcript').getByText(request.content, { exact: true })).toHaveCount(0);
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
  await app.emitSessionEvent(sessionA, 'user', { submission_id: request.submission_id, content: request.content });
  await app.emitSessionEvent(sessionA, 'steer_applied', { submission_id: request.submission_id, kind: 'prompt', content: request.content });
  await expect(page.locator('.pending-steer-row')).toHaveCount(0);
  await expect(page.locator('#task')).toHaveValue('Draft after submission');
  expect(controls(app, 'steer')).toHaveLength(1);
});

test('Cloud uses the shared queue editor, withdrawal and conversion to Steer', async ({ page }, testInfo) => {
  const app = await running(page);
  await followup(page, 'First queued input', 'queue');
  const rows = page.locator('.queued-input-row');
  await expect(rows).toContainText('First queued input');
  await expect(page.locator('#task')).toHaveValue('');
  expect(app.histories.get(sessionA).messages.filter(record => record.kind === 'user')).toHaveLength(1);
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
  const path = testInfo.outputPath('cloud-queue.png');
  await page.locator('.composer').screenshot({ path });
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
  await app.emitSessionEvent(sessionA, 'task_started', { submission_id: queued.id, previous_task_id: task }, { task: 'queued-next-task', seq: 1 });
  await expect(page.locator('#stop')).toBeEnabled();
  await expect(row).toHaveCount(0);
  await app.open(sessionB);
  await expect(page.locator('#task')).toHaveValue('Draft belonging to B');
});

test('Cloud late previous-task events cannot stop the next queued turn', async ({ page }) => {
  const app = await running(page);
  await followup(page, 'Run this next', 'queue');
  await expect(page.locator('.queued-input-row')).toBeVisible();
  const previous = app.controlState(sessionA).task_id;
  const queued = app.controlState(sessionA).data.queue[0];
  await app.finishTask(sessionA);
  await app.emitSessionEvent(sessionA, 'task_started', { submission_id: queued.id, previous_task_id: previous }, { task: 'next-task', seq: 1 });
  await expect(page.locator('#stop')).toBeEnabled();
  await app.emitSessionEvent(sessionA, 'task_finished', { status: 'failed', result: { status: 'aborted' } }, { task: previous, seq: 999 });
  await app.emitSessionEvent(sessionA, 'assistant_delta', { content: 'OLD TURN SHOULD NOT APPEAR' }, { task: previous, seq: 1000 });
  await page.locator('#stop').click();
  await expect.poll(() => controls(app, 'stop')).toEqual([{ task_id: 'next-task' }]);
  await expect(page.locator('main')).not.toContainText('OLD TURN SHOULD NOT APPEAR');
  await expect(page.locator('.composer')).toContainText('Stopping…');
});


test('Cloud keeps a pending send and later draft while switching away and back', async ({ page }) => {
  const app = new CloudHarness(page);
  app.manualTasks = true;
  const admission = deferred();
  app.pauseSend = admission.promise;
  await app.install();
  await app.goto();
  await app.open();
  await page.locator('#task').fill('Submitted before switching');
  await page.locator('#send').click();
  await expect.poll(() => app.postCount).toBe(1);
  await page.locator('#task').fill('Later draft for the same conversation');
  await app.open(sessionB);
  await page.locator('#task').fill('Separate B draft');
  await app.open(sessionA);
  await expect(page.locator('#task')).toHaveValue('Later draft for the same conversation');
  admission.resolve();
  await expect(page.locator('#stop')).toBeEnabled();
  await expect(page.locator('#transcript').getByText('Submitted before switching', { exact: true })).toHaveCount(1);
  await expect(page.locator('#task')).toHaveValue('Later draft for the same conversation');
  await app.finishTask();
  await expect(page.locator('#stop')).toHaveCount(0);
  app.pauseSend = null;
  await page.locator('#send').click();
  await expect.poll(() => app.postCount).toBe(2);
  await expect(page.locator('#stop')).toBeEnabled();
  const messages = app.requests.filter(request => request.method === 'POST' && request.path.endsWith('/messages'));
  expect(JSON.parse(messages[1].body)).toEqual({ content: 'Later draft for the same conversation' });
  await app.finishTask();
  await app.open(sessionB);
  await expect(page.locator('#task')).toHaveValue('Separate B draft');
});

for (const status of ['completed', 'failed']) {
  test(`Cloud ${status} terminal still refreshes history after an idle queue snapshot`, async ({ page }) => {
    const app = await running(page);
    const reads = () => app.requests.filter(request => request.method === 'GET' && request.path === `/v1/sessions/${sessionA}/messages`).length;
    const before = reads();
    const refreshed = page.waitForResponse(response => response.request().method() === 'GET' && new URL(response.url()).pathname === `/v1/sessions/${sessionA}/messages`);
    await app.finishTask(sessionA, status);
    await (await refreshed).finished();
    await expect.poll(reads).toBeGreaterThan(before);
    await expect(page.locator('#stop')).toHaveCount(0);
    if (status === 'failed') await expect(page.locator('#transcript')).toContainText('interrupted');
    expect(app.device.pageErrors).toEqual([]);
  });
}

for (const stopped of [false, true]) {
  test(`Cloud paused queue can be edited and withdrawn after ${stopped ? 'Stop' : 'failure'}`, async ({ page }, testInfo) => {
    const app = await running(page);
    await followup(page, 'Keep this queued input', 'queue');
    await expect(page.locator('#task')).toHaveValue('');
    await followup(page, 'Withdraw while paused', 'queue');
    await expect(page.locator('.queued-input-row')).toHaveCount(2);
    const previous = app.controlState(sessionA).task_id;
    if (stopped) {
      await page.locator('#stop').click();
      await expect(page.locator('.composer')).toContainText('Stopping…');
    }
    await app.finishTask(sessionA, 'failed');
    await expect(page.locator('#stop')).toHaveCount(0);
    const rows = page.locator('.queued-input-row');
    await expect(rows.getByTitle('Steer', { exact: true }).first()).toBeDisabled();
    await rows.filter({ hasText: 'Keep this queued input' }).getByTitle('Edit', { exact: true }).click();
    await page.locator('#task').fill('Edited while paused');
    await expect(page.getByTitle('Save queued message', { exact: true })).toBeEnabled();
    await expect(page.locator('#stop')).toHaveCount(0);
    if (!stopped) await page.locator('.composer').screenshot({ path: testInfo.outputPath('cloud-paused-queue-edit.png') });
    await page.getByTitle('Save queued message', { exact: true }).click();
    await expect(rows.filter({ hasText: 'Edited while paused' })).toHaveCount(1);
    await expect(page.locator('#task')).toHaveValue('');
    expect(controls(app, 'queue').at(-1)).toMatchObject({ task_id: previous, action: 'edit', content: 'Edited while paused' });
    await rows.filter({ hasText: 'Withdraw while paused' }).getByTitle('Delete', { exact: true }).click();
    await expect(rows).toHaveCount(1);
    expect(controls(app, 'queue').at(-1)).toMatchObject({ task_id: previous, action: 'withdraw' });
    expect(app.postCount).toBe(1);
    expect(app.controlState(sessionA).data.paused).toBe(true);
    await page.locator('#task').fill('Explicit next prompt');
    await page.locator('#send').click();
    await expect(page.locator('#stop')).toBeEnabled();
    let current = app.controlState(sessionA).task_id;
    expect(current).not.toBe(previous);
    await rows.getByTitle('Edit', { exact: true }).click();
    await page.locator('#task').fill('Edit bound to the new task');
    await page.getByTitle('Save queued message', { exact: true }).click();
    await expect(rows).toContainText('Edit bound to the new task');
    expect(controls(app, 'queue').at(-1)).toMatchObject({ task_id: current, action: 'edit' });
    if (stopped) {
      await page.locator('#stop').click();
      await expect(page.locator('.composer')).toContainText('Stopping…');
    }
    await app.finishTask(sessionA, 'failed');
    await expect(rows).toHaveCount(1);
    await expect(page.locator('#stop')).toHaveCount(0);
    expect(app.controlState(sessionA).data.paused).toBe(true);
    expect(app.postCount).toBe(2);
    await page.locator('#task').fill('Try the explicit prompt again');
    await page.locator('#send').click();
    await expect(page.locator('#stop')).toBeEnabled();
    current = app.controlState(sessionA).task_id;
    await app.finishTask(sessionA);
    const next = app.controlState(sessionA).data.queue[0];
    await app.emitSessionEvent(sessionA, 'task_started', { submission_id: next.id, previous_task_id: current }, { task: 'queued-next-task', seq: 1 });
    await expect(rows).toHaveCount(0);
    await expect(page.locator('#stop')).toBeEnabled();
    expect(app.device.pageErrors).toEqual([]);
  });
}
