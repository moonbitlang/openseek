import { test, expect } from '@playwright/test';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';

const workspace = '/Users/test/Library/Application Support/SeekMoon/workspaces/Unnamed workspace';

test('create an unnamed workspace without selecting a folder, then recover it on reload', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  app.workspaces = [];
  await page.emulateMedia({ colorScheme: 'dark' });
  await app.install();
  await app.goto();
  await page.locator('.section-heading').getByRole('button', { name: 'Add a project', exact: true }).click();
  const picker = page.getByRole('dialog', { name: 'Add a project' });
  const create = picker.getByRole('button', { name: 'Create unnamed workspace' });
  await expect(create).toBeEnabled();
  await picker.screenshot({ path: test.info().outputPath('unnamed-workspace-picker.png') });
  app.rpcDelays.set('fs.create_unnamed_workspace', 300);
  await create.click();
  await expect(create).toBeDisabled();
  await expect.poll(() => app.requests.find(request => request.method === 'workspace.add'))
    .toMatchObject({ params: { path: workspace } });
  expect(app.requests.filter(request => request.method === 'fs.create_unnamed_workspace')).toHaveLength(1);
  app.notify('workspace.changed', { workspaces: app.workspaces });
  await expect(picker).toBeHidden();
  await expect(page.locator('.workspace-disclosure').filter({ hasText: 'Unnamed workspace' })).toBeVisible();
  await expect(page.getByRole('button', { name: 'Choose project, current project Unnamed workspace' })).toBeVisible();
  await page.reload();
  await expect(page.locator('.workspace-disclosure').filter({ hasText: 'Unnamed workspace' })).toBeVisible();
  expect(app.pageErrors).toEqual([]);
});

test('unnamed workspace errors leave the picker usable and do not register a project', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  app.rpcErrors.set('fs.create_unnamed_workspace', 'disk full');
  await app.install();
  await app.goto();
  await page.getByRole('button', { name: 'Add a project', exact: true }).click();
  const picker = page.getByRole('dialog', { name: 'Add a project' });
  const create = picker.getByRole('button', { name: 'Create unnamed workspace' });
  await create.click();
  await expect(page.getByText(/Cannot create unnamed workspace:.*disk full/)).toBeVisible();
  await expect(create).toBeEnabled();
  expect(app.requests.some(request => request.method === 'workspace.add')).toBe(false);
  app.rpcErrors.delete('fs.create_unnamed_workspace');
  await create.click();
  await expect.poll(() => app.requests.find(request => request.method === 'workspace.add'))
    .toMatchObject({ params: { path: workspace } });
  expect(app.pageErrors).toEqual([]);
});
