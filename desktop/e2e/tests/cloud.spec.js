import { test, expect } from '@playwright/test';
import { CloudHarness, authOrigin, cloudOrigin, sessionA, sessionB, sessionC } from './support/cloud_harness.js';

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

  test(`${desktop ? 'desktop' : 'browser'} creates Cloud directly through the existing plus button and uses the unified account`, async ({ page, context }, testInfo) => {
    const cloud = new CloudHarness(page, { desktop, cached: false });
    cloud.device.hostSettings.has_deepseek_key = false;
    await context.addCookies([{ name: 'session', value: 'fixture-account', url: authOrigin }]);
    await cloud.install();
    await cloud.goto();
    await cloud.create();
    await expect(page.getByRole('menuitem', { name: 'Local', exact: true })).toHaveCount(0);
    expect(cloud.device.requests.some(request => request.method === 'fs.create_unnamed_workspace')).toBe(false);
    await expect(page.locator('main h1')).toHaveText('New chat');
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

for (const failure of ['network', '503']) {
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
    await expect(cloud.row(sessionA)).toBeVisible();
  });
}

test('unknown submission and Busy remain blocked when recovery GET fails', async ({ page }) => {
  const cloud = new CloudHarness(page);
  await cloud.install();
  await cloud.goto();
  await cloud.open();
  for (const failure of ['disconnect', 'busy']) {
    cloud.disconnectSend = failure === 'disconnect';
    cloud.sendStatus = failure === 'busy' ? 409 : 200;
    cloud.historyStatus = 503;
    await page.locator('#task').fill(`Submitted ${failure}`);
    await page.getByRole('button', { name: 'Send', exact: true }).click();
    await expect(page.getByRole('main').getByText(/Cloud answered HTTP 503/)).toBeVisible();
    const posts = cloud.postCount;
    await page.getByRole('button', { name: 'Retry', exact: true }).click();
    await expect(page.getByRole('main').getByText(/Cloud answered HTTP 503/)).toBeVisible();
    expect(cloud.postCount).toBe(posts);
    cloud.historyStatus = 200;
    await page.getByRole('button', { name: 'Retry', exact: true }).click();
    await expect(page.locator('#task')).toBeVisible();
    await page.locator('#task').fill('Next question');
    await expect(page.getByRole('button', { name: 'Send', exact: true })).toBeEnabled();
    expect(cloud.postCount).toBe(posts);
  }
});

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

