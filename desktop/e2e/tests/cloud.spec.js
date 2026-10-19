import { test, expect } from '@playwright/test';
import { CloudHarness, authOrigin, sessionA, sessionB, sessionC } from './support/cloud_harness.js';

for (const desktop of [false, true]) {
  test(`${desktop ? 'desktop' : 'browser'} restores Cloud in the ordinary chat UI without an online device`, async ({ page }) => {
    const cloud = new CloudHarness(page, { desktop });
    cloud.apiOffline = true;
    await cloud.install();
    await cloud.goto();
    await cloud.open();
    await expect(cloud.row(sessionA)).toHaveText('Cloud fixture A');
    await expect(page.locator('main h1')).toHaveText('Cloud fixture A');
    await expect(page.locator('#task')).toBeVisible();
    expect(cloud.exchangeCount).toBe(0);
    expect(cloud.hostRequests.filter(request => request.method === 'cloud.authorize')).toEqual([]);
    expect(cloud.requests.filter(request => request.path === '/v1/auth/cloud/authorize')).toEqual([]);
    expect(cloud.device.pageErrors).toEqual([]);
  });

  test(`${desktop ? 'desktop' : 'browser'} creates Cloud on first send through the existing composer and unified account`, async ({ page, context }, testInfo) => {
    const cloud = new CloudHarness(page, { desktop, cached: false });
    cloud.device.hostSettings.has_deepseek_key = false;
    await context.addCookies([{ name: 'session', value: 'fixture-account', url: authOrigin }]);
    await cloud.install();
    await cloud.goto();
    await cloud.create();
    await expect(page.getByRole('menuitem', { name: 'Local', exact: true })).toHaveCount(0);
    expect(cloud.device.requests.some(request => request.method === 'fs.create_unnamed_workspace')).toBe(false);
    await expect(page.locator('main h1')).toHaveText('New chat');
    expect(cloud.requests.filter(request => request.method === 'POST' && request.path === '/v1/sessions')).toHaveLength(0);
    await page.locator('#task').fill('Calculate 1 + 1');
    await page.getByRole('button', { name: 'Send', exact: true }).click();
    await expect(page.locator('#transcript').getByText('您好 🌙 — calculation complete.', { exact: true })).toHaveCount(1);
    await expect(page.locator('main h1')).toHaveText('Calculate 1 + 1');
    await expect(page.locator('#task')).toHaveValue('');
    expect(cloud.exchangeCount).toBe(0);
    const send = cloud.requests.find(request => request.method === 'POST' && request.path.endsWith('/messages'));
    expect(JSON.parse(send.body)).toEqual({ content: 'Calculate 1 + 1' });
    expect(cloud.hostRequests.filter(request => request.method === 'cloud.key')).toEqual([]);
    expect(send.headers.cookie).toBeUndefined();
    expect(send.headers.authorization).toMatch(/^Bearer ts_fixture-/);
    expect(cloud.requests.filter(request => request.path.startsWith('/v1/auth/cloud/'))).toEqual([]);
    expect(cloud.hostRequests.filter(request => request.method === 'cloud.authorize')).toEqual([]);
    expect(await page.evaluate(() => localStorage.getItem('seekmoon.cloud.token.v1'))).toBeNull();
    expect(cloud.device.pageErrors).toEqual([]);
    await page.screenshot({ path: testInfo.outputPath(`cloud-${desktop ? 'desktop' : 'browser'}.png`), fullPage: true });
  });
}

test('browser login and session recovery use only v2 account endpoints', async ({ page }) => {
  const cloud = new CloudHarness(page, { cached: false });
  await cloud.install();
  await page.goto(`${authOrigin}/console/index.html?device=device-a`);
  const login = page.getByRole('link', { name: /Sign in.*GitHub/i });
  await expect(login).toHaveAttribute('href', /^\/v2\/auth\/login\?/);
  await page.getByRole('button', { name: 'Settings', exact: true }).click();
  const recovered = page.waitForResponse(response => new URL(response.url()).pathname === '/v2/auth/session');
  await page.getByRole('main').getByRole('button', { name: 'Sign in', exact: true }).click();
  await recovered;
  await page.getByRole('button', { name: 'Chat', exact: true }).click();
  await expect(cloud.row(sessionA)).toBeVisible();
  expect(cloud.requests.filter(request => request.side === 'api' && request.path === '/v2/auth/login')).toHaveLength(1);
  expect(cloud.requests.filter(request => request.side === 'api' && request.path === '/v2/auth/session' && request.method === 'POST')).toHaveLength(1);
  expect(cloud.requests.filter(request => request.side === 'api' && request.path.startsWith('/v1/'))).toEqual([]);
  expect(cloud.device.pageErrors).toEqual([]);
});

