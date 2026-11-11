import { test, expect } from './support/test.js';
import { CloudHarness, sessionA } from './support/cloud_harness.js';

async function menu(page, cloud, id = sessionA) {
  await cloud.rowContainer(id).hover();
  await cloud.rowContainer(id).getByRole('button', { name: 'Conversation actions', exact: true }).click();
}

async function rename(page, cloud, title) {
  await menu(page, cloud);
  await page.getByRole('menuitem', { name: 'Rename…', exact: true }).click();
  const field = page.getByRole('textbox', { name: 'Rename conversation', exact: true });
  await field.fill(title);
  return field;
}

const patches = cloud => cloud.requests.filter(request => request.method === 'PATCH');

{
  const desktop = false;

  test(`${desktop ? 'desktop' : 'browser'} Cloud renames through the shared field and keeps its manual title after sending and reload`, async ({ page }) => {
    const cloud = new CloudHarness(page, { desktop });
    await cloud.install();
    await cloud.goto();
    await cloud.open();
    const field = await rename(page, cloud, '  Release planning  ');
    await field.press('Enter');
    await expect(field).toHaveCount(0);
    await expect(cloud.row(sessionA)).toHaveText('Release planning');
    await expect(page.locator('main h1')).toHaveText('Release planning');
    expect(patches(cloud).map(request => JSON.parse(request.body))).toEqual([{ title: 'Release planning' }]);
    expect(patches(cloud)[0].path).toBe(`/v1/sessions/${sessionA}`);
    expect(patches(cloud)[0].headers.authorization).toBe('Bearer ts_fixture-123');
    await page.locator('#task').fill('Continue the plan');
    await page.getByRole('button', { name: 'Send', exact: true }).click();
    await expect(page.locator('#transcript')).toContainText('calculation complete');
    await expect(page.locator('main h1')).toHaveText('Release planning');
    await page.reload();
    await page.getByRole('button', { name: 'Chat', exact: true }).click();
    await cloud.open();
    await expect(page.locator('main h1')).toHaveText('Release planning');
    expect(cloud.device.pageErrors).toEqual([]);
  });
}

