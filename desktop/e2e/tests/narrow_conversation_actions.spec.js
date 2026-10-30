import { test, expect } from '@playwright/test';
import { CloudHarness, authOrigin, cloudOrigin, sessionA } from './support/cloud_harness.js';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';

const actions = page => page.locator('main > .topbar').getByRole('button', { name: 'Conversation actions', exact: true });
const actionsMenu = page => page.getByRole('menu', { name: 'Conversation actions', exact: true });

async function expectSeparateHeaderControls(page) {
  const menuButton = actions(page);
  const panelButton = page.locator('.right-panel-toggle');
  await expect(menuButton).toBeVisible();
  await expect(panelButton).toBeVisible();
  await expect(panelButton).toBeEnabled();
  await expect(panelButton).toHaveAccessibleName('Show panel');
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
  await expect(page.locator('main > .topbar .run-status')).toHaveText('Finished');
  return cloud;
}

test('narrow Cloud conversation actions preserve export, full-screen files and the current conversation across resizing', async ({ page }) => {
  await page.setViewportSize({ width: 393, height: 851 });
  const cloud = await cloudConversation(page);
  const header = page.locator('main > .topbar');
  const conversationURL = page.url();
  await page.locator('#task').fill('Unsent Cloud draft');
  await expectSeparateHeaderControls(page);
  await expect(header.locator('button:visible')).toHaveCount(1);
  await expect(header.getByRole('button', { name: 'Export', exact: true })).toHaveCount(0);

  await actions(page).click();
  await expect(actionsMenu(page).getByRole('menuitem', { name: 'Export', exact: true })).toBeEnabled();
  await expect(actionsMenu(page).getByRole('menuitem', { name: /^(Show|Hide) panel$/ })).toHaveCount(0);
  await actionsMenu(page).getByRole('menuitem', { name: 'Export', exact: true }).click();
  const exportDialog = page.getByRole('dialog', { name: 'Export conversation', exact: true });
  await expect(exportDialog).toBeVisible();
  await page.keyboard.press('Escape');
  await expect(exportDialog).not.toBeVisible();
  await expect(actions(page)).toBeFocused();

  await page.getByRole('button', { name: 'Show panel', exact: true }).click();
  await page.locator('.dock-launcher').getByRole('button', { name: /^Files / }).click();
  const tree = page.getByRole('tree', { name: 'Workspace files', exact: true });
  await expect(tree.getByRole('treeitem', { name: 'README.md', exact: true })).toBeVisible();
  const panel = page.locator('.content > .editor');
  await expect.poll(async () => Math.abs((await panel.boundingBox()).x)).toBeLessThan(1);
  const panelBox = await panel.boundingBox();
  expect(panelBox.width).toBe(393);
  expect(panelBox.height).toBe(851);
  await page.getByRole('button', { name: 'Hide panel', exact: true }).click();
  await expect(page.locator('.content')).not.toHaveClass(/panel-open/);
  await expect(page).toHaveURL(conversationURL);
  await expect(page.locator('#transcript')).toContainText('Narrow Cloud conversation');
  await expect(page.locator('#task')).toHaveValue('Unsent Cloud draft');

  await page.setViewportSize({ width: 1440, height: 900 });
  await expect(actions(page)).toHaveCount(0);
  const inlineExport = header.getByRole('button', { name: 'Export', exact: true });
  await expect(inlineExport).toBeVisible();
  await expect(inlineExport).not.toHaveAttribute('aria-haspopup', 'menu');
  await inlineExport.click();
  await expect(exportDialog).toBeVisible();
  await expect(actionsMenu(page)).not.toBeVisible();
  await page.keyboard.press('Escape');
  await expect(exportDialog).not.toBeVisible();
  await expect(page.locator('.right-panel-toggle')).toBeVisible();
  await page.setViewportSize({ width: 393, height: 851 });
  await expectSeparateHeaderControls(page);
  await expect(header.locator('button:visible')).toHaveCount(1);
  await expect(page.locator('#task')).toHaveValue('Unsent Cloud draft');
  expect(cloud.device.pageErrors).toEqual([]);
  expect(cloud.device.ticketRequests).toEqual([]);
});