{
  const failure = 'network';

  test(`Cloud ${failure} preserves credentials and retries through the normal chat entry`, async ({ page }) => {
    const cloud = new CloudHarness(page);
    cloud.listOffline = failure === 'network';
    cloud.listStatus = failure === '503' ? 503 : 200;
    await cloud.install();
    await page.goto(`${authOrigin}/console/index.html?device=device-a`);
    await page.getByRole('button', { name: 'Chat', exact: true }).click();
    await expect(page.locator('aside')).toContainText(failure === 'network' ? 'Cloud is unreachable' : 'Cloud answered HTTP 503');
    expect(await page.evaluate(() => localStorage.getItem('seekmoon.account.v1'))).toContain('ts_fixture-123');
    cloud.listOffline = false;
    cloud.listStatus = 200;
    await cloud.create();
    expect(cloud.exchangeCount).toBe(0);
    await page.locator('#task').fill('First message after reconnect');
    await page.locator('#task').press('Enter');
    await expect(cloud.row(sessionA)).toBeVisible();
  });
}

test('drafts and task admission stay owned by the existing composer during generation', async ({ page }) => {
  const cloud = new CloudHarness(page);
  await cloud.install();
  await cloud.goto();
  await cloud.open();
  let admit, complete;
  cloud.pauseSend = new Promise(resolve => { admit = resolve; });
  cloud.pauseStream = new Promise(resolve => { complete = resolve; });
  await page.locator('#task').fill('Submitted question');
  await page.getByRole('button', { name: 'Send', exact: true }).click();
  await expect.poll(() => cloud.postCount).toBe(1);
  await page.locator('#task').fill('Draft before admission');
  await page.locator('#task').press('Enter');
  expect(cloud.postCount).toBe(1);
  admit();
  await expect(page.locator('#transcript').getByText('Submitted question', { exact: true })).toBeVisible();
  await expect(page.locator('#task')).toHaveValue('Draft before admission');
  await page.locator('#task').fill('Draft after admission');
  const bHistoryLoads = cloud.requests.filter(request => request.method === 'GET' && request.path === `/v1/sessions/${sessionB}/messages`).length;
  let loadB;
  cloud.pauseHistory = new Promise(resolve => { loadB = resolve; });
  await cloud.row(sessionB).click();
  await expect(cloud.row(sessionB)).toHaveAttribute('aria-current', 'true');
  await expect.poll(() => cloud.requests.filter(request => request.method === 'GET' && request.path === `/v1/sessions/${sessionB}/messages`).length).toBe(bHistoryLoads + 1);
  await expect(page.locator('#task')).toHaveCount(0);
  cloud.pauseHistory = null;
  loadB();
  await expect(page.locator('#task')).toBeVisible();
  await page.locator('#task').fill('Second conversation draft');
  // Empty drafts disable Send. After filling cold B, enabled Send proves the
  // editor and recovered history belong to B; A is still generating.
  await expect(page.getByRole('button', { name: 'Send', exact: true })).toBeEnabled();
  await expect(page.locator('#task')).toHaveValue('Second conversation draft');
  await expect(cloud.row(sessionA).locator('..').locator('.sidebar-run-status.running')).toHaveCount(1);
  const recoveredA = page.waitForResponse(response => response.request().method() === 'GET' && new URL(response.url()).pathname === `/v1/sessions/${sessionA}/messages`);
  complete();
  await (await recoveredA).finished();
  await expect(cloud.row(sessionA).locator('..').locator('.sidebar-run-status.running')).toHaveCount(0);
  await expect(page.locator('#task')).toHaveValue('Second conversation draft');
  await cloud.open(sessionA);
  await expect(page.locator('#task')).toHaveValue('Draft after admission');
  await expect(page.getByRole('button', { name: 'Send', exact: true })).toBeEnabled();
  await cloud.open(sessionB);
  await expect(page.getByRole('button', { name: 'Send', exact: true })).toBeEnabled();
  await expect(page.locator('#task')).toHaveValue('Second conversation draft');
  expect(cloud.postCount).toBe(1);
});

