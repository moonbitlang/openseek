import { test, expect } from './support/test.js';
import { CloudHarness, sessionA, sessionB, sessionC } from './support/cloud_harness.js';

const model = page => page.locator('.composer').getByRole('button', { name: 'Model', exact: true });
const effort = page => page.locator('.composer').getByRole('button', { name: 'Reasoning effort', exact: true });
const creations = cloud => cloud.requests.filter(r => r.method === 'POST' && r.path === '/v1/sessions');
const patches = cloud => cloud.requests.filter(r => r.method === 'PATCH');
async function choose(page, control, label) {
  await control(page).click();
  await page.getByRole('listbox').getByRole('option', { name: label, exact: true }).click();
}

test('Cloud draft keeps model, thinking and approval through failed creation and first send', async ({ page }, testInfo) => {
  const cloud = new CloudHarness(page, { desktop: true });
  cloud.manualTasks = true; cloud.createStatus = 503;
  await cloud.install(); await cloud.goto(); await cloud.create();
  await expect(model(page)).toHaveText('DeepSeek Flash');
  await expect(effort(page)).toHaveText('High');
  await choose(page, model, 'DeepSeek Pro');
  await choose(page, effort, 'Max');
  await choose(page, p => p.getByRole('button', { name: 'Approval mode', exact: true }), /^Auto-review/);
  await page.locator('#task').fill('Prepare the demo report');
  await model(page).click();
  await page.screenshot({ path: testInfo.outputPath('cloud-model-picker.png') });
  await page.keyboard.press('Escape');
  let release;
  cloud.pauseCreate = new Promise(resolve => { release = resolve; });
  await page.locator('#send').click();
  try {
    await expect.poll(() => creations(cloud).length).toBe(1);
    await expect(model(page)).toBeDisabled();
    await expect(effort(page)).toBeDisabled();
  } finally { release(); }
  await expect(model(page)).toBeEnabled();
  await expect(page.locator('#task')).toHaveValue('Prepare the demo report');
  await cloud.open(sessionA);
  await expect(model(page)).toHaveText('DeepSeek Flash');
  await expect(effort(page)).toHaveText('High');
  await cloud.create();
  await expect(model(page)).toHaveText('DeepSeek Pro');
  await expect(effort(page)).toHaveText('Max');
  cloud.createStatus = 201; cloud.pauseCreate = null;
  await page.locator('#send').click();
  await expect.poll(() => cloud.postCount).toBe(1);
  expect(creations(cloud).map(r => JSON.parse(r.body))).toEqual(Array(2).fill({ approval: 'review', model: 'deepseek-v4-pro', thinking: 'max' }));
  expect(cloud.taskInference.get(cloud.controlState(sessionC).task_id)).toEqual({ model: 'deepseek-v4-pro', thinking: 'max' });
  await expect(model(page)).toHaveText('DeepSeek Pro');
  await expect(effort(page)).toHaveText('Max');
  await cloud.create();
  await expect(model(page)).toHaveText('DeepSeek Flash');
  await expect(effort(page)).toHaveText('High');
  expect(cloud.device.pageErrors).toEqual([]);
});

