import { test, expect } from '@playwright/test';
import { CloudHarness, sessionA, sessionB, sessionC } from './support/cloud_harness.js';

async function menu(page, cloud, id = sessionA) {
  await cloud.row(id).locator('..').hover();
  await cloud.row(id).locator('..').getByRole('button', { name: 'Conversation actions', exact: true }).click();
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

async function archivedGroup(page) {
  const group = page.getByRole('button', { name: /^Archived chats \(/ });
  if (await group.getAttribute('aria-expanded') === 'false') await group.click();
}

for (const desktop of [false, true]) {
  test(`${desktop ? 'desktop' : 'browser'} Cloud renames through the shared field and keeps its manual title after sending and reload`, async ({ page }, testInfo) => {
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
    await page.screenshot({ path: testInfo.outputPath(`cloud-renamed-${desktop ? 'desktop' : 'browser'}.png`), fullPage: true, animations: 'disabled' });
    expect(cloud.device.pageErrors).toEqual([]);
  });
}

test('Cloud reuses blank, unchanged, Escape and blur rename behavior', async ({ page }) => {
  const cloud = new CloudHarness(page);
  await cloud.install();
  await cloud.goto();
  await cloud.open();
  for (const [title, key] of [['   ', 'Enter'], [' Cloud fixture A ', 'Enter'], ['Discarded', 'Escape']]) {
    const field = await rename(page, cloud, title);
    await field.press(key);
    await expect(field).toHaveCount(0);
    await expect(cloud.row(sessionA)).toHaveText('Cloud fixture A');
  }
  expect(patches(cloud)).toHaveLength(0);
  const field = await rename(page, cloud, 'Saved on blur');
  await cloud.row(sessionB).click();
  await expect(field).toHaveCount(0);
  await expect(cloud.row(sessionA)).toHaveText('Saved on blur');
  await expect(cloud.row(sessionB)).toHaveAttribute('aria-current', 'true');
  expect(patches(cloud).map(request => JSON.parse(request.body))).toEqual([{ title: 'Saved on blur' }]);
});

test('Cloud locks the shared rename field until the empty 204 response arrives', async ({ page }) => {
  const cloud = new CloudHarness(page);
  let finish;
  cloud.pausePatch = new Promise(resolve => { finish = resolve; });
  await cloud.install();
  await cloud.goto();
  await cloud.open();
  const field = await rename(page, cloud, 'Pending title');
  await field.press('Enter');
  await expect(field).not.toBeEditable();
  await expect(page.locator('main h1')).toHaveText('Cloud fixture A');
  finish();
  await expect(field).toHaveCount(0);
  await expect(page.locator('main h1')).toHaveText('Pending title');
  expect(patches(cloud)).toHaveLength(1);
});

for (const failure of [503, 'network']) {
  test(`Cloud rename ${failure} keeps the saved title and uses the ordinary error toast`, async ({ page }) => {
    const cloud = new CloudHarness(page);
    cloud.patchStatus = failure === 'network' ? 204 : failure;
    cloud.patchOffline = failure === 'network';
    await cloud.install();
    await cloud.goto();
    await cloud.open();
    const field = await rename(page, cloud, 'Rejected title');
    await field.press('Enter');
    await expect(field).toHaveCount(0);
    await expect(page.getByText(/Rename failed:/)).toBeVisible();
    await expect(cloud.row(sessionA)).toHaveText('Cloud fixture A');
    expect(await page.evaluate(() => localStorage.getItem('seekmoon.account.v1'))).toContain('ts_fixture-123');
    cloud.patchStatus = 204;
    cloud.patchOffline = false;
    await (await rename(page, cloud, 'Retry title')).press('Enter');
    await expect(cloud.row(sessionA)).toHaveText('Retry title');
  });
}

test('Cloud keeps rename enabled while generation disables archive and delete', async ({ page }) => {
  const cloud = new CloudHarness(page);
  cloud.generating.add(sessionA);
  cloud.histories.set(sessionA, { messages: [], generating: true });
  await cloud.install();
  await cloud.goto();
  await cloud.open();
  await menu(page, cloud);
  await expect(page.getByRole('menuitem', { name: 'Rename…', exact: true })).toBeEnabled();
  await expect(page.getByRole('menuitem', { name: 'Archive', exact: true })).toBeDisabled();
  await expect(page.getByRole('menuitem', { name: 'Delete…', exact: true })).toBeDisabled();
  await page.keyboard.press('Escape');
  await (await rename(page, cloud, 'Running title')).press('Enter');
  await expect(cloud.row(sessionA)).toHaveText('Running title');
  expect(patches(cloud).map(request => JSON.parse(request.body))).toEqual([{ title: 'Running title' }]);
});

test('a late Cloud rename cannot recreate a signed-out account or its row', async ({ page }) => {
  const cloud = new CloudHarness(page);
  let finish;
  cloud.pausePatch = new Promise(resolve => { finish = resolve; });
  await cloud.install();
  await cloud.goto();
  await cloud.open();
  await (await rename(page, cloud, 'Late title')).press('Enter');
  await expect.poll(() => patches(cloud).length).toBe(1);
  await page.getByRole('button', { name: 'Settings', exact: true }).click();
  const account = page.locator('.settings-group', { has: page.getByRole('heading', { name: 'Account · Remote access', exact: true }) });
  await account.getByRole('button', { name: 'Sign out', exact: true }).click();
  await expect(cloud.row(sessionA)).toHaveCount(0);
  const completed = page.waitForResponse(response => response.request().method() === 'PATCH');
  finish();
  expect((await completed).status()).toBe(204);
  await expect(page.getByRole('textbox', { name: 'Rename conversation', exact: true })).toHaveCount(0);
  await expect(cloud.row(sessionA)).toHaveCount(0);
  expect(await page.evaluate(() => localStorage.getItem('seekmoon.account.v1'))).toBeNull();
});

for (const status of [401, 404]) {
  test(`Cloud rename ${status} uses existing expiry or missing-session recovery`, async ({ page }) => {
    const cloud = new CloudHarness(page);
    cloud.patchStatus = status;
    await cloud.install();
    await cloud.goto();
    await cloud.open();
    await (await rename(page, cloud, 'Unavailable title')).press('Enter');
    await expect(cloud.row(sessionA)).toHaveCount(0);
    if (status === 401) {
      await expect.poll(() => page.evaluate(() => localStorage.getItem('seekmoon.account.v1'))).toBeNull();
    } else {
      expect(await page.evaluate(() => localStorage.getItem('seekmoon.account.v1'))).toContain('ts_fixture-123');
      await expect(cloud.row(sessionC)).toHaveCount(0);
    }
  });
}

for (const desktop of [false, true]) {
  test(`${desktop ? 'desktop' : 'browser'} Cloud archives into the existing group, opens read only and restores with its draft`, async ({ page }, testInfo) => {
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
    await archivedGroup(page);
    await expect(cloud.row(sessionA)).toHaveAttribute('id', /cloud\.archived:/);
    const history = page.waitForResponse(response => response.request().method() === 'GET' && response.url().endsWith(`/v1/sessions/${sessionA}/messages`));
    await cloud.row(sessionA).click();
    await (await history).finished();
    await expect(page.locator('main h1')).toHaveText('Cloud fixture A');
    await expect(page.locator('#transcript')).toContainText('Earlier Cloud answer.');
    await expect(page.locator('.archived-read-only')).toHaveText('Archived conversation · Read onlyRestore');
    await expect(page.locator('#task')).toHaveCount(0);
    await expect(page.getByRole('button', { name: 'Send', exact: true })).toHaveCount(0);
    await cloud.row(sessionA).click({ button: 'right' });
    await expect(page.getByRole('menuitem')).toHaveText(['Restore', 'Delete…']);
    await page.keyboard.press('Escape');
    await page.screenshot({ path: testInfo.outputPath(`cloud-archived-${desktop ? 'desktop' : 'browser'}.png`), fullPage: true, animations: 'disabled' });
    await page.locator('main').getByRole('button', { name: 'Restore', exact: true }).click();
    await expect(cloud.row(sessionA)).toHaveAttribute('id', /cloud\.live:/);
    await expect(page.locator('.archived-read-only')).toHaveCount(0);
    await expect(page.locator('#task')).toHaveValue('Unsent Cloud draft');
    expect(patches(cloud).map(request => JSON.parse(request.body))).toEqual([{ archived: true }, { archived: false }]);
    expect(creations(cloud)).toHaveLength(0);
    expect(cloud.device.pageErrors).toEqual([]);
  });
}

test('Cloud background archive and a late archive reply leave the selected chat and draft alone', async ({ page }) => {
  const cloud = new CloudHarness(page);
  await cloud.install();
  await cloud.goto();
  await cloud.open();
  await page.locator('#task').fill('Foreground draft');
  await menu(page, cloud, sessionB);
  await page.getByRole('menuitem', { name: 'Archive', exact: true }).click();
  await expect(cloud.row(sessionB)).toHaveCount(0);
  await expect(cloud.row(sessionA)).toHaveAttribute('aria-current', 'true');
  await expect(page.locator('#task')).toHaveValue('Foreground draft');
  expect(creations(cloud)).toHaveLength(0);
  await archivedGroup(page);
  await cloud.row(sessionB).locator('..').hover();
  await cloud.row(sessionB).locator('..').getByRole('button', { name: 'Restore this conversation to the sidebar', exact: true }).click();
  await expect(cloud.row(sessionB)).toHaveAttribute('id', /cloud\.live:/);
  let finish;
  cloud.pausePatch = new Promise(resolve => { finish = resolve; });
  await menu(page, cloud);
  await page.getByRole('menuitem', { name: 'Archive', exact: true }).click();
  await expect.poll(() => patches(cloud).length).toBe(3);
  await cloud.open(sessionB);
  await page.locator('#task').fill('New destination draft');
  const completed = page.waitForResponse(response => response.request().method() === 'PATCH');
  finish();
  expect((await completed).status()).toBe(204);
  await expect(cloud.row(sessionA)).toHaveAttribute('id', /cloud\.archived:/);
  await expect(cloud.row(sessionB)).toHaveAttribute('aria-current', 'true');
  await expect(page.locator('#task')).toHaveValue('New destination draft');
  expect(creations(cloud)).toHaveLength(0);
});

for (const failure of [409, 503, 'network']) {
  test(`Cloud archive ${failure} leaves the live conversation and its ordinary archive action`, async ({ page }) => {
    const cloud = new CloudHarness(page);
    cloud.patchStatus = failure === 'network' ? 204 : failure;
    cloud.patchOffline = failure === 'network';
    await cloud.install();
    await cloud.goto();
    await cloud.open();
    await page.locator('#task').fill('Keep the draft');
    await menu(page, cloud);
    await page.getByRole('menuitem', { name: 'Archive', exact: true }).click();
    await expect(page.locator('aside')).toContainText(failure === 'network' ? 'unreachable' : `HTTP ${failure}`);
    await expect(cloud.row(sessionA)).toHaveAttribute('id', /cloud\.live:/);
    await expect(cloud.row(sessionA)).toHaveAttribute('aria-current', 'true');
    await expect(page.locator('#task')).toHaveValue('Keep the draft');
    expect(creations(cloud)).toHaveLength(0);
    expect(await page.evaluate(() => localStorage.getItem('seekmoon.account.v1'))).toContain('ts_fixture-123');
    await menu(page, cloud);
    await expect(page.getByRole('menuitem', { name: 'Archive', exact: true })).toBeEnabled();
  });
}

test('Cloud restore keeps its read-only view after failure and exposes a disabled-only menu while retrying', async ({ page }, testInfo) => {
  const cloud = new CloudHarness(page);
  cloud.archived.add(sessionA);
  cloud.patchStatus = 503;
  await cloud.install();
  await cloud.goto();
  await archivedGroup(page);
  await cloud.row(sessionA).click();
  const restore = page.locator('main').getByRole('button', { name: 'Restore', exact: true });
  await restore.click();
  await expect(page.locator('aside')).toContainText('HTTP 503');
  await expect(cloud.row(sessionA)).toHaveAttribute('id', /cloud\.archived:/);
  await expect(page.locator('#task')).toHaveCount(0);
  cloud.patchStatus = 204;
  let finish;
  cloud.pausePatch = new Promise(resolve => { finish = resolve; });
  await restore.click();
  try {
    await expect(restore).toBeDisabled();
    await cloud.row(sessionA).click({ button: 'right' });
    const popup = page.getByRole('menu', { name: 'Conversation actions', exact: true });
    await expect(popup).toBeFocused();
    await expect(popup.getByRole('menuitem', { name: 'Restore', exact: true })).toBeDisabled();
    await expect(popup.getByRole('menuitem', { name: 'Delete…', exact: true })).toBeDisabled();
    for (const key of ['ArrowDown', 'ArrowUp', 'Home', 'End', 'Enter', 'Space']) {
      await page.keyboard.press(key);
      await expect(popup).toBeFocused();
    }
    await page.screenshot({ path: testInfo.outputPath('cloud-restore-pending-menu.png'), fullPage: true });
    expect(cloud.requests.filter(request => request.method === 'DELETE')).toHaveLength(0);
    await page.keyboard.press('Escape');
  } finally {
    finish();
  }
  await expect(cloud.row(sessionA)).toHaveAttribute('id', /cloud\.live:/);
  await expect(page.locator('#task')).toBeVisible();
  expect(creations(cloud)).toHaveLength(0);
});