test('browser account sign-out clears Cloud and never signs out the computer', async ({ page }) => {
  const cloud = new CloudHarness(page);
  await cloud.install();
  await cloud.goto();
  await cloud.open();
  await page.getByRole('button', { name: 'Settings', exact: true }).click();
  const section = page.locator('.settings-group', { has: page.getByRole('heading', { name: 'Account · Remote access', exact: true }) });
  await section.getByRole('button', { name: 'Sign out', exact: true }).click();
  expect(await page.evaluate(() => localStorage.getItem('seekmoon.cloud.token.v1'))).toBeNull();
  await expect(cloud.row(sessionA)).toBeHidden();
  expect(cloud.requests.filter(request => request.path === '/v2/auth/logout')).toHaveLength(1);
  expect(cloud.hostRequests.filter(request => request.method === 'auth.disconnect')).toEqual([]);
});

test('missing service credentials show a server configuration error without asking for a user key', async ({ page }) => {
  const cloud = new CloudHarness(page);
  cloud.sendStatus = 503;
  cloud.sendErrorBody = 'server model credentials are not configured';
  await cloud.install();
  await cloud.goto();
  await cloud.open();
  await page.locator('#task').fill('Keep this draft');
  await page.getByRole('button', { name: 'Send', exact: true }).click();
  const notice = page.locator('.sidebar-notice').filter({ hasText: 'Cloud model credentials are not configured. Contact the service administrator.' });
  await expect(notice).toHaveText('Cloud model credentials are not configured. Contact the service administrator.');
  await expect(notice).toHaveAttribute('title', 'Cloud model credentials are not configured. Contact the service administrator.');
  expect(await notice.evaluate(element => getComputedStyle(element).whiteSpace)).toBe('normal');
  await expect(page.locator('#task')).toHaveValue('Keep this draft');
  await expect(page.getByRole('button', { name: 'Send', exact: true })).toBeEnabled();
  await expect(page.getByRole('button', { name: 'Set API key', exact: true })).toHaveCount(0);
  cloud.sendStatus = 200;
  await page.getByRole('button', { name: 'Send', exact: true }).click();
  await expect(page.locator('#task')).toHaveValue('');
  await expect(notice).toHaveCount(0);
});

test('Cloud selection replies use the shared composer without a device or account API session', async ({ page }) => {
  const cloud = new CloudHarness(page);
  cloud.apiOffline = true;
  cloud.histories.set(sessionA, { messages: [{ id: 1, task_id: 'old-task', kind: 'assistant_message', data: { content: 'Selectable Cloud answer.' }, created_at: 1000 }], generating: false, outcome: null });
  await cloud.install();
  await cloud.goto();
  await cloud.open();
  const task = page.locator('#task');
  await task.fill('Existing draft');
  await page.locator('#transcript .msg-content').getByText('Selectable Cloud answer.', { exact: true }).dblclick({ position: { x: 8, y: 8 } });
  await page.getByRole('toolbar', { name: 'Selection actions' }).getByRole('button', { name: 'Reply', exact: true }).click();
  const reply = page.getByRole('dialog', { name: 'Reply to selection' });
  await expect(reply.locator('blockquote')).toHaveText('Selectable');
  await reply.getByRole('textbox', { name: 'Reply', exact: true }).fill('Quoted reply');
  await reply.getByRole('checkbox', { name: 'Batch', exact: true }).check();
  await reply.getByRole('button', { name: 'Add to message', exact: true }).click();
  await expect(reply).toBeHidden();
  await expect(task).toHaveValue('Existing draft\n\n> Selectable\n\nQuoted reply\n\n');
  await task.pressSequentially('More detail');
  const content = await task.inputValue();
  await page.getByRole('button', { name: 'Send', exact: true }).click();
  await expect.poll(() => cloud.postCount).toBe(1);
  const request = cloud.requests.find(request => request.method === 'POST' && request.path.endsWith('/messages'));
  expect(JSON.parse(request.body).content).toBe(content);
  await expect(task).toHaveValue('');
  expect(cloud.device.pageErrors).toEqual([]);
});