test('narrow Host conversation actions retain import, export, overview and files without replacing the conversation', async ({ page }) => {
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
  await expect(page.locator('main > .topbar').getByRole('button', { name: 'Export and import', exact: true })).toHaveCount(0);

  for (const [entry, title] of [['Export', 'Export conversation'], ['Import', 'Import conversation']]) {
    await actions(page).click();
    await expect(actionsMenu(page).getByRole('menuitem', { name: 'Export', exact: true })).toBeEnabled();
    await expect(actionsMenu(page).getByRole('menuitem', { name: 'Import', exact: true })).toBeEnabled();
    await expect(actionsMenu(page).getByRole('menuitem', { name: /^(Show|Hide) panel$/ })).toHaveCount(0);
    await expect(actionsMenu(page).getByRole('menuitem', { name: /^(Show|Hide) overview$/ })).toBeEnabled();
    await actionsMenu(page).getByRole('menuitem', { name: entry, exact: true }).click();
    const dialog = page.getByRole('dialog', { name: title, exact: true });
    await expect(dialog).toBeVisible();
    await page.keyboard.press('Escape');
    await expect(dialog).not.toBeVisible();
    await expect(actions(page)).toBeFocused();
  }

  await actions(page).click();
  const overview = page.getByRole('complementary', { name: 'Overview', exact: true });
  const hideOverview = actionsMenu(page).getByRole('menuitem', { name: 'Hide overview', exact: true });
  if (await hideOverview.count()) {
    await hideOverview.click();
    await expect(overview).toHaveCount(0);
    await actions(page).click();
  }
  await actionsMenu(page).getByRole('menuitem', { name: 'Show overview', exact: true }).click();
  await expect(overview).toBeVisible();
  await actions(page).click();
  await actionsMenu(page).getByRole('menuitem', { name: 'Hide overview', exact: true }).click();
  await expect(overview).toHaveCount(0);

  await page.getByRole('button', { name: 'Show panel', exact: true }).click();
  await page.locator('.dock-launcher').getByRole('button', { name: /^Files / }).click();
  await expect(page.getByRole('tree', { name: 'Workspace files', exact: true }).getByRole('treeitem', { name: 'README.md', exact: true })).toBeVisible();
  await page.getByRole('button', { name: 'Hide panel', exact: true }).click();
  await expect(page.locator('.content')).not.toHaveClass(/panel-open/);
  await expect(page).toHaveURL(conversationURL);
  await expect(page.locator('#task')).toHaveValue('Unsent Host draft');
  await expect(page.locator('#transcript')).toContainText('Browser result');
  await expectSeparateHeaderControls(page);
  expect(app.pageErrors).toEqual([]);
});

test('conversation actions fit the viewport, dismiss on Escape and outside clicks, and close at the wide-layout boundary', async ({ page }, testInfo) => {
  await page.setViewportSize({ width: 393, height: 851 });
  const cloud = await cloudConversation(page);
  for (const width of [393, 760]) {
    await page.setViewportSize({ width, height: 851 });
    await expectSeparateHeaderControls(page);
    await actions(page).click();
    const menu = actionsMenu(page);
    await expect(menu.getByRole('menuitem', { name: /^(Show|Hide) panel$/ })).toHaveCount(0);
    await expect(menu).toBeInViewport({ ratio: 1 });
    const bounds = await menu.boundingBox();
    expect(bounds.x).toBeGreaterThanOrEqual(0);
    expect(bounds.y).toBeGreaterThanOrEqual(0);
    expect(bounds.x + bounds.width).toBeLessThanOrEqual(width);
    expect(bounds.y + bounds.height).toBeLessThanOrEqual(851);
    if (width === 393) {
      await page.screenshot({ path: testInfo.outputPath('narrow-panel-toggle-with-menu-393.png'), animations: 'disabled' });
    }
    await page.keyboard.press('Escape');
    await expect(menu).not.toBeVisible();
    await expect(actions(page)).toBeFocused();
    await actions(page).click();
    await page.locator('#task').click();
    await expect(menu).not.toBeVisible();
    await expect(page.locator('#task')).toBeFocused();
  }
  await actions(page).click();
  await expect(actionsMenu(page)).toBeVisible();
  await page.setViewportSize({ width: 761, height: 851 });
  await expect(actions(page)).toHaveCount(0);
  await expect(actionsMenu(page)).not.toBeVisible();
  await expect(page.locator('main > .topbar').getByRole('button', { name: 'Export', exact: true })).toBeVisible();
  await expect(page.locator('.right-panel-toggle')).toBeVisible();
  await page.setViewportSize({ width: 760, height: 851 });
  await expectSeparateHeaderControls(page);
  await expect(page.locator('main > .topbar button:visible')).toHaveCount(1);
  await actions(page).click();
  await expect(actionsMenu(page).getByRole('menuitem', { name: /^(Show|Hide) panel$/ })).toHaveCount(0);
  await expect(actionsMenu(page).getByRole('menuitem', { name: 'Export', exact: true })).toBeEnabled();
  expect(cloud.device.pageErrors).toEqual([]);
});
