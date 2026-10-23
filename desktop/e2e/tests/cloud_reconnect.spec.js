import { test, expect } from '@playwright/test';
import { CloudHarness, sessionA, sessionB } from './support/cloud_harness.js';

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

for (const nextTurn of [false, true]) {
  test(`Cloud reconnect reconciles ${nextTurn ? 'a subsequent task' : 'a completed task'} before enabling controls`, async ({ page }) => {
    const app = await running(page);
    const oldTask = app.controlState(sessionA).task_id;
    const connection = deferred();
    app.pauseSessionEvents = connection.promise;
    await app.disconnectSession(sessionA);
    await expect.poll(() => observations(app).length).toBe(2);
    await app.emitSessionEvent(sessionA, 'assistant_message', { content: 'Finished while disconnected.' });
    await app.finishTask();
    if (nextTurn) await app.emitSessionEvent(sessionA, 'task_started', { previous_task_id: oldTask }, { task: 'next-task', seq: 1 });
    const history = deferred();
    app.pauseHistory = history.promise;
    const reads = () => app.requests.filter(request => request.method === 'GET' && request.path.endsWith(`/${sessionA}/messages`)).length;
    const before = reads();
    app.pauseSessionEvents = null;
    connection.resolve();
    await expect.poll(reads).toBeGreaterThan(before);
    await expect(page.locator('.composer-banner')).toContainText('reconnecting');
    await expect(page.locator('#send')).toBeDisabled();
    if (nextTurn) await app.emitSessionEvent(sessionA, 'assistant_delta', { content: 'New turn is live' });
    app.pauseHistory = null;
    history.resolve();
    await expect(page.locator('.composer-banner')).not.toBeVisible();
    await expect(page.locator('#transcript').getByText('Finished while disconnected.', { exact: true })).toHaveCount(1);
    if (nextTurn) {
      await expect(page.locator('#stop')).toBeEnabled();
      await expect(page.locator('#transcript')).toContainText('New turn is live');
      await app.emitSessionEvent(sessionA, 'task_finished', { status: 'failed' }, { task: oldTask, seq: 999 });
      await expect(page.locator('#stop')).toBeEnabled();
    } else {
      await expect(page.locator('#stop')).toHaveCount(0);
      await page.locator('#task').fill('Another explicit prompt');
      await expect(page.locator('#send')).toBeEnabled();
    }
    expect(app.postCount).toBe(1);
    expect(app.device.pageErrors).toEqual([]);
  });
}

test('Cloud repeated reconnects retain pending inputs, queue and later drafts without duplicate messages', async ({ page }) => {
  const app = await running(page);
  for (const mode of ['Queue next', 'Steer now']) {
    await page.locator('#task').fill(mode);
    await page.getByRole('button', { name: 'Follow-up action', exact: true }).click();
    await page.getByRole('option', { name: new RegExp(`^${mode}`) }).click();
    await page.locator('#send').click();
    await expect(page.locator('#task')).toHaveValue('');
  }
  await expect(page.locator('.pending-steer-row')).toContainText('Steer now');
  await expect(page.locator('.queued-input-row')).toContainText('Queue next');
  await page.locator('#task').fill('Later typing');
  const posts = app.requests.filter(request => request.method === 'POST').length;
  for (let index = 0; index < 3; index++) {
    await app.disconnectSession(sessionA, { error: index % 2 === 1 });
    await expect.poll(() => observations(app).length).toBe(index + 2);
    await expect(page.locator('.composer-banner')).not.toBeVisible();
    await expect(page.locator('#stop')).toBeEnabled();
    await expect(page.locator('.pending-steer-row')).toContainText('Steer now');
    await expect(page.locator('.queued-input-row')).toContainText('Queue next');
  }
  const submission = app.controlState(sessionA).data.steers[0].submission_id;
  await app.emitSessionEvent(sessionA, 'user', { content: 'Steer now', submission_id: submission });
  await app.emitSessionEvent(sessionA, 'steer_applied', { content: 'Steer now', submission_id: submission, kind: 'prompt' });
  await expect(page.locator('.pending-steer-row')).toHaveCount(0);
  await expect(page.locator('#transcript').getByText('Steer now', { exact: true })).toHaveCount(1);
  await app.finishTask(sessionA, 'failed');
  await expect(page.locator('#stop')).toHaveCount(0);
  await expect(page.locator('.queued-input-row').getByTitle('Edit', { exact: true })).toBeEnabled();
  await expect(page.locator('.queued-input-row').getByTitle('Steer', { exact: true })).toBeDisabled();
  await expect(page.locator('#task')).toHaveValue('Later typing');
  expect(app.requests.filter(request => request.method === 'POST')).toHaveLength(posts);
  expect(app.device.pageErrors).toEqual([]);
});