test('Work and Cloud preserve their drafts and local send behavior', async ({ page }) => {
  const cloud = new CloudHarness(page);
  cloud.meStatus = 200;
  await cloud.install();
  await cloud.goto();
  await expect(page.getByRole('button', { name: 'Rabbita browser fixture', exact: true })).toHaveCount(0);
  await cloud.open();
  await page.locator('#task').fill('Cloud draft');
  await page.getByRole('button', { name: 'Work', exact: true }).click();
  const local = page.getByRole('button', { name: 'Rabbita browser fixture', exact: true });
  await local.click();
  await expect(local).toHaveAttribute('aria-current', 'true');
  await expect(page.locator('main > .topbar h1')).toHaveText('Rabbita browser fixture');
  await page.locator('#task').fill('Local draft');
  await page.getByRole('button', { name: 'Chat', exact: true }).click();
  await cloud.open();
  await expect(page.locator('#task')).toHaveValue('Cloud draft');
  await page.getByRole('button', { name: 'Work', exact: true }).click();
  await local.click();
  await expect(page.locator('#task')).toHaveValue('Local draft');
  await page.getByRole('button', { name: 'Send', exact: true }).click();
  await expect.poll(() => cloud.device.requests.find(request => request.method === 'agent.start')?.params.task).toBe('Local draft');
  expect(cloud.postCount).toBe(0);
  expect(cloud.device.pageErrors).toEqual([]);
});

{
  const message = 'Cloud sign-in was declined in the browser';

  test(`desktop preserves the Cloud sign-in failure: ${message}`, async ({ page }) => {
    const cloud = new CloudHarness(page, { desktop: true, cached: false });
    cloud.authorizationError = message;
    await cloud.install();
    await cloud.goto();
    await page.getByRole('button', { name: 'New chat', exact: true }).click();
    await page.getByRole('button', { name: 'Settings', exact: true }).click();
    await expect(page.getByText(message, { exact: true })).toBeVisible();
    expect(cloud.hostRequests.filter(request => request.method === 'auth.connect')).toHaveLength(1);
    expect(cloud.exchangeCount).toBe(0);
  });
}

test('Cloud renders each text fragment before completion and replaces the preview once', async ({ page }) => {
  const cloud = new CloudHarness(page);
  cloud.streamEvents = [
    ['task_started', {}],
    ['assistant_delta', { content: '你' }],
    ['assistant_delta', { content: '好 🌙' }],
    ['assistant_message', { content: '你好 🌙' }],
    ['task_finished', { status: 'completed', result: { output: { answer: '你好 🌙' } } }],
  ];
  let first, second, final;
  cloud.eventPauses = new Map([
    [1, new Promise(resolve => first = resolve)],
    [2, new Promise(resolve => second = resolve)],
    [3, new Promise(resolve => final = resolve)],
  ]);
  await cloud.install();
  await cloud.goto();
  await cloud.open();
  await page.locator('#task').fill('Stream the reply');
  await page.getByRole('button', { name: 'Send', exact: true }).click();
  await expect(page.locator('#transcript').getByText('你', { exact: true })).toBeVisible();
  await expect(page.locator('#transcript').getByText('你好 🌙', { exact: true })).toHaveCount(0);
  first();
  await expect(page.locator('#transcript').getByText('你好 🌙', { exact: true })).toHaveCount(1);
  second();
  await expect(page.locator('#transcript .streaming')).toHaveCount(0);
  await expect(page.locator('#transcript').getByText('你好 🌙', { exact: true })).toHaveCount(1);
  const recovered = page.waitForResponse(response => response.request().method() === 'GET' && new URL(response.url()).pathname === `/v1/sessions/${sessionA}/messages`);
  final(); await (await recovered).finished();
  await expect(page.locator('#task')).toHaveValue('');
  await expect(page.locator('#transcript').getByText('你好 🌙', { exact: true })).toHaveCount(1);
  expect(cloud.device.pageErrors).toEqual([]);
});

