import { test, expect } from '@playwright/test';
import { CloudHarness, sessionA, sessionB } from './support/cloud_harness.js';

const shown = app => app.notifications.filter(call => call.method === 'show');
const badge = app => app.notifications.filter(call => call.method === 'setBadge').at(-1)?.params.count;

async function running(page, { desktop = true } = {}) {
  const app = new CloudHarness(page, { desktop });
  app.manualTasks = true;
  await app.install();
  await app.goto();
  await app.open();
  await page.locator('#task').fill('Notify when finished');
  await page.locator('#send').click();
  await expect(page.locator('#stop')).toBeEnabled();
  return app;
}

test('Cloud background completion uses the shared notification, badge and click navigation', async ({ page }, testInfo) => {
  const app = await running(page);
  await app.open(sessionB);
  await app.emitSessionEvent(sessionA, 'assistant_message', { content: 'The Cloud task is done.' });
  await app.finishTask();
  await expect.poll(() => shown(app).length).toBe(1);
  expect(shown(app)[0].params).toMatchObject({ title: 'Task finished', body: 'The Cloud task is done.' });
  await expect.poll(() => badge(app)).toBe(1);
  await expect(app.row(sessionA).locator('..').getByRole('status')).toBeVisible();
  await expect.poll(() => page.evaluate(session => window.cloudSessionStreams.get(session)?.size || 0, sessionA)).toBe(0);
  await page.screenshot({ path: testInfo.outputPath('cloud-unread-completion.png') });
  const payload = shown(app)[0].params.payload;
  await page.evaluate(payload => window.desktopEvent('notification.click', { payload }), payload);
  await expect(page.locator('main .topbar-title')).toHaveText('Cloud fixture A');
  await expect(app.row(sessionA)).toHaveAttribute('aria-current', 'true');
  await expect.poll(() => badge(app)).toBe(0);
  await expect(app.row(sessionA).locator('..').getByRole('status')).toHaveCount(0);
  await expect(page.locator('#transcript')).toContainText('The Cloud task is done.');
  expect(shown(app)).toHaveLength(1);
  expect(app.device.pageErrors).toEqual([]);
});

for (const focused of [true, false]) {
  test(`Cloud ${focused ? 'foreground' : 'unfocused'} completion follows the shared read policy`, async ({ page }) => {
    const app = await running(page);
    await page.evaluate(focused => window.dispatchEvent(new Event(focused ? 'focus' : 'blur')), focused);
    await app.finishTask();
    await expect.poll(() => shown(app).length).toBe(1);
    expect(shown(app)[0].params.title).toBe('Task finished');
    await expect.poll(() => badge(app)).toBe(focused ? 0 : 1);
    if (!focused) {
      await page.evaluate(() => window.dispatchEvent(new Event('focus')));
      await expect.poll(() => badge(app)).toBe(0);
    }
    const refreshed = page.waitForResponse(response => response.request().method() === 'GET' && response.url().endsWith(`/${sessionA}/messages`));
    await app.emitSessionEvent(sessionA, 'task_finished', { status: 'completed', result: { status: 'completed' } });
    await (await refreshed).finished();
    expect(shown(app)).toHaveLength(1);
    await app.open(sessionB);
    await app.open(sessionA);
    await expect(page.locator('#stop')).toHaveCount(0);
    expect(shown(app)).toHaveLength(1);
    expect(app.device.pageErrors).toEqual([]);
  });
}

test('Cloud keeps observing a background queued turn and counts conversations rather than completions', async ({ page }) => {
  const app = await running(page);
  await app.publishControl(sessionA, { queue: [{ id: 'next-input', content: 'Continue' }] });
  await app.open(sessionB);
  const previous = app.controlState(sessionA).task_id;
  await app.finishTask();
  await expect.poll(() => shown(app).length).toBe(1);
  await app.emitSessionEvent(sessionA, 'task_started', { previous_task_id: previous, submission_id: 'next-input' }, { task: 'second-task', seq: 1 });
  await app.finishTask();
  await expect.poll(() => shown(app).length).toBe(2);
  await expect.poll(() => badge(app)).toBe(1);
  expect(shown(app)[0].params.payload).toBe(shown(app)[1].params.payload);
  expect(app.postCount).toBe(1);
  expect(app.device.pageErrors).toEqual([]);
});

test('Cloud cancellation stays silent and sign-out retires its unread badge and notification target', async ({ page }) => {
  const app = await running(page);
  await app.open(sessionB);
  await app.finishTask(sessionA, 'failed');
  await expect(app.row(sessionA).locator('..').getByRole('status')).toBeVisible();
  await expect.poll(() => badge(app)).toBe(1);
  expect(shown(app)).toHaveLength(0);
  // Obtain a real completion target before signing out.
  await app.open(sessionA);
  await page.locator('#task').fill('A second prompt');
  await page.locator('#send').click();
  await expect(page.locator('#stop')).toBeEnabled();
  await app.open(sessionB);
  await app.finishTask();
  await expect.poll(() => shown(app).length).toBe(1);
  const payload = shown(app)[0].params.payload;
  await page.getByRole('button', { name: 'Settings', exact: true }).click();
  const section = page.locator('.settings-group', { has: page.getByRole('heading', { name: 'Account · Remote access', exact: true }) });
  await section.getByRole('button', { name: 'Sign out', exact: true }).click();
  await expect(app.row(sessionA)).toBeHidden();
  await expect.poll(() => badge(app)).toBe(0);
  await page.evaluate(payload => window.desktopEvent('notification.click', { payload }), payload);
  await expect(page.locator('main .topbar-title')).toHaveText('Settings');
  expect(app.device.pageErrors).toEqual([]);
});

test('Cloud browser completion uses the same unread row without requesting native notifications', async ({ page }) => {
  const app = await running(page, { desktop: false });
  await app.open(sessionB);
  await app.finishTask();
  await expect(app.row(sessionA).locator('..').getByRole('status')).toBeVisible();
  expect(app.notifications).toEqual([]);
  await app.open(sessionA);
  await expect(app.row(sessionA).locator('..').getByRole('status')).toHaveCount(0);
  expect(app.device.pageErrors).toEqual([]);
  expect(await page.evaluate(() => window.cloudUnhandledRejections)).toEqual([]);
});
