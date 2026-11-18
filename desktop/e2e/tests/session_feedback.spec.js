import { test, expect } from './support/test.js';
import { CloudHarness, authOrigin, cloudOrigin, sessionA } from './support/cloud_harness.js';

const publicOrigin = 'https://public-feedback.test';
const receipt = id => ({ id, url: `${publicOrigin}/v1/feedback/${id}` });
const message = '  窗口闪烁\nsecond line  ';

test('Cloud feedback sends the verbatim command body from the latest history page', async ({ page }) => {
  const app = new CloudHarness(page);
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
  let status;
  let response;
  await page.route(`${cloudOrigin}/v1/sessions/${sessionA}/feedback`, async route => {
    const request = route.request();
    const form = await new Response(request.postDataBuffer(), { headers: {
      'content-type': request.headers()['content-type'],
    } }).formData();
    posts.push({ method: request.method(), auth: request.headers().authorization, parts: [...form.keys()], metadata: JSON.parse(form.get('metadata')) });
    await route.fulfill({ status, json: response });
  });
  await page.goto(`${authOrigin}/cloud/session/${sessionA}`);
  await expect(page.locator('#transcript .msg.user .msg-content')).toHaveText(['Persisted question (80)']);
  const task = page.locator('#task');
  await task.fill('/feed');
  const completion = page.locator('.completion-item').filter({ hasText: '/feedback' });
  await expect(completion).toContainText('Include runtime environment details. Anyone with the link can read your feedback and the full conversation.');
  await completion.click();
  await expect(task).toHaveValue('/feedback ');
  await expect(page.locator('#send')).toBeDisabled();
  await task.fill('/feedback ' + message);
  for (const [code, reason] of [[500, 'session export unavailable'], [413, 'transcript too large'], [502, 'storage unavailable']]) {
    status = code;
    response = { error: reason };
    await task.press('Enter');
    await expect(page.getByText(`Feedback failed (HTTP ${code}): ${reason}`)).toBeVisible();
    await expect(task).toHaveValue('/feedback ' + message);
  }
  status = 201;
  for (const invalid of [{ id: 'fb_cloud' }, { id: 'fb_cloud', url: 'javascript:alert(1)' }]) {
    response = invalid;
    await task.press('Enter');
    await expect(page.getByText('Invalid feedback receipt.').last()).toBeVisible();
    await expect(task).toHaveValue('/feedback ' + message);
    await expect(page.locator('#send')).toBeEnabled();
  }
  response = receipt('fb_cloud');
  await page.locator('#send').click();
  const link = page.getByRole('link', { name: /Feedback submitted.*fb_cloud/ });
  await expect(link).toHaveAttribute('href', response.url);
  await page.context().route(response.url, route => route.fulfill({ body: 'Feedback' }));
  const opened = page.waitForEvent('popup');
  await link.click();
  const popup = await opened;
  await expect(popup).toHaveURL(response.url);
  await popup.close();
  await expect(task).toHaveValue('');
  expect(posts).toHaveLength(6);
  for (const post of posts) {
    expect(post).toEqual({ method: 'POST', auth: 'Bearer ts_fixture-123', parts: ['metadata'], metadata: {
      message, environment: { client: 'browser', app_version: process.env.SEEKMOON_BROWSER_RELEASE || 'unknown', platform: expect.any(String), locale: expect.any(String), user_agent: expect.any(String) },
    } });
  }
  expect(app.requests.filter(request => request.path.endsWith('/messages'))).toHaveLength(1);
  expect(app.requests.filter(request => request.path.endsWith('/commands') || request.path.endsWith('/export'))).toHaveLength(0);
  await page.getByRole('button', { name: 'Settings', exact: true }).click();
  await page.getByRole('tab', { name: 'Account', exact: true }).click();
  await page.getByRole('region', { name: 'Account', exact: true }).getByRole('button', { name: 'Sign out', exact: true }).click();
  await expect(page.locator('.feedback-receipt')).toHaveCount(0);
  expect(app.device.pageErrors).toEqual([]);
});

