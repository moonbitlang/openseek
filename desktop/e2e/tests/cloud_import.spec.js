import { test, expect } from './support/test.js';
import { CloudHarness, importedSession } from './support/cloud_harness.js';

const shareUrl = 'https://openseek-api.moonbitlang.cn/v1/shares/sh_fixture';
const exportJson = JSON.stringify({ '/api/sessions': '[]' });

async function setup(page) {
  const cloud = new CloudHarness(page);
  cloud.titles.set(importedSession, 'Imported chat');
  await cloud.install();
  await cloud.goto();
  await page.locator('aside .section-heading').getByRole('button', { name: 'More actions', exact: true }).click();
  await page.getByRole('menuitem', { name: 'Import conversation', exact: true }).click();
  const dialog = page.getByRole('dialog', { name: 'Import conversation', exact: true });
  await expect(dialog).toBeVisible();
  return { cloud, dialog };
}

const imports = cloud => cloud.requests.filter(request => request.path === '/v1/sessions/import');

async function expectOpened(page, cloud, dialog) {
  await expect(dialog).toBeHidden();
  await expect(cloud.row(importedSession)).toBeVisible();
  await expect(page.locator('main .topbar-title')).toHaveText('Imported chat');
  expect(cloud.hostRequests.filter(request => request.method === 'session.import')).toEqual([]);
  expect(cloud.device.pageErrors).toEqual([]);
}

test('a share link imports into Cloud chats and opens the new chat', async ({ page }) => {
  const { cloud, dialog } = await setup(page);
  await expect(dialog).toContainText('new Cloud chat');
  await dialog.getByRole('textbox', { name: 'OpenSeek share link' }).fill(shareUrl);
  await dialog.getByRole('button', { name: 'Import link', exact: true }).click();
  await expectOpened(page, cloud, dialog);
  expect(imports(cloud)).toHaveLength(1);
  expect(imports(cloud)[0].method).toBe('POST');
  expect(imports(cloud)[0].headers.authorization).toBe('Bearer ts_fixture-123');
  expect(JSON.parse(imports(cloud)[0].body)).toEqual({ source: { kind: 'share', url: shareUrl } });
});

test('a JSON file imports into Cloud chats', async ({ page }) => {
  const { cloud, dialog } = await setup(page);
  const chooser = page.waitForEvent('filechooser');
  await dialog.getByRole('button', { name: 'Import JSON file', exact: true }).click();
  await (await chooser).setFiles({ name: 'conversation.json', mimeType: 'application/json', buffer: Buffer.from(exportJson) });
  await expectOpened(page, cloud, dialog);
  expect(JSON.parse(imports(cloud)[0].body)).toEqual({ source: { kind: 'json', text: exportJson } });
});

for (const [status, body, message] of [
  [400, 'This export came from Local. Import it into a Local workspace.', 'This export came from Local. Import it into a Local workspace.'],
  [410, 'This share link has expired.', 'This share link has expired.'],
  [400, '', 'Cloud answered HTTP 400'],
  [401, '', 'Your account sign-in expired'],
  [500, 'internal details', 'Cloud answered HTTP 500'],
]) {
  test(`Cloud import ${status}${body ? '' : ' without a body'} keeps the dialog retryable`, async ({ page }) => {
    const { cloud, dialog } = await setup(page);
    cloud.importStatus = status;
    cloud.importError = body;
    await dialog.getByRole('textbox', { name: 'OpenSeek share link' }).fill(shareUrl);
    const submit = dialog.getByRole('button', { name: 'Import link', exact: true });
    await submit.click();
    await expect(dialog.getByRole('status')).toContainText(message);
    await expect(submit).toBeEnabled();
    await expect(cloud.row(importedSession)).toHaveCount(0);
    cloud.importStatus = 201;
    await submit.click();
    await expectOpened(page, cloud, dialog);
    expect(imports(cloud)).toHaveLength(2);
  });
}

test('signed-out Chats offer sign-in without an import menu', async ({ page }) => {
  const cloud = new CloudHarness(page, { cached: false });
  await cloud.install();
  await cloud.goto();
  await expect(page.locator('aside .cloud-sign-in')).toBeVisible();
  await expect(page.locator('aside .section-heading').getByRole('button', { name: 'More actions', exact: true })).toHaveCount(0);
});
