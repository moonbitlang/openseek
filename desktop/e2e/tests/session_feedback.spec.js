import { test, expect } from './support/test.js';
import { CloudHarness, authOrigin, cloudOrigin, sessionA } from './support/cloud_harness.js';

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
  let status = 502;
  let response = { error: 'storage unavailable' };
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
  await page.locator('.completion-item').filter({ hasText: '/feedback' }).click();
  await expect(task).toHaveValue('/feedback ');
  await expect(page.locator('#send')).toBeDisabled();
  await task.fill('/feedback ' + message);
  await task.press('Enter');
  await expect(page.getByText(/HTTP 502.*storage unavailable/)).toBeVisible();
  await expect(task).toHaveValue('/feedback ' + message);
  status = 201;
  response = { id: 'fb_cloud', transcript_error: 'session export unavailable' };
  await page.locator('#send').click();
  await expect(page.getByText(/fb_cloud.*Transcript not attached.*session export unavailable/)).toBeVisible();
  await expect(task).toHaveValue('');
  expect(posts).toHaveLength(2);
  for (const post of posts) {
    expect(post).toEqual({ method: 'POST', auth: 'Bearer ts_fixture-123', parts: ['metadata'], metadata: {
      message, environment: { client: 'browser', app_version: expect.any(String), platform: expect.any(String), locale: expect.any(String), user_agent: expect.any(String) },
    } });
  }
  expect(app.requests.filter(request => request.path.endsWith('/messages'))).toHaveLength(1);
  expect(app.requests.filter(request => request.path.endsWith('/commands') || request.path.endsWith('/export'))).toHaveLength(0);
  expect(app.device.pageErrors).toEqual([]);
});

test('Local feedback targets the selected host session and displays its receipt', async ({ page }) => {
  const app = new CloudHarness(page, { desktop: true });
  await app.install();
  const original = app.device.replyFor.bind(app.device);
  app.device.replyFor = request => request.method === 'session.feedback' ? { Ok: { id: 'fb_local' } } : original(request);
  await page.goto(`${authOrigin}/console/index.html?device=device-a`);
  await app.device.openSession();
  const task = page.locator('#task');
  await task.fill('/feedback ' + message);
  await task.press('Enter');
  await expect(page.getByText(/Feedback submitted.*fb_local/)).toBeVisible();
  await expect(task).toHaveValue('');
  const requests = app.hostRequests.filter(request => request.method === 'session.feedback');
  expect(requests).toHaveLength(1);
  expect(requests[0].params.source).toMatchObject({ session: 'session-1', workspace: '/workspace', archived: false });
  expect(requests[0].params.metadata).toMatchObject({ message, environment: { client: 'desktop' } });
  expect(app.hostRequests.some(request => ['agent.start', 'session.snapshot'].includes(request.method))).toBe(false);
  expect(app.device.pageErrors).toEqual([]);
});