test('Cloud disconnect replaces provisional text with authoritative history and preserves the draft', async ({ page }) => {
  const cloud = new CloudHarness(page);
  cloud.streamEvents = [['task_started', {}], ['assistant_delta', { content: 'Partial text' }], ['assistant_message', { content: 'Authoritative answer' }], ['task_finished', { status: 'completed', result: { output: { answer: 'Authoritative answer' } } }]];
  cloud.disconnectStreamAfter = 1;
  let disconnect;
  cloud.eventPauses = new Map([[1, new Promise(resolve => disconnect = resolve)]]);
  await cloud.install(); await cloud.goto(); await cloud.open();
  await page.locator('#task').fill('Question'); await page.getByRole('button', { name: 'Send', exact: true }).click();
  await expect(page.locator('#transcript').getByText('Partial text', { exact: true })).toBeVisible();
  await page.locator('#task').fill('Draft after admission');
  const recovered = page.waitForResponse(response => response.request().method() === 'GET' && new URL(response.url()).pathname === `/v1/sessions/${sessionA}/messages`);
  disconnect(); await (await recovered).finished();
  await expect(page.locator('#transcript').getByText('Authoritative answer', { exact: true })).toHaveCount(1);
  await expect(page.locator('#transcript').getByText('Partial text', { exact: true })).toHaveCount(0);
  await expect(page.locator('#task')).toHaveValue('Draft after admission');
  await expect(page.getByRole('button', { name: 'Send', exact: true })).toBeEnabled();
  expect(cloud.postCount).toBe(1);
  await expect(page.locator('#frontend-crash')).toHaveCount(0);
  expect(cloud.device.pageErrors).toEqual([]);
  expect(await page.evaluate(() => window.cloudUnhandledRejections)).toEqual([]);
});

test('Cloud sign-out closes the local reader even when stream cancellation rejects', async ({ page }) => {
  const cloud = new CloudHarness(page);
  cloud.rejectStreamCancel = true;
  cloud.streamEvents = [['task_started', {}], ['assistant_delta', { content: 'Partial text' }], ['assistant_message', { content: 'Authoritative answer' }], ['task_finished', { status: 'completed', result: { output: { answer: 'Authoritative answer' } } }]];
  let resume;
  cloud.eventPauses = new Map([[1, new Promise(resolve => resume = resolve)]]);
  try {
    await cloud.install(); await cloud.goto(); await cloud.open();
    await page.locator('#task').fill('Question');
    await page.getByRole('button', { name: 'Send', exact: true }).click();
    await expect(page.locator('#transcript').getByText('Partial text', { exact: true })).toBeVisible();
    await page.getByRole('button', { name: 'Settings', exact: true }).click();
    const section = page.locator('.settings-group', { has: page.getByRole('heading', { name: 'Account · Remote access', exact: true }) });
    await section.getByRole('button', { name: 'Sign out', exact: true }).click();
    await expect.poll(() => cloud.streamCancellations).toBe(1);
    resume();
    await expect(cloud.row(sessionA)).toBeHidden();
    await expect(page.locator('#frontend-crash')).toHaveCount(0);
    expect(cloud.device.pageErrors).toEqual([]);
    expect(await page.evaluate(() => window.cloudUnhandledRejections)).toEqual([]);
    expect(cloud.postCount).toBe(1);
  } finally {
    resume();
  }
});