test('Cloud recovers one durable answer after a burst of 256 deltas and EOF', async ({ page }) => {
  const app = await running(page);
  const baseline = app.controlState(sessionA);
  const content = '🌙'.repeat(256);
  const frames = Array.from({ length: 256 }, (_, index) => app.sseFrame('assistant_delta', {
    session_id: sessionA, task_id: baseline.task_id, seq: baseline.seq + index + 1,
    kind: 'assistant_delta', data: { content: '🌙' },
  })).join('');
  app.controlSnapshots.set(sessionA, { ...baseline, seq: baseline.seq + 256 });
  await page.evaluate(({ session, frames }) => window.cloudSessionEvent(session, frames), { session: sessionA, frames });
  await expect(page.locator('#transcript').getByText(content, { exact: true })).toHaveCount(1);
  await app.disconnectSession(sessionA);
  await expect(page.locator('.composer-banner')).toContainText('reconnecting');
  await app.emitSessionEvent(sessionA, 'assistant_message', { content });
  await app.finishTask();
  await expect.poll(() => observations(app).length).toBe(2);
  await expect(page.locator('.composer-banner')).not.toBeVisible();
  await expect(page.locator('#transcript').getByText(content, { exact: true })).toHaveCount(1);
  await expect(page.locator('#transcript .streaming')).toHaveCount(0);
  await expect(page.locator('#stop')).toHaveCount(0);
  expect(app.postCount).toBe(1);
  expect(app.device.pageErrors).toEqual([]);
});

for (const leave of ['switch', 'sign out']) {
  test(`Cloud ${leave} cancels a scheduled ${leave === 'switch' ? 'idle conversation ' : ''}reconnect`, async ({ page }) => {
    const app = await running(page);
    if (leave === 'switch') {
      await app.finishTask();
      await expect(page.locator('#stop')).toHaveCount(0);
    }
    await page.clock.install();
    await app.disconnectSession(sessionA);
    await expect(page.locator('.composer-banner')).toContainText('reconnecting');
    if (leave === 'switch') {
      await app.open(sessionB);
      await expect.poll(() => observations(app, sessionB).length).toBe(1);
    } else {
      await page.getByRole('button', { name: 'Settings', exact: true }).click();
      const section = page.locator('.settings-group', { has: page.getByRole('heading', { name: 'Account · Remote access', exact: true }) });
      await section.getByRole('button', { name: 'Sign out', exact: true }).click();
      await expect(app.row(sessionA)).toBeHidden();
    }
    await page.clock.runFor(5000);
    expect(observations(app)).toHaveLength(1);
    expect(app.postCount).toBe(1);
    expect(app.device.pageErrors).toEqual([]);
  });
}

for (const status of [401, 404, 403]) {
  test(`Cloud reconnect stops on HTTP ${status}`, async ({ page }) => {
    const app = await running(page);
    await page.clock.install();
    app.sessionEventStatus = status;
    await app.disconnectSession(sessionA);
    await expect(page.locator('.composer-banner')).toContainText('reconnecting');
    await page.clock.runFor(1600);
    await expect.poll(() => observations(app).length).toBe(2);
    if (status === 401 || status === 404) await expect(app.row(sessionA)).toBeHidden();
    else await expect(page.locator('#transcript')).toContainText('HTTP 403');
    await page.clock.runFor(5000);
    expect(observations(app)).toHaveLength(2);
    expect(app.postCount).toBe(1);
    expect(app.device.pageErrors).toEqual([]);
  });
}

for (const operation of ['Archive', 'Delete…']) {
  test(`Cloud ${operation} cancels an idle conversation reconnect`, async ({ page }) => {
    const app = new CloudHarness(page);
    await app.install();
    await app.goto();
    await app.open();
    await expect.poll(() => observations(app).length).toBe(1);
    await expect.poll(() => page.evaluate(session => window.cloudSessionStreams.get(session)?.size, sessionA)).toBe(1);
    await page.clock.install();
    await app.disconnectSession(sessionA);
    await expect(page.locator('.composer-banner')).toContainText('reconnecting');
    await app.row(sessionA).locator('..').hover();
    await app.row(sessionA).locator('..').getByRole('button', { name: 'Conversation actions', exact: true }).click();
    await page.getByRole('menuitem', { name: operation, exact: true }).click();
    if (operation === 'Delete…') await page.getByRole('button', { name: 'Delete permanently', exact: true }).click();
    await expect(page.locator('main .topbar-title')).toHaveText('New chat');
    await page.clock.runFor(5000);
    expect(observations(app)).toHaveLength(1);
    expect(app.postCount).toBe(0);
    expect(app.device.pageErrors).toEqual([]);
  });
}

