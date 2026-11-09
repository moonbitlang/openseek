import { test, expect } from './support/test.js';
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

test('Cloud background completion uses the shared notification, badge and click navigation', async ({ page }) => {
  const app = await running(page);
  await app.open(sessionB);
  let releaseHistory;
  app.pauseHistory = new Promise(resolve => { releaseHistory = resolve; });
  await app.emitSessionEvent(sessionA, 'assistant_message', { content: 'The Cloud task is done.' });
  await app.finishTask();
  await expect.poll(() => shown(app).length).toBe(1);
  expect(shown(app)[0].params).toMatchObject({ title: 'Task finished', body: 'The Cloud task is done.' });
  await expect.poll(() => badge(app)).toBe(1);
  await expect(app.rowContainer(sessionA).getByRole('status')).toBeVisible();
  await expect.poll(() => page.evaluate(session => window.cloudSessionStreams.get(session)?.size || 0, sessionA)).toBe(0);
  app.pauseHistory = null;
  releaseHistory();
  const payload = shown(app)[0].params.payload;
  await page.evaluate(payload => window.desktopEvent('notification.click', { payload }), payload);
  await expect(page.locator('main .topbar-title')).toHaveText('Cloud fixture A');
  await expect(app.row(sessionA)).toHaveAttribute('aria-current', 'true');
  await expect.poll(() => badge(app)).toBe(0);
  await expect(app.rowContainer(sessionA).getByRole('status')).toHaveCount(0);
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
    const refreshed = page.waitForResponse(response => response.request().method() === 'GET' && new URL(response.url()).pathname.endsWith(`/${sessionA}/messages`));
    await app.emitSessionEvent(sessionA, 'task_finished', { status: 'completed', result: { status: 'completed' } });
    expect([200, 304]).toContain((await refreshed).status());
    expect(shown(app)).toHaveLength(1);
    await app.open(sessionB);
    await app.open(sessionA);
    await expect(page.locator('#stop')).toHaveCount(0);
    expect(shown(app)).toHaveLength(1);
    expect(app.device.pageErrors).toEqual([]);
  });
}

test('Cloud browser completion uses the same unread row without requesting native notifications', async ({ page }) => {
  const app = await running(page, { desktop: false });
  await app.open(sessionB);
  await app.finishTask();
  await expect(app.rowContainer(sessionA).getByRole('status')).toBeVisible();
  expect(app.notifications).toEqual([]);
  await app.open(sessionA);
  await expect(app.rowContainer(sessionA).getByRole('status')).toHaveCount(0);
  expect(app.device.pageErrors).toEqual([]);
  expect(await page.evaluate(() => window.cloudUnhandledRejections)).toEqual([]);
});
