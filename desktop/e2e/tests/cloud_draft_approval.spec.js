import { test, expect } from './support/test.js';
import { CloudHarness, sessionA, sessionC } from './support/cloud_harness.js';

const creations = cloud => cloud.requests.filter(r => r.method === 'POST' && r.path === '/v1/sessions');
for (const desktop of [false, true]) {
  test(`Cloud first send creates with automatic review on ${desktop ? 'Desktop' : 'Web'}`, async ({ page }, testInfo) => {
    const cloud = new CloudHarness(page, { desktop });
    cloud.manualTasks = true;
    await cloud.install(); await cloud.goto(); await cloud.create();
    await page.locator('#task').fill('Create a report');
    if (desktop) {
      await page.screenshot({ path: testInfo.outputPath('cloud-draft-approval.png') });
    }
    expect(cloud.requests.filter(r => r.method === 'POST' || r.method === 'PATCH')).toEqual([]);
    await page.getByRole('button', { name: 'Send', exact: true }).click();
    await expect.poll(() => cloud.postCount).toBe(1);
    expect(creations(cloud).map(r => JSON.parse(r.body))).toEqual([{ approval: 'review' }]);
    const command = cloud.requests.find(r => r.method === 'POST' && r.path.endsWith('/commands'));
    expect(command.path).toBe(`/v1/sessions/${sessionC}/commands`);
    expect(cloud.requests.indexOf(command)).toBeGreaterThan(cloud.requests.indexOf(creations(cloud)[0]));
    expect(cloud.requests.filter(r => r.method === 'PATCH')).toEqual([]);
    expect(cloud.device.pageErrors).toEqual([]);
  });
}

test('failed creation retains its approval and draft across navigation and retry', async ({ page }) => {
  const cloud = new CloudHarness(page);
  let release;
  cloud.createStatus = 503;
  cloud.pauseCreate = new Promise(resolve => { release = resolve; });
  await cloud.install(); await cloud.goto(); await cloud.create();
  await page.locator('#task').fill('Keep my draft and approval');
  await page.getByRole('button', { name: 'Send', exact: true }).click();
  try {
    await expect.poll(() => creations(cloud).length).toBe(1);
    await expect(page.locator('#send')).toBeDisabled();
    expect(cloud.postCount).toBe(0);
  } finally { release(); }
  await expect(page.locator('#send')).toBeEnabled();
  await expect(page.locator('#task')).toHaveValue('Keep my draft and approval');
  await cloud.open(sessionA);
  await cloud.create();
  await expect(page.locator('#task')).toHaveValue('Keep my draft and approval');
  cloud.createStatus = 201; cloud.pauseCreate = null;
  await page.getByRole('button', { name: 'Send', exact: true }).click();
  await expect.poll(() => cloud.postCount).toBe(1);
  expect(creations(cloud).map(r => JSON.parse(r.body))).toEqual([{ approval: 'review' }, { approval: 'review' }]);
  await expect(page.locator('#task')).toHaveValue('');
  await cloud.create();
  expect(cloud.device.pageErrors).toEqual([]);
});