test('creation cannot steal a conversation selected while it was pending', async ({ page }) => {
  const cloud = new CloudHarness(page);
  await cloud.install();
  await cloud.goto();
  await cloud.open();
  let finish;
  cloud.pauseCreate = new Promise(resolve => { finish = resolve; });
  await page.getByRole('button', { name: 'New chat', exact: true }).click();
  await cloud.open(sessionB);
  finish();
  await expect(cloud.row(sessionC)).toBeVisible();
  await expect(cloud.row(sessionB)).toHaveAttribute('aria-current', 'true');
  await expect(page.locator('main h1')).toHaveText('Cloud fixture B');
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

test('Cloud ignores a previously saved browser key and needs no local model credential', async ({ page }) => {
  const cloud = new CloudHarness(page);
  cloud.device.hostSettings.has_deepseek_key = false;
  await page.addInitScript(owner => localStorage.setItem('seekmoon.cloud.deepseek-key.v1', JSON.stringify({ owner, value: 'fixture-private-key' })), `${authOrigin}|${cloudOrigin}|123`);
  await cloud.install();
  await cloud.goto();
  await cloud.open();
  await page.locator('#task').fill('Use the service default');
  await expect(page.getByRole('button', { name: 'Send', exact: true })).toBeEnabled();
  await page.getByRole('button', { name: 'Send', exact: true }).click();
  await expect.poll(() => cloud.postCount).toBe(1);
  const request = cloud.requests.find(request => request.method === 'POST' && request.path.endsWith('/messages'));
  expect(JSON.parse(request.body)).toEqual({ content: 'Use the service default' });
  expect(cloud.hostRequests.filter(request => request.method === 'cloud.key')).toEqual([]);
  expect(cloud.device.requests.filter(request => request.method === 'settings.set')).toEqual([]);
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

test('backend titles appear on admission and long titles use the unprefixed label', async ({ page }, testInfo) => {
  const cloud = new CloudHarness(page, { desktop: true });
  await cloud.install();
  await cloud.goto();
  await cloud.create();
  let complete;
  cloud.pauseStream = new Promise(resolve => { complete = resolve; });
  const title = 'A long conversation title with Unicode 月亮 and enough detail to exceed the sidebar width '.repeat(3);
  await page.locator('#task').fill(`  ${title}\nA second line does not belong to the title`);
  await page.getByRole('button', { name: 'Send', exact: true }).click();
  await expect(page.locator('main h1')).toHaveText(title.trim());
  await expect(cloud.row(sessionC)).toBeVisible();
  expect(cloud.postCount).toBe(1);
  await page.locator('#task').fill('Draft while the response is still generating');
  await expect(page.getByRole('button', { name: 'Send', exact: true })).toBeDisabled();
  await page.screenshot({ path: testInfo.outputPath('cloud-long-title.png'), fullPage: true });
  complete();
  await expect(page.locator('#transcript').getByText('您好 🌙 — calculation complete.', { exact: true })).toBeVisible();
  await expect(page.locator('#task')).toHaveValue('Draft while the response is still generating');
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

for (const message of ['Cloud sign-in was declined in the browser', 'Cloud sign-in timed out waiting for the browser']) {
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


test('a rejected Cloud message remains visible after successful history recovery', async ({ page }) => {
  const cloud = new CloudHarness(page);
  cloud.sendStatus = 422;
  cloud.sendErrorBody = 'Failed to deserialize the JSON body into the target type: missing field `api_key`';
  await cloud.install();
  await cloud.goto();
  await cloud.create();
  await page.locator('#task').fill('你好');
  const recovery = page.waitForResponse(response => response.request().method() === 'GET' && new URL(response.url()).pathname === `/v1/sessions/${sessionC}/messages`);
  await page.getByRole('button', { name: 'Send', exact: true }).click();
  await (await recovery).finished();
  await expect(page.locator('#transcript').getByText('Cloud answered HTTP 422. Try again.', { exact: true })).toBeVisible();
  await expect(page.locator('#task')).toHaveValue('你好');
  await expect(page.getByRole('button', { name: 'Send', exact: true })).toBeEnabled();
  expect(cloud.postCount).toBe(1);
  cloud.sendStatus = 200;
  await page.getByRole('button', { name: 'Send', exact: true }).click();
  await expect(page.locator('#transcript').getByText('您好 🌙 — calculation complete.', { exact: true })).toBeVisible();
  await expect(page.locator('#transcript').getByText('Cloud answered HTTP 422. Try again.', { exact: true })).toHaveCount(0);
  await expect(page.locator('#task')).toHaveValue('');
  expect(cloud.postCount).toBe(2);
});


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

test('Cloud steps and provider retries do not concatenate provisional text', async ({ page }) => {
  const cloud = new CloudHarness(page);
  cloud.streamEvents = [
    ['task_started', {}],
    ['assistant_delta', { content: 'Step one' }],
    ['assistant_message', { content: 'Step one' }],
    ['tool_call', { id: 'call', name: 'read', arguments: '{}' }],
    ['tool_result', { tool_call_id: 'call', tool_name: 'read', content: 'ok', is_error: false }],
    ['assistant_delta', { content: 'Unfinished step' }],
    ['step', { step: 2 }],
    ['assistant_delta', { content: 'Discarded attempt' }],
    ['stream_retry', { attempt: 2, max_attempts: 3, reason: 'fixture' }],
    ['assistant_delta', { content: 'Step two' }],
    ['assistant_message', { content: 'Step two' }],
    ['task_finished', { status: 'completed', result: { output: { answer: 'Step two' } } }],
  ];
  let first, full, unfinished, step, failed, retry, second;
  cloud.eventPauses = new Map([
    [1, new Promise(resolve => first = resolve)], [2, new Promise(resolve => full = resolve)],
    [5, new Promise(resolve => unfinished = resolve)], [6, new Promise(resolve => step = resolve)],
    [7, new Promise(resolve => failed = resolve)], [8, new Promise(resolve => retry = resolve)],
    [9, new Promise(resolve => second = resolve)],
  ]);
  await cloud.install(); await cloud.goto(); await cloud.open();
  await page.locator('#task').fill('Two steps');
  await page.getByRole('button', { name: 'Send', exact: true }).click();
  await expect(page.locator('#transcript').getByText('Step one', { exact: true })).toBeVisible();
  first();
  await expect(page.locator('#transcript .streaming')).toHaveCount(0);
  full();
  await expect(page.locator('#transcript').getByText('Unfinished step', { exact: true })).toBeVisible();
  unfinished();
  await expect(page.locator('#transcript').getByText('Unfinished step', { exact: true })).toHaveCount(0);
  await expect(page.locator('#transcript .streaming')).toHaveCount(0);
  await expect(page.locator('#transcript').getByText('step', { exact: true })).toHaveCount(0);
  step();
  await expect(page.locator('#transcript').getByText('Discarded attempt', { exact: true })).toBeVisible();
  failed();
  await expect(page.locator('#transcript').getByText('Discarded attempt', { exact: true })).toHaveCount(0);
  retry();
  await expect(page.locator('#transcript').getByText('Step two', { exact: true })).toBeVisible();
  const recovered = page.waitForResponse(response => response.request().method() === 'GET' && new URL(response.url()).pathname === `/v1/sessions/${sessionA}/messages`);
  second(); await (await recovered).finished();
  await expect(page.locator('#transcript').getByText('Step one', { exact: true })).toHaveCount(1);
  await expect(page.locator('#transcript').getByText('Step two', { exact: true })).toHaveCount(1);
  await expect(page.locator('#transcript').getByText('Discarded attempt', { exact: true })).toHaveCount(0);
  expect(cloud.device.pageErrors).toEqual([]);
});

test('Cloud previews remain owned by their conversation across navigation', async ({ page }) => {
  const cloud = new CloudHarness(page);
  cloud.streamEvents = [['task_started', {}], ['assistant_delta', { content: 'First fragment' }], ['assistant_delta', { content: ' continued' }], ['assistant_message', { content: 'First fragment continued' }], ['task_finished', { status: 'completed', result: { output: { answer: 'First fragment continued' } } }]];
  let first, second;
  cloud.eventPauses = new Map([[1, new Promise(resolve => first = resolve)], [2, new Promise(resolve => second = resolve)]]);
  await cloud.install(); await cloud.goto(); await cloud.open();
  await page.locator('#task').fill('Question A'); await page.getByRole('button', { name: 'Send', exact: true }).click();
  await expect(page.locator('#transcript').getByText('First fragment', { exact: true })).toBeVisible();
  await page.locator('#task').fill('Draft A');
  await cloud.open(sessionB); await page.locator('#task').fill('Draft B');
  first();
  await expect(page.locator('#transcript').getByText('First fragment continued', { exact: true })).toHaveCount(0);
  await cloud.open(sessionA);
  await expect(page.locator('#transcript').getByText('First fragment continued', { exact: true })).toBeVisible();
  await expect(page.locator('#task')).toHaveValue('Draft A');
  await cloud.open(sessionB);
  const recovered = page.waitForResponse(response => response.request().method() === 'GET' && new URL(response.url()).pathname === `/v1/sessions/${sessionA}/messages`);
  second(); await (await recovered).finished();
  await expect(page.locator('#task')).toHaveValue('Draft B');
  await expect(page.locator('#transcript').getByText('First fragment continued', { exact: true })).toHaveCount(0);
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

for (const desktop of [false, true]) {
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

test('Cloud-only browser navigation needs no selected or connected device', async ({ page }) => {
  const cloud = new CloudHarness(page);
  await cloud.install();
  await page.goto(`${authOrigin}/console/index.html`);
  await page.getByRole('button', { name: 'Chat', exact: true }).click();
  await cloud.open(sessionA);
  await page.locator('#task').fill('Cloud-only draft A');
  await page.getByRole('button', { name: 'Settings', exact: true }).click();
  await cloud.open(sessionB);
  const back = page.getByRole('button', { name: 'Back', exact: true });
  const forward = page.getByRole('button', { name: 'Forward', exact: true });
  const heading = page.locator('main > .topbar h1');
  await back.click(); await expect(heading).toHaveText('Settings');
  await expect(page.getByRole('heading', { name: 'Account · Remote access', exact: true })).toBeVisible();
  await back.click(); await expect(heading).toHaveText('Cloud fixture A');
  await expect(page.locator('#task')).toHaveValue('Cloud-only draft A');
  await forward.click(); await expect(heading).toHaveText('Settings');
  await forward.click(); await expect(heading).toHaveText('Cloud fixture B');
  expect(cloud.device.ticketRequests).toHaveLength(0);
  expect(cloud.device.pageErrors).toEqual([]);
});

test('Cloud history can restore Settings after the selected host disconnects', async ({ page }) => {
  const cloud = new CloudHarness(page);
  await cloud.install(); await cloud.goto(); await cloud.open();
  await expect.poll(() => Boolean(cloud.device.socket)).toBe(true);
  await page.routeWebSocket('**/v2/devices/device-a/ws?*', socket => socket.close({ code: 1001 }));
  cloud.device.socket.close({ code: 1001 });
  await page.getByRole('button', { name: 'Settings', exact: true }).click();
  await cloud.open();
  await page.getByRole('button', { name: 'Back', exact: true }).click();
  await expect(page.getByRole('heading', { name: 'Account · Remote access', exact: true })).toBeVisible();
  await expect(page.getByText('Loading destination…', { exact: true })).toHaveCount(0);
  await page.getByRole('button', { name: 'Forward', exact: true }).click();
  await expect(page.locator('main > .topbar h1')).toHaveText('Cloud fixture A');
  expect(cloud.device.pageErrors).toEqual([]);
});

test('desktop navigation restores Cloud drafts across Settings and Work', async ({ page }) => {
  const cloud = new CloudHarness(page, { desktop: true });
  await cloud.install(); await cloud.goto(); await cloud.open();
  await page.locator('#task').fill('Cloud draft across navigation');
  const heading = page.locator('main > .topbar h1');
  const back = page.getByRole('button', { name: 'Back', exact: true });
  const forward = page.getByRole('button', { name: 'Forward', exact: true });
  await page.getByRole('button', { name: 'Settings', exact: true }).click();
  await cloud.open();
  await expect(heading).toHaveText('Cloud fixture A');
  await page.getByRole('button', { name: 'Settings', exact: true }).click();
  await back.click();
  await expect(heading).toHaveText('Cloud fixture A');
  await expect(page.locator('#task')).toHaveValue('Cloud draft across navigation');
  await forward.click();
  await expect(heading).toHaveText('Settings');
  await page.getByRole('button', { name: 'Work', exact: true }).click();
  await page.getByRole('button', { name: 'Rabbita browser fixture', exact: true }).click();
  await expect(heading).toHaveText('Rabbita browser fixture');
  await back.click(); await expect(heading).toHaveText('Settings');
  await back.click(); await expect(heading).toHaveText('Cloud fixture A');
  await expect(page.locator('#task')).toHaveValue('Cloud draft across navigation');
  expect(cloud.device.pageErrors).toEqual([]);
});

test('late Cloud creation cannot steal a project New chat or its draft', async ({ page }) => {
  const cloud = new CloudHarness(page, { desktop: true });
  await cloud.install(); await cloud.goto(); await cloud.open();
  let complete;
  cloud.pauseCreate = new Promise(resolve => complete = resolve);
  try {
    await page.getByRole('button', { name: 'New chat', exact: true }).click();
    await page.getByRole('button', { name: 'Work', exact: true }).click();
    await page.locator('.workspace-row', { hasText: 'workspace' }).hover();
    await page.getByRole('button', { name: 'New conversation in this project', exact: true }).click();
    await expect(page.locator('main > .topbar h1')).toHaveText('New chat');
    await page.locator('#task').fill('Work draft during Cloud creation');
    complete();
    await expect.poll(() => cloud.requests.filter(request => request.method === 'GET' && request.path === '/v1/sessions').length).toBeGreaterThan(1);
    await page.getByRole('button', { name: 'Chat', exact: true }).click();
    await expect(cloud.row(sessionC)).toHaveAttribute('aria-current', 'false');
    await expect(page.locator('#task')).toHaveValue('Work draft during Cloud creation');
    expect(cloud.device.pageErrors).toEqual([]);
  } finally {
    complete();
  }
});
