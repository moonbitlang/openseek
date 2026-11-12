import { test, expect } from './support/test.js';
import { CloudHarness, sessionA, sessionB, sessionC } from './support/cloud_harness.js';

const model = page => page.locator('.composer').getByRole('button', { name: 'Model', exact: true });
const effort = page => page.locator('.composer').getByRole('button', { name: 'Reasoning effort', exact: true });
const approval = page => page.locator('.composer').getByRole('button', { name: 'Approval mode', exact: true });
const requests = (cloud, method) => cloud.requests.filter(r => r.method === method);
const commands = cloud => requests(cloud, 'POST').filter(r => r.path.endsWith('/commands')).map(r => JSON.parse(r.body));
const creations = cloud => requests(cloud, 'POST').filter(r => r.path === '/v1/sessions').map(r => JSON.parse(r.body));
async function choose(page, picker, name) {
  await picker(page).click();
  await page.getByRole('listbox').getByRole('option', { name: new RegExp(`^${name}(?: ✓)?$`) }).click();
  await expect(picker(page)).toBeEnabled();
}

for (const [name, wire] of [['DeepSeek Flash', 'deepseek-flash'], ['DeepSeek Pro', 'deepseek-v4-pro']]) {
  for (const [label, thinking] of [['Off', 'no'], ['High', 'high'], ['Max', 'max']]) {
    test(`Cloud creates with ${name}/${label} and locks options until creation finishes`, async ({ page }, testInfo) => {
      const cloud = new CloudHarness(page, { desktop: name === 'DeepSeek Pro' });
      cloud.manualTasks = true;
      await cloud.install(); await cloud.goto(); await cloud.create();
      await expect(model(page)).toHaveText('DeepSeek Flash'); await expect(effort(page)).toHaveText('High');
      await choose(page, model, name); await choose(page, effort, label);
      if (wire === 'deepseek-v4-pro' && thinking === 'max') {
        await effort(page).click();
        await page.screenshot({ path: testInfo.outputPath('cloud-session-reasoning.png') });
        await page.keyboard.press('Escape');
      }
      await page.locator('#task').fill('Prepare the demo report');
      let release; cloud.pauseCreate = new Promise(resolve => { release = resolve; });
      await page.locator('#send').click();
      try {
        await expect.poll(() => creations(cloud).length).toBe(1);
        await expect(model(page)).toBeDisabled(); await expect(effort(page)).toBeDisabled(); await expect(approval(page)).toBeDisabled();
      } finally { release(); }
      await expect.poll(() => commands(cloud).length).toBe(1);
      expect(creations(cloud)).toEqual([{ approval: 'ask', model: wire, thinking }]);
      expect(commands(cloud)[0]).not.toHaveProperty('settings');
      expect(cloud.taskSettings.get(cloud.controlState(sessionC).task_id)).toEqual({ model: wire, thinking });
      await expect(model(page)).toHaveText(name); await expect(effort(page)).toHaveText(label);
      await cloud.finishTask(sessionC);
      await expect(model(page)).toBeEnabled();
      expect(requests(cloud, 'PATCH')).toEqual([]);
      expect(cloud.device.pageErrors).toEqual([]);
    });
  }
}

test('failed creation retains draft options through navigation and retry', async ({ page }) => {
  const cloud = new CloudHarness(page);
  cloud.createStatus = 503; cloud.manualTasks = true;
  await cloud.install(); await cloud.goto(); await cloud.create();
  await choose(page, model, 'DeepSeek Pro'); await choose(page, effort, 'Off');
  await page.locator('#task').fill('Keep the draft'); await page.locator('#send').click();
  await expect(model(page)).toBeEnabled(); await expect(page.locator('#task')).toHaveValue('Keep the draft');
  await cloud.open(sessionA);
  await expect(model(page)).toHaveText('DeepSeek Flash'); await expect(effort(page)).toHaveText('High');
  await cloud.create();
  await expect(model(page)).toHaveText('DeepSeek Pro'); await expect(effort(page)).toHaveText('Off');
  cloud.createStatus = 201;
  await page.locator('#send').click();
  await expect.poll(() => commands(cloud).length).toBe(1);
  expect(creations(cloud)).toEqual(Array(2).fill({ approval: 'ask', model: 'deepseek-v4-pro', thinking: 'no' }));
  await cloud.create();
  await expect(model(page)).toHaveText('DeepSeek Flash'); await expect(effort(page)).toHaveText('High');
  expect(cloud.device.pageErrors).toEqual([]);
});

