import { test, expect } from './support/test.js';
import { CloudHarness, authOrigin, cloudOrigin, sessionA } from './support/cloud_harness.js';

const message = '  窗口闪烁\nsecond line  ';
const url = `${authOrigin}/v1/feedback/fb_test`;

for (const mode of ['Cloud', 'Local']) {
  test(`${mode} feedback copies the published link and retains the draft on failure`, async ({ page, context }) => {
    await context.grantPermissions(['clipboard-read', 'clipboard-write']);
    const local = mode === 'Local';
    const app = new CloudHarness(page, { desktop: local });
    app.historyTurns.set(sessionA, Array.from({ length: 80 }, (_, i) => {
      const sequence = i * 2 + 1;
      return {
        messages: [{ task_id: `turn-${i}`, kind: 'user', data: {}, id: sequence, engine_sequence: sequence, created_at: sequence }],
        events: [
          { sequence, item: { kind: 'user', payload: { content: `Persisted question (${i + 1})` } } },
          { sequence: sequence + 1, item: { kind: 'terminal', payload: { kind: 'finished' } } },
        ],
      };
    }));
    await app.install();
    const posts = [];
    let succeed = false;
    if (local) {
      app.device.sessionEvents = [{ sequence: 80, ts: 80, item: { kind: 'user', payload: { content: 'Persisted question (80)' } } }];
      const original = app.device.replyFor.bind(app.device);
      app.device.replyFor = request => {
        if (request.method === 'session.share') return { status: 'shared', url: authOrigin + '/v1/shares/sh_fixture' };
        if (request.method !== 'session.feedback') return original(request);
        posts.push(request.params);
        if (!succeed) throw new Error('Unknown command: session.feedback');
        return { status: 'shared', url };
      };
      await page.goto(`${authOrigin}/console/index.html?device=device-a`);
      await page.getByText('Rabbita browser fixture', { exact: true }).first().click();
    } else {
      await page.route(`${cloudOrigin}/v1/sessions/${sessionA}/feedback`, route => {
        expect(route.request().headers().authorization).toBe('Bearer ts_fixture-123');
        expect(route.request().headers()['content-type']).toContain('application/json');
        posts.push(route.request().postDataJSON());
        return route.fulfill(succeed ? { status: 201, json: { id: 'fb_test', url } } : { status: 502, json: { error: 'storage unavailable' } });
      });
      await page.goto(`${authOrigin}/cloud/session/${sessionA}`);
    }
    await expect(page.locator('#transcript .msg.user .msg-content')).toHaveText(['Persisted question (80)']);
    const task = page.locator('#task');
    await task.fill('/feed');
    const completion = page.locator('.completion-item').filter({ hasText: '/feedback' });
    await expect(completion).toContainText('Anyone with the link can read the full conversation');
    await completion.click();
    await expect(page.locator('#send')).toBeDisabled();
    await task.fill('/feedback ' + message);
    await task.press('Enter');
    const dialog = page.getByRole('dialog', { name: 'Export conversation' });
    await expect(dialog).toContainText('kept until manually deleted');
    await expect(dialog).not.toContainText('7 days');
    await expect(dialog.locator('.export-error')).toContainText(local ? 'Unknown command: session.feedback' : 'storage unavailable');
    expect(app.hostRequests.filter(r => r.method === 'session.share')).toHaveLength(0);
    await expect(task).toHaveValue('/feedback ' + message);
    succeed = true;
    await dialog.getByRole('button', { name: 'Share', exact: true }).click();
    await expect(dialog.getByRole('textbox', { name: 'Share link' })).toHaveValue(url);
    await expect(task).toHaveValue('');
    await dialog.getByRole('button', { name: 'Copy share link' }).click();
    await expect.poll(() => page.evaluate(() => navigator.clipboard.readText())).toBe(url);
    expect(posts).toHaveLength(2);
    for (const body of posts) {
      expect(local ? body.metadata : body).toEqual({ message, environment: {
        client: local ? 'desktop' : 'browser', app_version: local ? expect.any(String) : process.env.SEEKMOON_BROWSER_RELEASE || 'unknown',
        platform: expect.any(String), locale: expect.any(String), user_agent: expect.any(String),
      } });
      if (local) {
        expect(body.share.source).toMatchObject({ session: 'session-1', workspace: '/workspace' });
        expect(body.share.authorization).toEqual({ kind: 'local_account', user_id: '123' });
      }
    }
    await dialog.press('Escape');
    await page.getByRole('button', { name: 'Export', exact: true }).click();
    await expect(dialog).toContainText('7 days');
    await dialog.getByRole('button', { name: 'Share', exact: true }).click();
    await expect(dialog.getByRole('textbox', { name: 'Share link' })).toHaveValue(/\/v1\/shares\//);
    expect(posts).toHaveLength(2);
    expect(app.device.pageErrors).toEqual([]);
  });
}

test('a dismissed feedback submission can be reopened before and after its receipt', async ({ page, context }) => {
  await context.grantPermissions(['clipboard-read', 'clipboard-write']);
  const app = new CloudHarness(page);
  await app.install();
  let finish;
  const pending = new Promise(resolve => { finish = resolve; });
  let posts = 0;
  await page.route(`${cloudOrigin}/v1/sessions/${sessionA}/feedback`, async route => {
    posts++;
    await pending;
    await route.fulfill({ status: 201, json: { id: 'fb_test', url } });
  });
  await page.goto(`${authOrigin}/cloud/session/${sessionA}`);
  const task = page.locator('#task');
  const dialog = page.getByRole('dialog', { name: 'Export conversation' });
  await task.fill('/feedback ' + message);
  await task.press('Enter');
  await expect.poll(() => posts).toBe(1);
  await dialog.press('Escape');
  await expect(dialog).toBeHidden();
  await task.press('Enter');
  await expect(dialog).toBeVisible();
  await dialog.press('Escape');
  finish();
  await expect(task).toHaveValue('');
  await expect(dialog).toBeHidden();
  await page.getByRole('button', { name: 'Export', exact: true }).click();
  await expect(dialog).toContainText('7 days');
  await dialog.getByRole('button', { name: 'Share', exact: true }).click();
  await expect(dialog.getByRole('textbox', { name: 'Share link' })).toHaveValue(/\/v1\/shares\//);
  await dialog.press('Escape');
  await task.fill('/feedback ' + message);
  await task.press('Enter');
  await expect(dialog.getByRole('textbox', { name: 'Share link' })).toHaveValue(url);
  await expect(task).toHaveValue('');
  await dialog.getByRole('button', { name: 'Copy share link' }).click();
  await expect.poll(() => page.evaluate(() => navigator.clipboard.readText())).toBe(url);
  expect(posts).toBe(1);
});
