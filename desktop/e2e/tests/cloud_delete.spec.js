import { test, expect } from './support/test.js';
import { CloudHarness, sessionA, sessionC } from './support/cloud_harness.js';

async function menu(page, cloud, id) {
  await cloud.rowContainer(id).hover();
  await cloud.rowContainer(id).getByRole('button', { name: 'Conversation actions', exact: true }).click();
}

async function askDelete(page, cloud, id) {
  await menu(page, cloud, id);
  await page.getByRole('menuitem', { name: 'Delete…', exact: true }).click();
  await expect(page.getByRole('button', { name: 'Delete permanently', exact: true })).toBeVisible();
}

const deletes = cloud => cloud.requests.filter(request => request.method === 'DELETE');

{
  const desktop = false;

  test(`${desktop ? 'desktop' : 'browser'} deletes Cloud through the shared confirmation and stays in Chat`, async ({ page }) => {
    const cloud = new CloudHarness(page, { desktop });
    await cloud.install();
    await cloud.goto();
    await cloud.open();
    await page.locator('#task').fill('Draft that belongs to deleted A');
    await menu(page, cloud, sessionA);
    await expect(page.getByRole('menuitem', { name: 'Rename…', exact: true })).toBeEnabled();
    await expect(page.getByRole('menuitem', { name: 'Archive', exact: true })).toBeEnabled();
    await page.getByRole('menuitem', { name: 'Delete…', exact: true }).click();
    await expect(page.getByText(/“Cloud fixture A”.*permanently deleted/)).toContainText('Cloud fixture A');
    await expect(page.getByText(/“Cloud fixture A”.*permanently deleted/)).not.toContainText('worktree');
    await page.getByRole('button', { name: 'Cancel', exact: true }).click();
    expect(deletes(cloud)).toHaveLength(0);
    await expect(cloud.row(sessionA)).toBeVisible();
    await askDelete(page, cloud, sessionA);
    await page.getByRole('button', { name: 'Delete permanently', exact: true }).click();
    await expect(cloud.row(sessionA)).toHaveCount(0);
    await expect(cloud.row(sessionC)).toHaveCount(0);
    await expect(page.locator('#task')).toHaveValue('');
    await expect(page.locator('main h1')).toHaveText('New chat');
    expect(deletes(cloud)).toHaveLength(1);
    expect(deletes(cloud)[0].path).toBe(`/v1/sessions/${sessionA}`);
    expect(deletes(cloud)[0].headers.authorization).toBe('Bearer ts_fixture-123');
    expect(cloud.device.requests.filter(request => request.method === 'session.delete')).toHaveLength(0);
    expect(cloud.device.pageErrors).toEqual([]);
  });
}

