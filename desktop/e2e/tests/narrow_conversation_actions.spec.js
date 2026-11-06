import { test, expect } from './support/test.js';
import { CloudHarness, authOrigin, cloudOrigin, sessionA } from './support/cloud_harness.js';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';

const actions = page => page.locator('[id="conversation-transfer:actions-trigger"]');
const actionsMenu = page => page.locator('[id="conversation-transfer:actions-content"]:visible');

async function expectSeparateHeaderControls(page, menuButton = actions(page)) {
  const panelButton = page.locator('.right-panel-toggle');
  await expect(menuButton).toBeVisible();
  await expect(panelButton).toBeVisible();
  await expect(panelButton).toBeEnabled();
  const menuBox = await menuButton.boundingBox();
  const panelBox = await panelButton.boundingBox();
  expect(Math.abs(menuBox.y + menuBox.height / 2 - panelBox.y - panelBox.height / 2)).toBeLessThanOrEqual(1);
  expect(Math.min(menuBox.x + menuBox.width, panelBox.x + panelBox.width) - Math.max(menuBox.x, panelBox.x)).toBeLessThanOrEqual(0);
  for (const button of [menuButton, panelButton]) {
    await expect.poll(() => button.evaluate(node => {
      const bounds = node.getBoundingClientRect();
      const hit = document.elementFromPoint(bounds.x + bounds.width / 2, bounds.y + bounds.height / 2);
      return hit === node || node.contains(hit);
    })).toBe(true);
  }
}

async function cloudConversation(page) {
  const cloud = new CloudHarness(page);
  cloud.histories.set(sessionA, { generating: false, messages: [
    { task_id: 'finished-task', kind: 'assistant_message', data: { content: 'Narrow Cloud conversation' }, created_at: 1000 },
    { task_id: 'finished-task', kind: 'task_finished', data: { status: 'completed', result: { output: { answer: 'Narrow Cloud conversation' } } }, created_at: 1001 },
  ] });
  await cloud.install();
  await page.route(url => url.origin === cloudOrigin &&
    url.pathname === `/v1/sessions/${sessionA}/files`, route => route.fulfill({
      headers: { 'Access-Control-Allow-Origin': authOrigin, 'Access-Control-Allow-Headers': 'Authorization, Content-Type', 'Access-Control-Allow-Methods': 'GET, OPTIONS' },
      contentType: 'application/json',
      body: JSON.stringify({ entries: [{ name: 'README.md', is_dir: false }] }),
    }));
  await page.goto(`${authOrigin}/cloud/session/${sessionA}`);
  await expect(page.locator('#transcript')).toContainText('Narrow Cloud conversation');
  return cloud;
}

test('narrow Cloud conversations keep the inline export beside the panel toggle across resizing', async ({ page }) => {
  await page.setViewportSize({ width: 393, height: 851 });
  const cloud = await cloudConversation(page);
  const header = page.locator('main > .topbar');
  const conversationURL = page.url();
  const inlineExport = page.locator('#cloud-conversation-export');
  await page.locator('#task').fill('Unsent Cloud draft');
  await expectSeparateHeaderControls(page, inlineExport);
  await expect(header.locator('button:visible')).toHaveCount(1);
  await expect(actions(page)).toHaveCount(0);
  await expect(inlineExport).not.toHaveAttribute('aria-haspopup', 'menu');

  await inlineExport.click();
  const exportDialog = page.locator('#conversation-export-dialog');
  await expect(exportDialog).toBeVisible();
  await exportDialog.locator('[data-slot="dialog-close"]').click();

  await page.locator('.right-panel-toggle').click();
  await page.locator('.dock-launcher [data-dock-action="files"]').click();
  await expect(page.locator('[role="treeitem"][data-path="README.md"]')).toBeVisible();
  const panel = page.locator('.content > .editor');
  await expect.poll(async () => Math.abs((await panel.boundingBox()).x)).toBeLessThan(1);
  const panelBox = await panel.boundingBox();
  expect(panelBox.width).toBe(393);
  expect(panelBox.height).toBe(851);
  await page.locator('.right-panel-toggle').click();
  await expect(page.locator('.content')).not.toHaveClass(/panel-open/);
  await expect(page).toHaveURL(conversationURL);
  await expect(page.locator('#transcript')).toContainText('Narrow Cloud conversation');
  await expect(page.locator('#task')).toHaveValue('Unsent Cloud draft');

  await page.setViewportSize({ width: 1440, height: 900 });
  await expect(inlineExport).toBeVisible();
  await expect(page.locator('.right-panel-toggle')).toBeVisible();
  await page.setViewportSize({ width: 393, height: 851 });
  await expectSeparateHeaderControls(page, inlineExport);
  await expect(header.locator('button:visible')).toHaveCount(1);
  await expect(page.locator('#task')).toHaveValue('Unsent Cloud draft');
  expect(cloud.device.pageErrors).toEqual([]);
  expect(cloud.device.ticketRequests).toEqual([]);
});

test('narrow Host conversation actions retain export, overview and files without replacing the conversation', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  app.directoryEntries['/workspace'] = [{ name: 'README.md', is_dir: false }];
  await app.install();
  await app.goto();
  await app.openSession();
  await page.setViewportSize({ width: 393, height: 851 });
  const conversationURL = page.url();
  await page.locator('#task').fill('Unsent Host draft');
  await expectSeparateHeaderControls(page);
  await expect(page.locator('main > .topbar button:visible')).toHaveCount(1);

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
  await expectSeparateHeaderControls(page);
  expect(app.pageErrors).toEqual([]);
});

test('conversation actions preserve direct panel access at the narrow layout boundary', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  await app.install();
  await app.goto();
  await app.openSession();
  for (const width of [393, 760]) {
    await page.setViewportSize({ width, height: 851 });
    await expectSeparateHeaderControls(page);
    await actions(page).click();
    await expect(actionsMenu(page).getByRole('menuitem').filter({ has: page.locator('#conversation-overview-action') })).toBeEnabled();
    await page.keyboard.press('Escape');
  }
  await page.setViewportSize({ width: 761, height: 851 });
  await expect(actions(page)).toBeVisible();
  await expect(page.locator('#conversation-overview-toggle')).toBeVisible();
  await expect(page.locator('.right-panel-toggle')).toBeVisible();
  await page.setViewportSize({ width: 760, height: 851 });
  await expectSeparateHeaderControls(page);
  await expect(page.locator('main > .topbar button:visible')).toHaveCount(1);
  await actions(page).click();
  await expect(actionsMenu(page).getByRole('menuitem').filter({ has: page.locator('#conversation-export-action') })).toBeEnabled();
  expect(app.pageErrors).toEqual([]);
});
