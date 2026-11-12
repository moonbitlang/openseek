import { test, expect } from './support/test.js';
import { CloudHarness, sessionA, sessionB, sessionC } from './support/cloud_harness.js';

const model = page => page.locator('.composer').getByRole('button', { name: 'Model', exact: true });
const effort = page => page.locator('.composer').getByRole('button', { name: 'Reasoning effort', exact: true });
const commands = cloud => cloud.requests.filter(r => r.method === 'POST' && r.path.endsWith('/commands')).map(r => JSON.parse(r.body));
async function choose(page, picker, name) {
  await picker(page).click();
  await page.getByRole('listbox').getByRole('option', { name, exact: true }).click();
}

test('Cloud freezes submitted settings while draft choices remain editable during creation', async ({ page }, testInfo) => {
  const cloud = new CloudHarness(page, { desktop: true });
  cloud.manualTasks = true;
  await cloud.install(); await cloud.goto(); await cloud.create();
  await choose(page, model, 'DeepSeek Pro'); await choose(page, effort, 'Max');
  await page.locator('#task').fill('Prepare the demo report');
  let release;
  cloud.pauseCreate = new Promise(resolve => { release = resolve; });
  await page.locator('#send').click();
  try {
    await expect.poll(() => cloud.requests.filter(r => r.path === '/v1/sessions' && r.method === 'POST').length).toBe(1);
    await choose(page, model, 'DeepSeek Flash'); await choose(page, effort, 'Off');
  } finally { release(); }
  await expect.poll(() => commands(cloud).length).toBe(1);
  expect(commands(cloud)[0]).toMatchObject({ settings: { model: 'deepseek-v4-pro', thinking: 'max' }, command: { command: 'prompt' } });
  expect(JSON.parse(cloud.requests.find(r => r.path === '/v1/sessions' && r.method === 'POST').body)).toEqual({ approval: 'ask' });
  await expect(model(page)).toHaveText('DeepSeek Flash'); await expect(effort(page)).toHaveText('Off');
  await effort(page).click();
  await page.screenshot({ path: testInfo.outputPath('cloud-reasoning-preference.png') });
  await page.keyboard.press('Escape');
  await cloud.finishTask(sessionC);
  await page.locator('#task').fill('Next turn'); await page.locator('#send').click();
  await expect.poll(() => commands(cloud).length).toBe(2);
  expect(commands(cloud)[1].settings).toEqual({ model: 'deepseek-flash', thinking: 'no' });
  expect(cloud.requests.filter(r => r.method === 'PATCH')).toEqual([]);
  expect(cloud.device.pageErrors).toEqual([]);
});

test('Cloud preferences reopen per session and account independently of Local defaults', async ({ page }, testInfo) => {
  const cloud = new CloudHarness(page);
  await cloud.install(); await cloud.goto(); await cloud.open();
  await choose(page, model, 'DeepSeek Pro'); await choose(page, effort, 'Off');
  await cloud.open(sessionB);
  await expect(model(page)).toHaveText('DeepSeek Pro');
  await choose(page, model, 'DeepSeek Flash'); await choose(page, effort, 'Max');
  await cloud.open(sessionA);
  await expect(model(page)).toHaveText('DeepSeek Pro'); await expect(effort(page)).toHaveText('Off');
  await page.reload();
  await page.getByRole('button', { name: 'Chat', exact: true }).click();
  await cloud.open(sessionA);
  await expect(model(page)).toHaveText('DeepSeek Pro'); await expect(effort(page)).toHaveText('Off');
  await cloud.open(sessionB);
  await expect(model(page)).toHaveText('DeepSeek Flash'); await expect(effort(page)).toHaveText('Max');
  const switchAccount = async id => {
    await page.getByRole('button', { name: 'Settings', exact: true }).click();
    await page.getByRole('tab', { name: 'Account', exact: true }).click();
    const account = page.getByRole('region', { name: 'Account', exact: true });
    await account.getByRole('button', { name: 'Sign out', exact: true }).click();
    await expect(account.getByRole('button', { name: 'Sign in', exact: true })).toBeVisible();
    cloud.userId = id;
    await account.getByRole('button', { name: 'Sign in', exact: true }).click();
    await cloud.open(sessionA);
  };
  await switchAccount('789');
  await expect(model(page)).toHaveText('DeepSeek Flash'); await expect(effort(page)).toHaveText('High');
  await choose(page, effort, 'Max');
  await switchAccount('123');
  await expect(model(page)).toHaveText('DeepSeek Pro'); await expect(effort(page)).toHaveText('Off');
  await model(page).click();
  await page.screenshot({ path: testInfo.outputPath('cloud-model-preference.png') });
  await page.keyboard.press('Escape');
  expect(cloud.requests.filter(r => r.method === 'PATCH')).toEqual([]);
  expect(cloud.device.pageErrors).toEqual([]);
});

