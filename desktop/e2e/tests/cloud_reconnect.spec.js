import { test, expect } from './support/test.js';
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

test('Cloud recovers one durable answer after a burst of 256 deltas and EOF', async ({ page }) => {
  const app = await running(page);
  const baseline = app.controlState(sessionA);
  const content = '🌙'.repeat(256);
  const frames = Array.from({ length: 256 }, (_, index) => app.sseFrame('engine_event', {
    session_id: sessionA, task_id: baseline.task_id, seq: baseline.seq + index + 1,
    kind: 'engine_event', data: { event: 'assistant_delta', content: '🌙' },
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
    await app.rowContainer(sessionA).hover();
    await app.rowContainer(sessionA).getByRole('button', { name: 'Conversation actions', exact: true }).click();
    await page.getByRole('menuitem', { name: operation, exact: true }).click();
    if (operation === 'Delete…') await page.getByRole('button', { name: 'Delete permanently', exact: true }).click();
    await expect(page.locator('main .topbar-title')).toHaveText('New chat');
    await page.clock.runFor(5000);
    expect(observations(app)).toHaveLength(1);
    expect(app.postCount).toBe(0);
    expect(app.device.pageErrors).toEqual([]);
  });
}

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

for (const error of [false, true]) {
  test(`Cloud reconnects after ${error ? 'a stream read failure' : 'EOF'} without resubmitting input`, async ({ page }) => {
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
