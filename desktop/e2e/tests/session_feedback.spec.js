import { test, expect } from './support/test.js';
import { CloudHarness, authOrigin, cloudOrigin, sessionA } from './support/cloud_harness.js';

const message = '  窗口闪烁\n<em>second line</em>  ';
const url = `${authOrigin}/v1/feedback/fb_test`;

for (const mode of ['Cloud', 'Local']) {
  test(`${mode} feedback reports progress inline, retains edits and retries in the composer`, async ({ page, context }) => {
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
    const gates = Array.from({ length: 5 }, () => {
      let finish;
      const pending = new Promise(resolve => { finish = resolve; });
      return { pending, finish };
    });
    if (local) {
      app.device.sessionEvents = [{ sequence: 80, ts: 80, item: { kind: 'user', payload: { content: 'Persisted question (80)' } } }];
      const original = app.device.replyFor.bind(app.device);
      app.device.replyFor = async request => {
        if (request.method === 'session.share') return { status: 'shared', url: authOrigin + '/v1/shares/sh_fixture' };
        if (request.method !== 'session.feedback') return original(request);
        posts.push(request.params);
        const attempt = posts.length;
        await gates[attempt - 1].pending;
        if (attempt === 1) return { status: 'failed', message: 'storage unavailable' };
        if (attempt === 4) throw new Error('Unknown command: session.feedback');
        return { status: 'submitted', id: 'fb_test' };
      };
      await page.goto(`${authOrigin}/console/index.html?device=device-a`);
      await page.getByText('Rabbita browser fixture', { exact: true }).first().click();
    } else {
      await page.route(`${cloudOrigin}/v1/sessions/${sessionA}/feedback`, async route => {
        expect(route.request().headers().authorization).toBe('Bearer ts_fixture-123');
        expect(route.request().headers()['content-type']).toContain('application/json');
        posts.push(route.request().postDataJSON());
        const attempt = posts.length;
        await gates[attempt - 1].pending;
        return route.fulfill(attempt !== 1 && attempt !== 4 ? { status: 201, json: { id: 'fb_test' } } : { status: 502, json: { error: 'storage unavailable' } });
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
    const emptyCommand = await task.inputValue();
    await task.press('Enter');
    await expect(task).toHaveValue(emptyCommand);
    const dialog = page.getByRole('dialog', { name: 'Export conversation' });
    const status = page.locator('.composer-feedback-status');
    const command = '/feedback ' + message;
    const retry = message + ' edited';
    await page.evaluate(() => navigator.clipboard.writeText('original clipboard'));
    await task.fill(command);
    await task.press('Enter');
    await expect(status).toContainText('Submitting feedback…');
    await expect(status.locator('.composer-feedback-message')).toHaveJSProperty('textContent', message);
    await expect(task).toHaveValue('');
    await expect(task).toBeFocused();
    await expect(dialog).toBeHidden();
    await task.press('Enter');
    await expect.poll(() => posts.length).toBe(1);
    gates[0].finish();
    await expect(status).toContainText('storage unavailable');
    await expect(task).toHaveValue(command);
    await task.fill('/feedback ' + retry);
    await task.press('Enter');
    await expect(status.locator('.composer-feedback-message')).toHaveJSProperty('textContent', retry);
    await expect(task).toHaveValue('');
    await expect.poll(() => posts.length).toBe(2);
    gates[1].finish();
    await expect(status).toHaveText('Feedback submitted');
    await expect(task).toHaveValue('');
    await task.fill(command);
    await task.press('Enter');
    await expect.poll(() => posts.length).toBe(3);
    await expect(status.locator('.composer-feedback-message')).toHaveJSProperty('textContent', message);
    await task.fill(command);
    await expect(page.locator('#send')).toBeDisabled();
    await task.press('Enter');
    await expect(task).toHaveValue(command);
    gates[2].finish();
    await expect(status).toHaveText('Feedback submitted');
    await expect(task).toHaveValue(command);
    await expect(dialog).toBeHidden();
    await expect(page.getByText(url, { exact: true })).toHaveCount(0);
    await task.press('Enter');
    await expect.poll(() => posts.length).toBe(4);
    await task.fill('my next question');
    gates[3].finish();
    await expect(status.locator('.composer-feedback-message')).toHaveJSProperty('textContent', message);
    await expect(task).toHaveValue('my next question');
    const retryButton = status.getByRole('button', { name: 'Retry', exact: true });
    await task.fill('my next question, edited');
    await retryButton.click();
    await expect.poll(() => posts.length).toBe(5);
    await expect(status).toContainText('Submitting feedback…');
    await expect(status.locator('.composer-feedback-message')).toHaveJSProperty('textContent', message);
    gates[4].finish();
    await expect(status).toHaveText('Feedback submitted');
    await expect(status).toBeHidden();
    await expect(task).toHaveValue('my next question, edited');
    expect(await page.evaluate(() => navigator.clipboard.readText())).toBe('original clipboard');
    expect(app.hostRequests.filter(r => r.method === 'session.share')).toHaveLength(0);
    for (const [index, body] of posts.entries()) {
      expect(local ? body.metadata : body).toEqual({ message: index === 1 ? retry : message, environment: {
        client: local ? 'desktop' : 'browser', app_version: local ? expect.any(String) : process.env.SEEKMOON_BROWSER_RELEASE || 'unknown',
        platform: expect.any(String), locale: expect.any(String), user_agent: expect.any(String),
      } });
      if (local) {
        expect(body.source).toMatchObject({ session: 'session-1', workspace: '/workspace' });
        expect(body.user_id).toBe('123');
      }
    }
    await page.getByRole('button', { name: 'Export', exact: true }).click();
    await expect(dialog).toContainText('7 days');
    await dialog.getByRole('button', { name: 'Share', exact: true }).click();
    await expect(dialog.getByRole('textbox', { name: 'Share link' })).toHaveValue(/\/v1\/shares\//);
    expect(posts).toHaveLength(5);
    expect(app.device.pageErrors).toEqual([]);
  });
}

for (const mode of ['Local', 'Cloud']) {
  test(`${mode} feedback offers sign-in and preserves the draft for an explicit retry`, async ({ page }) => {
    const local = mode === 'Local';
    const app = new CloudHarness(page, { desktop: true, cached: !local });
    await app.install();
    let uploads = 0;
    if (local) {
      const original = app.device.replyFor.bind(app.device);
      app.device.replyFor = request => {
        if (request.method !== 'session.feedback') return original(request);
        uploads++;
        return { status: 'submitted', id: 'fb_test' };
      };
      await page.goto(`${authOrigin}/console/index.html?device=device-a`);
      await page.getByText('Rabbita browser fixture', { exact: true }).first().click();
    } else {
      await page.route(`${cloudOrigin}/v1/sessions/${sessionA}/feedback`, route => {
        uploads++;
        return route.fulfill(uploads === 1
          ? { status: 401, json: { error: 'unauthorized' } }
          : { status: 201, json: { id: 'fb_test', url } });
      });
      await app.goto();
      await app.open(sessionA);
    }
    const task = page.locator('#task');
    const command = '/feedback ' + message;
    await task.fill(command);
    await task.press('Enter');
    const status = page.locator('.composer-feedback-status');
    const login = status.getByRole('button', { name: 'Sign in', exact: true });
    await expect(login).toBeVisible();
    await expect(task).toHaveValue(command);
    await login.click();
    await expect.poll(() => app.hostRequests.filter(r => r.method === 'auth.connect').length).toBe(1);
    await expect(login).toBeHidden();
    expect(uploads).toBe(local ? 0 : 1);
    await expect(task).toHaveValue(command);
    await task.press('Enter');
    await expect(status).toHaveText('Feedback submitted');
    await expect(task).toHaveValue('');
    expect(uploads).toBe(local ? 1 : 2);
  });
}

test('browser sign-in restores newer typing and the separate feedback retry', async ({ page }) => {
  const app = new CloudHarness(page, { cached: false });
  app.accountSignedIn = true;
  await app.install();
  let uploads = 0;
  let release;
  const pending = new Promise(resolve => { release = resolve; });
  await page.route(`${cloudOrigin}/v1/sessions/${sessionA}/feedback`, async route => {
    uploads++;
    if (uploads === 1) await pending;
    expect(route.request().postDataJSON().message).toBe(message);
    return route.fulfill(uploads === 1
      ? { status: 401, json: { error: 'unauthorized' } }
      : { status: 201, json: { id: 'fb_test', url } });
  });
  await page.goto(`${authOrigin}/cloud/session/${sessionA}`);
  const task = page.locator('#task');
  const command = '/feedback ' + message;
  const status = page.locator('.composer-feedback-status');
  await task.fill(command);
  await task.press('Enter');
  await expect(status.locator('.composer-feedback-message')).toHaveJSProperty('textContent', message);
  await task.fill('draft for my next message');
  release();
  const navigation = page.waitForRequest(request => new URL(request.url()).pathname === '/v2/auth/login');
  await status.getByRole('button', { name: 'Sign in' }).click();
  expect(new URL((await navigation).url()).searchParams.get('return_to')).toBe('/cloud/session/' + sessionA);
  await expect(status.getByRole('button', { name: 'Retry' })).toBeVisible();
  await expect(task).toHaveValue('draft for my next message');
  expect(uploads).toBe(1);
  await status.getByRole('button', { name: 'Retry' }).click();
  await expect(status).toHaveText('Feedback submitted');
  await expect(task).toHaveValue('draft for my next message');
  expect(uploads).toBe(2);
});

test('a Cloud conversation can send the next chat message before feedback finishes', async ({ page }) => {
  const app = new CloudHarness(page);
  await app.install();
  let release;
  const pending = new Promise(resolve => { release = resolve; });
  await page.route(`${cloudOrigin}/v1/sessions/${sessionA}/feedback`, async route => {
    await pending;
    await route.fulfill({ status: 201, json: { id: 'fb_test', url } });
  });
  await app.goto();
  await app.open();
  const task = page.locator('#task');
  const status = page.locator('.composer-feedback-status');
  // Deliver input and Enter before the composer can render the typed draft.
  await task.evaluate((field, command) => {
    field.focus();
    field.value = command;
    field.dispatchEvent(new InputEvent('input', { bubbles: true, data: command, inputType: 'insertText' }));
    field.dispatchEvent(new KeyboardEvent('keydown', {
      bubbles: true, cancelable: true, key: 'Enter', code: 'Enter', keyCode: 13,
    }));
  }, '/feedback ' + message);
  await expect(status).toContainText('Submitting feedback…');
  await expect(task).toHaveValue('');
  await task.fill('next chat message');
  await task.press('Enter');
  await expect.poll(() => app.requests.some(r =>
    r.path.endsWith('/commands') && JSON.parse(r.body).command?.content === 'next chat message'
  )).toBe(true);
  await expect(status.locator('.composer-feedback-message')).toHaveJSProperty('textContent', message);
  await task.fill('unsent draft while feedback is pending');
  release();
  await expect(status).toHaveText('Feedback submitted');
  await expect(task).toHaveValue('unsent draft while feedback is pending');
});
