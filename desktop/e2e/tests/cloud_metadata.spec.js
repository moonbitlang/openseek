import { test, expect } from './support/test.js';
import { CloudHarness, sessionA, sessionC } from './support/cloud_harness.js';

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
const creations = cloud => cloud.requests.filter(request => request.method === 'POST' && request.path === '/v1/sessions');

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

{
  const desktop = false;

  test(`${desktop ? 'desktop' : 'browser'} Cloud archives into the existing group, opens read only and restores with its draft`, async ({ page }) => {
    const cloud = new CloudHarness(page, { desktop });
    cloud.histories.set(sessionA, { messages: [{ task_id: 'earlier', kind: 'assistant_message', data: { content: 'Earlier Cloud answer.' }, created_at: 1000 }], generating: false });
    await cloud.install();
    await cloud.goto();
    await cloud.open();
    await page.locator('#task').fill('Unsent Cloud draft');
    await menu(page, cloud);
    await page.getByRole('menuitem', { name: 'Archive', exact: true }).click();
    await expect(cloud.row(sessionC)).toHaveCount(0);
    await expect(page.locator('main h1')).toHaveText('New chat');
    await expect(page.locator('#task')).toHaveValue('');
    expect(creations(cloud)).toHaveLength(0);
    expect(patches(cloud).map(request => JSON.parse(request.body))).toEqual([{ archived: true }]);
    await expect(cloud.row(sessionA)).toHaveCount(0);
    const history = page.waitForResponse(response => response.request().method() === 'GET' && new URL(response.url()).pathname.endsWith(`/v1/sessions/${sessionA}/messages`));
    await cloud.openArchived(sessionA);
    expect((await history).status()).toBe(304);
    await expect(page.locator('main h1')).toHaveText('Cloud fixture A');
    await expect(page.locator('#transcript')).toContainText('Earlier Cloud answer.');
    await expect(page.locator('.archived-read-only')).toHaveText('Archived conversation · Read onlyRestore');
    await expect(page.locator('#task')).toHaveCount(0);
    await expect(page.getByRole('button', { name: 'Send', exact: true })).toHaveCount(0);
    await page.locator('main').getByRole('button', { name: 'Restore', exact: true }).click();
    await expect(cloud.row(sessionA)).toHaveAttribute('id', /cloud\.live:/);
    await expect(page.locator('.archived-read-only')).toHaveCount(0);
    await expect(page.locator('#task')).toHaveValue('Unsent Cloud draft');
    expect(patches(cloud).map(request => JSON.parse(request.body))).toEqual([{ archived: true }, { archived: false }]);
    expect(creations(cloud)).toHaveLength(0);
    expect(cloud.device.pageErrors).toEqual([]);
  });
}