test('Local feedback targets the selected host session and displays its receipt', async ({ page }) => {
  const app = new CloudHarness(page, { desktop: true });
  await app.install();
  const original = app.device.replyFor.bind(app.device);
  let reply = { Err: 'no durable record for this conversation' };
  app.device.replyFor = request => {
    if (request.method === 'session.feedback') return reply;
    if (request.method === 'shell.open_external') return { opened: true };
    return original(request);
  };
  await page.goto(`${authOrigin}/console/index.html?device=device-a`);
  await app.device.openSession();
  const task = page.locator('#task');
  await task.fill('/feedback ' + message);
  await task.press('Enter');
  await expect(page.getByText(reply.Err)).toBeVisible();
  await expect(task).toHaveValue('/feedback ' + message);
  reply = { Ok: receipt('fb_local') };
  await task.press('Enter');
  const link = page.getByRole('link', { name: /Feedback submitted.*fb_local/ });
  await expect(link).toHaveAttribute('href', reply.Ok.url);
  await link.click();
  await expect.poll(() => app.hostRequests.filter(r => r.method === 'shell.open_external').map(r => r.params.url)).toEqual([reply.Ok.url]);
  await expect(task).toHaveValue('');
  const requests = app.hostRequests.filter(request => request.method === 'session.feedback');
  expect(requests).toHaveLength(2);
  expect(requests[1].params).toEqual(requests[0].params);
  expect(requests[0].params.source).toMatchObject({ session: 'session-1', workspace: '/workspace', archived: false });
  expect(requests[0].params.metadata).toMatchObject({ message, environment: { client: 'desktop' } });
  expect(app.hostRequests.some(request => ['agent.start', 'session.snapshot'].includes(request.method))).toBe(false);
  expect(app.device.pageErrors).toEqual([]);
});

test('Cloud feedback releases a stalled submission and retries only on request', async ({ page }) => {
  const app = new CloudHarness(page);
  await app.install();
  await page.clock.install();
  let attempts = 0;
  await page.route(`${cloudOrigin}/v1/sessions/${sessionA}/feedback`, async route => {
    attempts++;
    if (attempts > 1) await route.fulfill({ status: 201, json: receipt('fb_retry') });
  });
  await page.goto(`${authOrigin}/cloud/session/${sessionA}`);
  const task = page.locator('#task');
  const send = page.locator('#send');
  await task.fill('/feedback ' + message);
  await send.click();
  await expect.poll(() => attempts).toBe(1);
  await expect(send).toBeDisabled();
  await page.clock.fastForward(240_000);
  await expect(page.getByText('The feedback request timed out. Delivery could not be confirmed.')).toBeVisible();
  await expect(task).toHaveValue('/feedback ' + message);
  await expect(send).toBeEnabled();
  expect(attempts).toBe(1);
  await send.click();
  const link = page.getByRole('link', { name: /Feedback submitted.*fb_retry/ });
  await expect(link).toHaveAttribute('href', receipt('fb_retry').url);
  await page.clock.fastForward(7000);
  await expect(link).toBeVisible();
  await page.locator('.feedback-receipt').getByRole('button').click();
  await expect(link).toHaveCount(0);
  await expect(task).toHaveValue('');
  expect(attempts).toBe(2);
});

test('switching accounts removes feedback links and settles a late Local receipt', async ({ page }) => {
  const app = new CloudHarness(page, { desktop: true });
  await app.install();
  const original = app.device.replyFor.bind(app.device);
  let attempts = 0;
  let finish;
  const pending = new Promise(resolve => { finish = resolve; });
  app.device.replyFor = request => {
    if (request.method !== 'session.feedback') return original(request);
    attempts++;
    if (attempts === 2) return pending;
    return { Ok: receipt('fb_' + request.params.user_id) };
  };
  await page.goto(`${authOrigin}/console/index.html?device=device-a`);
  await app.device.openSession();
  const task = page.locator('#task');
  const send = page.locator('#send');
  await task.fill('/feedback first');
  await send.click();
  const oldLink = page.getByRole('link', { name: /Feedback submitted.*fb_123/ });
  await expect(oldLink).toBeVisible();

  await task.fill('/feedback pending');
  await send.click();
  await expect.poll(() => attempts).toBe(2);
  await expect(send).toBeDisabled();
  app.userId = '456';
  await page.evaluate(origin => window.desktopEvent('openseek.auth.changed', { connected: false, server_url: origin }), authOrigin);
  await expect(oldLink).toHaveCount(0);
  finish({ Ok: receipt('fb_late') });
  await expect(send).toBeEnabled();
  await expect(page.locator('.feedback-receipt')).toHaveCount(0);
  await expect(task).toHaveValue('/feedback pending');
  await send.click();
  await expect(page.getByRole('link', { name: /Feedback submitted.*fb_456/ })).toBeVisible();
  expect(attempts).toBe(3);
});