test('Cloud queued turns and running controls retain the current engine configuration', async ({ page }) => {
  const cloud = new CloudHarness(page);
  cloud.manualTasks = true; cloud.device.hostSettings.followup_behavior = 'queue';
  await cloud.install(); await cloud.goto(); await cloud.open();
  await page.locator('#task').fill('First turn'); await page.locator('#send').click();
  await expect(page.locator('#stop')).toBeEnabled();
  const first = cloud.controlState(sessionA).task_id;
  await choose(page, model, 'DeepSeek Pro'); await choose(page, effort, 'Max');
  await page.locator('#task').fill('Queued turn'); await page.locator('#send').click();
  await expect.poll(() => cloud.controlState(sessionA).data.queue.length).toBe(1);
  const queued = cloud.controlState(sessionA).data.queue[0];
  await cloud.emitSessionEvent(sessionA, 'task_finished', { status: 'completed' }, { task: first });
  await cloud.emitSessionEvent(sessionA, 'task_started', { submission_id: queued.id, previous_task_id: first }, { task: 'queued-next' });
  expect(cloud.taskSettings.get('queued-next')).toEqual({ model: 'deepseek-flash', thinking: 'high' });
  await expect(page.locator('#stop')).toBeEnabled(); await page.locator('#stop').click();
  await expect.poll(() => commands(cloud).length).toBe(2);
  expect(commands(cloud)[1]).toMatchObject({ command: { command: 'cancel' }, settings: { model: 'deepseek-v4-pro', thinking: 'max' } });
  await cloud.finishTask(sessionA, 'aborted');
  await page.locator('#task').fill('New ordinary turn'); await page.locator('#send').click();
  await expect.poll(() => commands(cloud).length).toBe(3);
  expect(commands(cloud)[2].settings).toEqual({ model: 'deepseek-v4-pro', thinking: 'max' });
  await expect.poll(() => cloud.taskSettings.get(cloud.controlState(sessionA).task_id)).toEqual(commands(cloud)[2].settings);
  expect(cloud.requests.filter(r => r.method === 'PATCH')).toEqual([]);
  expect(cloud.device.pageErrors).toEqual([]);
});

test('Cloud restores latest history settings, protects unsent edits, and retains them with 304', async ({ page }, testInfo) => {
  const cloud = new CloudHarness(page);
  const remote = { model: 'deepseek-v4-pro', thinking: 'max' };
  cloud.histories.set(sessionA, { settings: remote, messages: [], generating: false });
  await cloud.install(); await cloud.goto(); await cloud.open(sessionA);
  await expect(model(page)).toHaveText('DeepSeek Pro'); await expect(effort(page)).toHaveText('Max');
  const reads = () => cloud.requests.filter(r => r.method === 'GET' && r.path.endsWith(`${sessionA}/messages`));
  await cloud.open(sessionB);
  cloud.histories.get(sessionA).settings = { model: 'deepseek-v4-pro', thinking: 'high' };
  let release;
  cloud.pauseHistory = new Promise(resolve => { release = resolve; });
  const count = reads().length;
  await cloud.open(sessionA);
  await expect.poll(() => reads().length).toBeGreaterThan(count);
  await choose(page, model, 'DeepSeek Flash'); await choose(page, effort, 'Off');
  release(); cloud.pauseHistory = null;
  await expect(model(page)).toHaveText('DeepSeek Flash'); await expect(effort(page)).toHaveText('Off');
  await page.reload(); await page.getByRole('button', { name: 'Chat', exact: true }).click();
  await cloud.open(sessionA);
  await expect(model(page)).toHaveText('DeepSeek Pro'); await expect(effort(page)).toHaveText('High');
  const response = page.waitForResponse(r => new URL(r.url()).pathname.endsWith(`${sessionA}/messages`));
  await cloud.open(sessionB); await cloud.open(sessionA);
  expect((await response).status()).toBe(304);
  await expect(effort(page)).toHaveText('High');
  await page.screenshot({ path: testInfo.outputPath('cloud-history-settings.png') });
  // The setting changes without changing native transcript data, and must change ETag.
  cloud.histories.get(sessionA).settings = { model: 'deepseek-flash', thinking: 'high' };
  await cloud.open(sessionB); await cloud.open(sessionA);
  await expect(model(page)).toHaveText('DeepSeek Flash'); await expect(effort(page)).toHaveText('High');
  // Earlier pages carry the latest metadata too, but paging never changes the selection.
  cloud.historyTurns.set(sessionA, ['Earlier question', 'Latest question'].map((text, index) => ({
    messages: [{task_id: `task-${index}`, kind: 'user', data: {content: text}, created_at: index + 1}], events: [],
  })));
  await cloud.open(sessionB); await cloud.open(sessionA);
  await choose(page, model, 'DeepSeek Pro'); await choose(page, effort, 'Off');
  const older = page.waitForRequest(r => r.method() === 'GET' && new URL(r.url()).pathname.endsWith(`${sessionA}/messages`) && new URL(r.url()).searchParams.get('offset') === '0');
  await page.locator('#transcript').hover(); await page.mouse.wheel(0, -200);
  await older;
  await expect(page.locator('#transcript')).toContainText('Earlier question');
  await expect(model(page)).toHaveText('DeepSeek Pro'); await expect(effort(page)).toHaveText('Off');
  expect(cloud.device.pageErrors).toEqual([]);
});