test('Cloud reconnect fences an old history reply and retains newer live messages during synchronization', async ({ page }) => {
  const app = await running(page);
  const oldTask = app.controlState(sessionA).task_id;
  const oldRead = deferred();
  app.pauseHistory = oldRead.promise;
  const oldResponse = page.waitForResponse(response => response.request().method() === 'GET' && response.url().endsWith(`/${sessionA}/messages`));
  const reads = () => app.requests.filter(request => request.method === 'GET' && request.path.endsWith(`/${sessionA}/messages`)).length;
  const before = reads();
  await app.finishTask();
  await expect.poll(reads).toBeGreaterThan(before);
  const connection = deferred();
  app.pauseSessionEvents = connection.promise;
  await app.disconnectSession(sessionA);
  await expect.poll(() => observations(app).length).toBe(2);
  await app.emitSessionEvent(sessionA, 'task_started', { previous_task_id: oldTask }, { task: 'next-task', seq: 1 });
  const freshRead = deferred();
  app.pauseHistory = freshRead.promise;
  const beforeFresh = reads();
  app.pauseSessionEvents = null;
  connection.resolve();
  await expect.poll(reads).toBeGreaterThan(beforeFresh);
  await app.emitSessionEvent(sessionA, 'assistant_message', { content: 'New durable message' });
  app.pauseHistory = null;
  freshRead.resolve();
  await expect(page.locator('.composer-banner')).not.toBeVisible();
  await expect(page.locator('#stop')).toBeEnabled();
  await expect(page.locator('#transcript').getByText('New durable message', { exact: true })).toHaveCount(1);
  oldRead.resolve();
  await (await oldResponse).finished();
  // A new frame also proves the stale read did not retire the live observer.
  await app.emitSessionEvent(sessionA, 'assistant_delta', { content: 'Still running the new turn' });
  await expect(page.locator('#transcript')).toContainText('Still running the new turn');
  await expect(page.locator('#stop')).toBeEnabled();
  await expect(page.locator('#transcript').getByText('New durable message', { exact: true })).toHaveCount(1);
  expect(app.postCount).toBe(1);
  expect(app.device.pageErrors).toEqual([]);
});

test('Cloud switching away retires an in-flight idle reconnect response', async ({ page }) => {
  const app = await running(page);
  await app.finishTask();
  await expect(page.locator('#stop')).toHaveCount(0);
  const connection = deferred();
  app.pauseSessionEvents = connection.promise;
  await app.disconnectSession(sessionA);
  await expect.poll(() => observations(app).length).toBe(2);
  await app.open(sessionB);
  app.pauseSessionEvents = null;
  connection.resolve();
  await expect.poll(() => observations(app, sessionB).length).toBe(1);
  await expect.poll(() => page.evaluate(session => window.cloudSessionStreams.get(session)?.size || 0, sessionA)).toBe(0);
  await app.emitSessionEvent(sessionA, 'assistant_message', { content: 'Hidden conversation response' });
  await expect(page.locator('main .topbar-title')).toHaveText('Cloud fixture B');
  await expect(page.locator('#transcript')).not.toContainText('Hidden conversation response');
  expect(observations(app)).toHaveLength(2);
  expect(app.postCount).toBe(1);
  expect(app.device.pageErrors).toEqual([]);
});

test('Cloud recovery retries a failed history synchronization without another stream or submission', async ({ page }) => {
  const app = await running(page);
  const connection = deferred();
  app.pauseSessionEvents = connection.promise;
  await app.disconnectSession(sessionA);
  await expect.poll(() => observations(app).length).toBe(2);
  await app.emitSessionEvent(sessionA, 'assistant_message', { content: 'Completed during the outage' });
  await app.finishTask();
  app.historyStatus = 503;
  const failed = page.waitForResponse(response => response.request().method() === 'GET' && response.url().endsWith(`/${sessionA}/messages`) && response.status() === 503);
  app.pauseSessionEvents = null;
  connection.resolve();
  await (await failed).finished();
  await expect(page.locator('.composer-banner')).toContainText('reconnecting');
  await expect(page.locator('#transcript')).not.toContainText('HTTP 503');
  await expect(page.locator('#send')).toBeDisabled();
  app.historyStatus = 200;
  await expect(page.locator('.composer-banner')).not.toBeVisible();
  await expect(page.locator('#transcript').getByText('Completed during the outage', { exact: true })).toHaveCount(1);
  await expect(page.locator('#stop')).toHaveCount(0);
  expect(observations(app)).toHaveLength(2);
  expect(app.postCount).toBe(1);
  expect(app.device.pageErrors).toEqual([]);
});


for (const error of [false, true]) {
  test(`Cloud reconnects after ${error ? 'a stream read failure' : 'EOF'} without resubmitting input`, async ({ page }, testInfo) => {
    const app = await running(page);
    await app.emitSessionEvent(sessionA, 'assistant_message', { content: 'Already confirmed.' });
    await expect(page.locator('#transcript')).toContainText('Already confirmed.');
    await page.locator('#task').fill('Keep my draft');
    const next = deferred();
    app.pauseSessionEvents = next.promise;
    await app.disconnectSession(sessionA, { error });
    await expect(page.locator('.composer-banner')).toContainText('reconnecting');
    await expect(page.locator('#transcript')).not.toContainText('Cloud is unreachable');
    await expect(page.locator('#task')).toBeEnabled();
    await expect(page.locator('#send')).toBeDisabled();
    await expect.poll(() => observations(app).length).toBe(2);
    if (!error) await page.locator('main').screenshot({ path: testInfo.outputPath('cloud-reconnecting.png') });
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
}