{
  const desktop = false;

  for (const target of ['existing session', 'project new chat']) {
    test(`${desktop ? 'desktop' : 'browser'} returns from Cloud to Work ${target}`, async ({ page }) => {
      const cloud = new CloudHarness(page, { desktop });
      cloud.meStatus = 200;
      await cloud.install();
      await cloud.goto();
      await cloud.open();
      await page.locator('#task').fill('Retain Cloud draft');
      await page.getByRole('button', { name: 'Work', exact: true }).click();
      if (target === 'existing session') {
        await page.getByRole('button', { name: 'Rabbita browser fixture', exact: true }).click();
        await expect(page.locator('main > .topbar h1')).toHaveText('Rabbita browser fixture');
        await expect(page.locator('#transcript').getByText('Browser result', { exact: true })).toBeVisible();
      } else {
        await page.locator('.workspace-row', { hasText: 'workspace' }).hover();
        await page.getByRole('button', { name: 'New conversation in this project', exact: true }).click();
        await expect(page.locator('main h1')).toHaveText('New chat');
        await expect(page.getByRole('button', { name: 'Model', exact: true })).toBeEnabled();
      }
      await page.locator('#task').fill('Retain Work draft');
      await page.getByRole('button', { name: 'Chat', exact: true }).click();
      await cloud.open();
      await expect(page.locator('#task')).toHaveValue('Retain Cloud draft');
      expect(cloud.postCount).toBe(0);
      expect(cloud.device.pageErrors).toEqual([]);
    });
  }
}

test('device browser history retains Cloud visits across refresh', async ({ page }) => {
  const cloud = new CloudHarness(page);
  await cloud.install(); await cloud.goto();
  await page.getByRole('button', { name: 'Settings', exact: true }).click();
  await expect(page).toHaveURL(/\/device\/device-a\/settings$/);
  await cloud.open(sessionA);
  await page.locator('#task').fill('Cloud draft A');
  await expect(page).toHaveURL(`${authOrigin}/cloud/session/${sessionA}`);
  await cloud.open(sessionB);
  await expect(page).toHaveURL(`${authOrigin}/cloud/session/${sessionB}`);
  await page.goBack();
  await expect(page.locator('main > .topbar h1')).toHaveText('Cloud fixture A');
  await expect(page.locator('#task')).toHaveValue('Cloud draft A');
  await page.goBack();
  await expect(page.locator('main > .topbar h1')).toHaveText('Settings');
  await page.goForward();
  await expect(page.locator('main > .topbar h1')).toHaveText('Cloud fixture A');
  await page.reload();
  await expect(page.locator('main > .topbar h1')).toHaveText('Cloud fixture A');
  await expect(page.locator('#task')).toHaveValue('');
  await page.goBack();
  await expect(page.locator('main > .topbar h1')).toHaveText('Settings');
  expect(cloud.device.pageErrors).toEqual([]);
});

for (const destination of ['settings', 'not-a-page']) {
  test(`late Cloud creation cannot steal browser navigation to ${destination}`, async ({ page }) => {
    const cloud = new CloudHarness(page);
    await cloud.install(); await cloud.goto();
    await page.getByRole('button', { name: 'Settings', exact: true }).click();
    await cloud.open();
    let complete;
    cloud.pauseCreate = new Promise(resolve => { complete = resolve; });
    try {
      await page.locator('.section-primary-action[aria-label="New chat"]').click();
      await page.locator('#task').fill('First Cloud message');
      await page.locator('#task').press('Enter');
      await expect.poll(() => cloud.requests.filter(request => request.method === 'POST' && request.path === '/v1/sessions').length).toBe(1);
      if (destination !== 'not-a-page') {
        await page.getByRole('button', { name: 'Settings', exact: true }).click();
        await expect(page.locator('main > .topbar h1')).toHaveText('Settings');
      } else {
        await page.evaluate(() => {
          history.pushState(null, '', '/device/device-a/not-a-page');
          dispatchEvent(new PopStateEvent('popstate'));
        });
        await expect(page.locator('.navigation-notice')).toBeVisible();
      }
      complete();
      await expect.poll(() => cloud.requests.some(request => request.path === `/v1/sessions/${sessionC}/messages`)).toBe(true);
      // An invalid URL covers the promoted draft; only Settings leaves Chat.
      if (destination !== 'not-a-page') await expect(cloud.row(sessionC)).toHaveAttribute('aria-current', 'false');
      await expect(page).toHaveURL(new RegExp(`/device/device-a/${destination}$`));
      if (destination !== 'not-a-page') await expect(page.locator('main > .topbar h1')).toHaveText('Settings');
      else await expect(page.locator('.navigation-notice')).toBeVisible();
      expect(cloud.device.pageErrors).toEqual([]);
    } finally { complete(); }
  });
}
