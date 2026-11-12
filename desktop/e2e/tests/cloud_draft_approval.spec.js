import { test, expect } from './support/test.js';
import { CloudHarness, sessionA, sessionC } from './support/cloud_harness.js';

const picker = page => page.locator('.composer').getByRole('button', { name: 'Approval mode' });
const creations = cloud => cloud.requests.filter(r => r.method === 'POST' && r.path === '/v1/sessions');
async function choose(page, label) {
  await picker(page).click();
  await page.getByRole('listbox', { name: 'Approval mode' }).getByRole('option', { name: new RegExp(label) }).click();
}

for (const { mode, label, desktop } of [
  { mode: 'ask', label: 'Request approval', desktop: false },
  { mode: 'review', label: 'Auto-review', desktop: true },
]) {
  test(`Cloud first send creates with ${mode} on ${desktop ? 'Desktop' : 'Web'}`, async ({ page }, testInfo) => {
    const cloud = new CloudHarness(page, { desktop });
    cloud.manualTasks = true;
    await cloud.install(); await cloud.goto(); await cloud.create();
    await expect(picker(page)).toBeEnabled();
    await expect(picker(page)).toHaveText('Request approval');
    await choose(page, label);
    await expect(picker(page)).toHaveText(label);
    await page.locator('#task').fill('Create a report');
    if (mode === 'review') {
      await picker(page).click();
      await page.screenshot({ path: testInfo.outputPath('cloud-draft-approval.png') });
      await page.keyboard.press('Escape');
    }
    expect(cloud.requests.filter(r => r.method === 'POST' || r.method === 'PATCH')).toEqual([]);
    await page.getByRole('button', { name: 'Send', exact: true }).click();
    await expect.poll(() => cloud.postCount).toBe(1);
    expect(creations(cloud).map(r => JSON.parse(r.body))).toEqual([{ approval: mode, model: 'deepseek-flash', thinking: 'high' }]);
    const command = cloud.requests.find(r => r.method === 'POST' && r.path.endsWith('/commands'));
    expect(command.path).toBe(`/v1/sessions/${sessionC}/commands`);
    expect(cloud.requests.indexOf(command)).toBeGreaterThan(cloud.requests.indexOf(creations(cloud)[0]));
    expect(cloud.requests.filter(r => r.method === 'PATCH')).toEqual([]);
    await expect(picker(page)).toHaveText(label);
    await expect(picker(page)).toBeDisabled();
    expect(cloud.device.pageErrors).toEqual([]);
  });
}

test('failed creation retains its approval and draft across navigation and retry', async ({ page }) => {
  const cloud = new CloudHarness(page);
  let release;
  cloud.createStatus = 503;
  cloud.pauseCreate = new Promise(resolve => { release = resolve; });
  await cloud.install(); await cloud.goto(); await cloud.create();
  await choose(page, 'Auto-review');
  await page.locator('#task').fill('Keep my draft and approval');
  await page.getByRole('button', { name: 'Send', exact: true }).click();
  try {
    await expect.poll(() => creations(cloud).length).toBe(1);
    await expect(picker(page)).toBeDisabled();
    await expect(page.getByRole('listbox', { name: 'Approval mode' })).toHaveCount(0);
    expect(cloud.postCount).toBe(0);
  } finally { release(); }
  await expect(picker(page)).toBeEnabled();
  await expect(picker(page)).toHaveText('Auto-review');
  await expect(page.locator('#task')).toHaveValue('Keep my draft and approval');
  await cloud.open(sessionA);
  await expect(picker(page)).toHaveText('Request approval');
  // Existing sessions still update their mode through PATCH.
  await choose(page, 'Auto-review');
  await expect(picker(page)).toHaveText('Auto-review');
  expect(cloud.requests.filter(r => r.method === 'PATCH').map(r => ({ path: r.path, body: JSON.parse(r.body) })))
    .toEqual([{ path: `/v1/sessions/${sessionA}`, body: { approval: 'review' } }]);
  await cloud.create();
  await expect(picker(page)).toHaveText('Auto-review');
  await expect(page.locator('#task')).toHaveValue('Keep my draft and approval');
  cloud.createStatus = 201; cloud.pauseCreate = null;
  await page.getByRole('button', { name: 'Send', exact: true }).click();
  await expect.poll(() => cloud.postCount).toBe(1);
  expect(creations(cloud).map(r => JSON.parse(r.body))).toEqual([{ approval: 'review', model: 'deepseek-flash', thinking: 'high' }, { approval: 'review', model: 'deepseek-flash', thinking: 'high' }]);
  await expect(page.locator('#task')).toHaveValue('');
  await expect(picker(page)).toHaveText('Auto-review');
  await cloud.create();
  await expect(picker(page)).toHaveText('Request approval');
  expect(cloud.device.pageErrors).toEqual([]);
});
