import { test, expect } from './support/test.js';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';

const actions = page => page.locator('[id="conversation-transfer:actions-trigger"]');
const actionsMenu = page => page.locator('[id="conversation-transfer:actions-content"]:visible');

test('narrow Host conversation actions retain export, overview and files without replacing the conversation', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  app.directoryEntries['/workspace'] = [{ name: 'README.md', is_dir: false }];
  await app.install();
  await app.goto();
  await app.openSession();
  await page.setViewportSize({ width: 393, height: 851 });
  const conversationURL = page.url();
  await page.locator('#task').fill('Unsent Host draft');

  await actions(page).click();
  const exportAction = actionsMenu(page).getByRole('menuitem').filter({ has: page.locator('#conversation-export-action') });
  await expect(exportAction).toBeEnabled();
  await exportAction.click();
  const dialog = page.locator('#conversation-export-dialog');
  await expect(dialog).toBeVisible();
  await dialog.locator('[data-slot="dialog-close"]').click();

  await actions(page).click();
  const overview = page.locator('#conversation-overview');
  const toggleOverview = () => actionsMenu(page).getByRole('menuitem').filter({ has: page.locator('#conversation-overview-action') });
  if (await overview.isVisible()) {
    await toggleOverview().click();
    await expect(overview).toBeHidden();
    await actions(page).click();
  }
  await toggleOverview().click();
  await expect(overview).toBeVisible();
  await actions(page).click();
  await toggleOverview().click();
  await expect(overview).toBeHidden();

  await page.locator('.right-panel-toggle').click();
  await page.locator('.dock-launcher [data-dock-action="files"]').click();
  await expect(page.locator('[role="treeitem"][data-path="README.md"]')).toBeVisible();
  await page.locator('.right-panel-toggle').click();
  await expect(page.locator('.content')).not.toHaveClass(/panel-open/);
  await expect(page).toHaveURL(conversationURL);
  await expect(page.locator('#task')).toHaveValue('Unsent Host draft');
  await expect(page.locator('#transcript')).toContainText('Browser result');
  expect(app.pageErrors).toEqual([]);
});