test('session PATCH holds sending, handles failures and restores saved options from the list', async ({ page }, testInfo) => {
  const cloud = new CloudHarness(page);
  await cloud.install(); await cloud.goto(); await cloud.open();
  await page.locator('#task').fill('Use the saved options');
  let release; cloud.pausePatch = new Promise(resolve => { release = resolve; });
  await model(page).click();
  await page.getByRole('listbox').getByRole('option', { name: 'DeepSeek Pro', exact: true }).click();
  try {
    await expect.poll(() => requests(cloud, 'PATCH').length).toBe(1);
    await expect(model(page)).toBeDisabled(); await expect(effort(page)).toBeDisabled(); await expect(approval(page)).toBeDisabled();
    await expect(page.locator('#send')).toBeDisabled();
    await expect(model(page)).toHaveText('DeepSeek Flash');
  } finally { release(); cloud.pausePatch = null; }
  await expect(model(page)).toHaveText('DeepSeek Pro'); await expect(model(page)).toBeEnabled();
  cloud.patchStatus = 409;
  await choose(page, effort, 'Max');
  await expect(effort(page)).toHaveText('High');
  await expect(page.getByText('The session became busy before the settings were saved. Choose them again when it is idle.', { exact: true })).toBeVisible();
  cloud.patchStatus = 503;
  await choose(page, effort, 'Off');
  await expect(effort(page)).toHaveText('High');
  await expect(page.getByText('Cloud answered HTTP 503. Try again.', { exact: true })).toBeVisible();
  cloud.patchStatus = 204;
  await choose(page, effort, 'Off'); await expect(effort(page)).toHaveText('Off');
  await cloud.open(sessionB);
  await expect(model(page)).toHaveText('DeepSeek Flash'); await expect(effort(page)).toHaveText('High');
  await page.reload(); await page.getByRole('button', { name: 'Chat', exact: true }).click(); await cloud.open(sessionA);
  await expect(model(page)).toHaveText('DeepSeek Pro'); await expect(effort(page)).toHaveText('Off');
  await model(page).click(); await page.screenshot({ path: testInfo.outputPath('cloud-session-model.png') }); await page.keyboard.press('Escape');
  expect(requests(cloud, 'PATCH').map(r => JSON.parse(r.body))).toEqual([{ model: 'deepseek-v4-pro' }, { thinking: 'max' }, { thinking: 'no' }, { thinking: 'no' }]);
  await page.locator('#task').fill('Use the saved options'); await page.locator('#send').click();
  await expect.poll(() => commands(cloud).length).toBe(1);
  expect(commands(cloud)[0]).not.toHaveProperty('settings');
  expect([...cloud.taskSettings.values()][0]).toEqual({ model: 'deepseek-v4-pro', thinking: 'no' });
  expect(cloud.device.pageErrors).toEqual([]);
});

test('running turns and automatic queues keep the saved engine options', async ({ page }) => {
  const cloud = new CloudHarness(page);
  cloud.manualTasks = true; cloud.device.hostSettings.followup_behavior = 'queue';
  await cloud.install(); await cloud.goto(); await cloud.open();
  await page.locator('#task').fill('First turn'); await page.locator('#send').click();
  await expect(page.locator('#stop')).toBeEnabled();
  await expect(model(page)).toBeDisabled(); await expect(effort(page)).toBeDisabled();
  const first = cloud.controlState(sessionA).task_id;
  await page.locator('#task').fill('Queued turn'); await page.locator('#send').click();
  await expect.poll(() => cloud.controlState(sessionA).data.queue.length).toBe(1);
  const queued = cloud.controlState(sessionA).data.queue[0];
  await cloud.emitSessionEvent(sessionA, 'task_finished', { status: 'completed' }, { task: first });
  await cloud.emitSessionEvent(sessionA, 'task_started', { submission_id: queued.id, previous_task_id: first }, { task: 'queued-next' });
  expect(cloud.taskSettings.get('queued-next')).toEqual({ model: 'deepseek-flash', thinking: 'high' });
  await expect(model(page)).toBeDisabled();
  await page.locator('#stop').click(); await cloud.finishTask(sessionA, 'aborted');
  await choose(page, model, 'DeepSeek Pro'); await choose(page, effort, 'Max');
  await page.locator('#task').fill('New ordinary turn'); await page.locator('#send').click();
  await expect.poll(() => commands(cloud).length).toBe(3);
  expect(commands(cloud).every(body => !('settings' in body))).toBe(true);
  await expect.poll(() => cloud.taskSettings.get(cloud.controlState(sessionA).task_id)).toEqual({ model: 'deepseek-v4-pro', thinking: 'max' });
  expect(cloud.device.pageErrors).toEqual([]);
});

test('late saves stay with their session and account changes restore the new account catalog', async ({ page }) => {
  const cloud = new CloudHarness(page);
  await cloud.install(); await cloud.goto(); await cloud.open(sessionA);
  let release; cloud.pausePatch = new Promise(resolve => { release = resolve; });
  await model(page).click(); await page.getByRole('listbox').getByRole('option', { name: 'DeepSeek Pro', exact: true }).click();
  await expect.poll(() => requests(cloud, 'PATCH').length).toBe(1);
  await cloud.open(sessionB);
  release(); cloud.pausePatch = null;
  await expect.poll(() => cloud.sessionSettings.get(sessionA)?.model).toBe('deepseek-v4-pro');
  await expect(model(page)).toHaveText('DeepSeek Flash'); await expect(effort(page)).toHaveText('High');
  await cloud.open(sessionA); await expect(model(page)).toHaveText('DeepSeek Pro');
  await page.getByRole('button', { name: 'Settings', exact: true }).click();
  await page.getByRole('tab', { name: 'Account', exact: true }).click();
  const account = page.getByRole('region', { name: 'Account', exact: true });
  await account.getByRole('button', { name: 'Sign out', exact: true }).click();
  await expect(account.getByRole('button', { name: 'Sign in', exact: true })).toBeVisible();
  cloud.userId = '789'; cloud.sessionSettings.set(sessionA, { model: 'deepseek-flash', thinking: 'max' });
  await account.getByRole('button', { name: 'Sign in', exact: true }).click(); await cloud.open(sessionA);
  await expect(model(page)).toHaveText('DeepSeek Flash'); await expect(effort(page)).toHaveText('Max');
  expect(cloud.device.pageErrors).toEqual([]);
});
