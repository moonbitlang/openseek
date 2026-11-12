import { test, expect } from './support/test.js';
import { CloudHarness, authOrigin } from './support/cloud_harness.js';

const library = page => page.getByRole('dialog', { name: 'Skills', exact: true });
const row = (page, name) => library(page).locator('.skill-row').filter({
  has: page.locator('.skill-name', { hasText: new RegExp(`^${name}$`) }),
});

const alpha = {
  name: 'alpha', module_name: 'acme/alpha', package_path: '', version: '1.0.0',
  description: 'Plan alpha work.', author: 'acme', repository: '',
};

async function showSidebar(page) {
  if (!await page.getByRole('button', { name: 'Settings', exact: true }).isVisible()) {
    await page.locator('.sidebar-toggle').click();
  }
}

test('browser Cloud manages the account skill library and completes its skills', async ({ page }) => {
  const cloud = new CloudHarness(page);
  cloud.skillCatalog = [alpha];
  await cloud.install();
  await page.goto(`${authOrigin}/cloud`);
  await expect(page.locator('#task')).toBeEnabled();
  await showSidebar(page);
  await page.getByRole('button', { name: 'Skills', exact: true }).click();

  // A page without a host has only the Cloud library: no switch.
  await expect(library(page).getByRole('group', { name: 'Library', exact: true })).toHaveCount(0);
  // Cloud's built-ins are always on: no switch or menu.
  await expect(row(page, 'typst')).toBeVisible();
  await expect(row(page, 'typst').getByRole('switch')).toHaveCount(0);
  await expect(row(page, 'typst').getByRole('button', { name: 'Manage skill', exact: true })).toHaveCount(0);

  await row(page, 'alpha').getByRole('button', { name: 'Install', exact: true }).click();
  await expect(row(page, 'alpha').getByRole('switch')).toBeChecked();
  const install = cloud.requests.find(request => request.method === 'POST' && request.path === '/v1/me/skills');
  expect(JSON.parse(install.body)).toEqual({ module_name: 'acme/alpha', version: '1.0.0' });
  expect(install.headers.authorization).toMatch(/^Bearer ts_fixture-/);

  // The Cloud composer completes the account's enabled skills.
  await page.keyboard.press('Escape');
  await expect(library(page)).toBeHidden();
  await page.locator('#task').fill('$');
  const labels = page.locator('.completion-list .completion-label');
  await expect(labels).toHaveText(['$typst', '$alpha']);

  await showSidebar(page);
  await page.getByRole('button', { name: 'Skills', exact: true }).click();
  await row(page, 'alpha').getByRole('switch').click();
  await expect(row(page, 'alpha').getByRole('switch')).not.toBeChecked();
  const toggle = cloud.requests.find(request => request.method === 'PATCH' && request.path === '/v1/me/skills/acme-alpha');
  expect(JSON.parse(toggle.body)).toEqual({ enabled: false });
  await page.keyboard.press('Escape');
  await expect(library(page)).toBeHidden();
  await page.locator('#task').fill('');
  await page.locator('#task').fill('$');
  await expect(labels).toHaveText(['$typst']);

  expect(cloud.device.requests.filter(request => request.method.startsWith('skills.'))).toEqual([]);
  expect(cloud.device.pageErrors).toEqual([]);
});

test('a signed-in Desktop switches between the device library and Cloud', async ({ page }) => {
  const cloud = new CloudHarness(page);
  cloud.device.installedSkills = [{
    id: 'local-notes', name: 'local-notes', description: 'Device notes.', source: '',
    builtin: false, enabled: true,
  }];
  await cloud.install();
  await cloud.goto();
  await expect.poll(() => cloud.device.requests.length).toBeGreaterThan(0);
  await showSidebar(page);
  await page.getByRole('button', { name: 'Skills', exact: true }).click();

  const libraries = library(page).getByRole('group', { name: 'Library', exact: true });
  const device = libraries.getByRole('button', { name: 'This device', exact: true });
  const cloudTab = libraries.getByRole('button', { name: 'Cloud', exact: true });
  await expect(device).toHaveAttribute('aria-pressed', 'true');
  await expect(row(page, 'local-notes')).toBeVisible();
  await expect(row(page, 'typst')).toHaveCount(0);

  await cloudTab.click();
  await expect(cloudTab).toHaveAttribute('aria-pressed', 'true');
  await expect(row(page, 'typst')).toBeVisible();
  await expect(row(page, 'local-notes')).toHaveCount(0);
  expect(cloud.requests.some(request => request.method === 'GET' && request.path === '/v1/me/skills')).toBe(true);

  await device.click();
  await expect(row(page, 'local-notes')).toBeVisible();
  await expect(row(page, 'typst')).toHaveCount(0);
  expect(cloud.device.pageErrors).toEqual([]);
});