test('Cloud saves gate sending, expose retry, and restore per-session settings from the list', async ({ page }, testInfo) => {
  const cloud = new CloudHarness(page);
  cloud.manualTasks = true;
  await cloud.install(); await cloud.goto(); await cloud.open();
  await page.locator('#task').fill('Retain this draft');
  let release;
  cloud.patchStatus = 500;
  cloud.pausePatch = new Promise(resolve => { release = resolve; });
  await choose(page, effort, 'Off');
  try {
    await expect.poll(() => patches(cloud).length).toBe(1);
    await expect(page.locator('#send')).toBeDisabled();
    await expect(model(page)).toBeDisabled();
    expect(cloud.postCount).toBe(0);
  } finally { release(); }
  const notice = page.locator('.composer-notice').filter({ hasText: 'Saving settings failed' });
  await expect(notice).toContainText('Sending is paused');
  await expect(effort(page)).toHaveText('Off');
  await expect(page.locator('#send')).toBeDisabled();
  await expect(page.locator('#task')).toHaveValue('Retain this draft');
  await page.screenshot({ path: testInfo.outputPath('cloud-settings-failed.png') });
  await cloud.open(sessionB);
  await expect(effort(page)).toHaveText('High');
  await expect(notice).toHaveCount(0);
  await cloud.open(sessionA);
  await expect(effort(page)).toHaveText('Off');
  await expect(notice).toBeVisible();
  cloud.patchStatus = 204; cloud.pausePatch = null;
  await notice.getByRole('button', { name: 'Retry', exact: true }).click();
  await expect(notice).toHaveCount(0);
  await expect(page.locator('#send')).toBeEnabled();
  expect(patches(cloud).map(r => JSON.parse(r.body))).toEqual(Array(2).fill({ model: 'deepseek-flash', thinking: 'no' }));
  await choose(page, model, 'DeepSeek Pro');
  await expect(model(page)).toBeEnabled();
  await page.reload();
  await page.getByRole('button', { name: 'Chat', exact: true }).click();
  await cloud.open(sessionA);
  await expect(model(page)).toHaveText('DeepSeek Pro');
  await expect(effort(page)).toHaveText('Off');
  await cloud.open(sessionB);
  await expect(model(page)).toHaveText('DeepSeek Flash');
  await expect(effort(page)).toHaveText('High');
  expect(cloud.device.pageErrors).toEqual([]);
});

test('Cloud changes during generation preserve the current turn and reach the next queued turn', async ({ page }, testInfo) => {
  const cloud = new CloudHarness(page);
  cloud.device.hostSettings.followup_behavior = 'queue'; cloud.manualTasks = true;
  await cloud.install(); await cloud.goto(); await cloud.open();
  await page.locator('#task').fill('First turn');
  await page.locator('#send').click();
  await expect(page.locator('#stop')).toBeEnabled();
  const firstTask = cloud.controlState(sessionA).task_id;
  await page.locator('#task').fill('Queued second turn');
  await page.locator('#send').click();
  await expect.poll(() => cloud.controlState(sessionA).data.queue.length).toBe(1);
  const queued = cloud.controlState(sessionA).data.queue[0];
  let release;
  cloud.pausePatch = new Promise(resolve => { release = resolve; });
  await choose(page, model, 'DeepSeek Pro');
  try {
    await expect.poll(() => patches(cloud).length).toBe(1);
    await expect(page.locator('#stop')).toBeEnabled();
    await page.locator('#task').fill('Another draft');
    await expect(page.locator('#send')).toBeDisabled();
    expect(cloud.taskInference.get(firstTask)).toEqual({ model: 'deepseek-flash', thinking: 'high' });
  } finally { release(); cloud.pausePatch = null; }
  await expect(model(page)).toBeEnabled();
  await choose(page, effort, 'Max');
  await expect(effort(page)).toBeEnabled();
  await effort(page).click();
  await page.screenshot({ path: testInfo.outputPath('cloud-reasoning-picker.png') });
  await page.keyboard.press('Escape');
  expect(cloud.taskInference.get(firstTask)).toEqual({ model: 'deepseek-flash', thinking: 'high' });
  await cloud.emitSessionEvent(sessionA, 'task_finished', { status: 'completed' }, { task: firstTask });
  await cloud.emitSessionEvent(sessionA, 'task_started', { submission_id: queued.id, previous_task_id: firstTask }, { task: 'queued-next' });
  await expect(page.locator('#stop')).toBeEnabled();
  await expect(page.locator('.queued-input-row')).toHaveCount(0);
  expect(cloud.taskInference.get('queued-next')).toEqual({ model: 'deepseek-v4-pro', thinking: 'max' });
  await expect(model(page)).toHaveText('DeepSeek Pro');
  await expect(effort(page)).toHaveText('Max');
  expect(cloud.device.pageErrors).toEqual([]);
});
