import { test, expect } from '@playwright/test';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';
import { installDesktopTransport } from './support/desktop_transport.js';

async function open(page, { codex = false, desktop = true } = {}) {
  const app = new DesktopBrowserHarness(page);
  app.codexModels = [{ id: 'gpt-test', displayName: 'Codex folders', isDefault: true }];
  await app.install();
  if (desktop) {
    await installDesktopTransport(page, app);
    await page.goto('/dist/browser/index.html');
    await page.getByRole('main').waitFor();
  } else {
    await app.goto();
  }
  if (codex) {
    await page.getByRole('button', { name: 'Model', exact: true }).click();
    await page.getByRole('option', { name: 'Codex folders', exact: true }).click();
    await expect(page.locator('#task')).toHaveAttribute('placeholder',
      'Ask Codex to inspect, edit, or explain this workspace.');
  } else {
    await app.openSession();
  }
  return app;
}

async function openFolder(page) {
  await page.getByRole('button', { name: 'Add attachments', exact: true }).click();
  await page.getByRole('menuitem', { name: 'Add folder', exact: true }).click();
  const picker = page.getByRole('dialog', { name: 'Add folder', exact: true });
  await expect(picker).toBeVisible();
  return picker;
}

function attachmentRequests(app) {
  return app.requests.filter(r => /fs\.(prepare_attachment|import_attachment|stage_attachments)/.test(r.method));
}

for (const desktop of [false, true]) {
  test(`${desktop ? 'desktop' : 'browser'} plus opens the add menu without launching a file picker`, async ({ page }, testInfo) => {
    const app = await open(page, { desktop });
    let fileChoosers = 0;
    page.on('filechooser', () => fileChoosers++);
    const plus = page.getByRole('button', { name: 'Add attachments', exact: true });
    await plus.click();
    const menu = page.getByRole('menu', { name: 'Add attachments' });
    await expect(menu).toBeVisible();
    await expect(menu.getByRole('menuitem')).toHaveText(['Add files or photos', 'Add folder']);
    const folder = menu.getByRole('menuitem', { name: 'Add folder', exact: true });
    if (desktop) {
      await expect(folder).toBeEnabled();
    } else {
      await expect(folder).toBeDisabled();
      await expect(folder).toHaveAttribute('title', 'Available only in local desktop sessions');
      await page.keyboard.press('ArrowDown');
      await expect(menu.getByRole('menuitem', { name: 'Add files or photos', exact: true })).toBeFocused();
      await page.keyboard.press('ArrowDown');
      await expect(folder).not.toBeFocused();
      expect(app.requests.some(r => r.method === 'fs.browse')).toBe(false);
    }
    expect(fileChoosers).toBe(0);
    const buttonBox = await plus.boundingBox();
    const menuBox = await menu.boundingBox();
    expect(Math.abs(menuBox.x - buttonBox.x)).toBeLessThanOrEqual(1);
    expect(menuBox.y + menuBox.height).toBeLessThan(buttonBox.y);
    await page.screenshot({ path: testInfo.outputPath('composer-add-menu.png') });
    await page.keyboard.press('Escape');
    await expect(menu).toBeHidden();
    await expect(plus).toBeFocused();
    await plus.click();
    await page.locator('#task').click();
    await expect(menu).toBeHidden();
    expect(fileChoosers).toBe(0);
    expect(app.pageErrors).toEqual([]);
  });
}

for (const codex of [false, true]) {
  test(`${codex ? 'Codex' : 'OpenSeek'} references the selected folder without uploading or traversing it`, async ({ page }, testInfo) => {
    const app = await open(page, { codex });
    const path = '/Users/test/Project & "notes"';
    const reply = app.replyFor.bind(app);
    app.replyFor = request => request.method === 'fs.browse'
      ? request.params.path === path
        ? { path, parent: '/Users/test', entries: ['private-subfolder'] }
        : { path: '/Users/test', parent: '/Users', entries: ['Project & "notes"'] }
      : reply(request);
    await page.locator('#task').fill('Inspect this folder');
    const before = app.requests.length;
    const picker = await openFolder(page);
    await expect(picker).toContainText('Only the folder path will be referenced. Its contents will not be uploaded.');
    await expect(picker.getByRole('button', { name: 'New folder', exact: true })).toHaveCount(0);
    await picker.getByRole('button', { name: 'Open folder Project & "notes"', exact: true }).click();
    await expect(picker.locator('.picker-current-path')).toHaveText(path);
    await expect(picker.getByRole('button', { name: 'Add folder', exact: true })).toBeEnabled();
    await page.screenshot({ path: testInfo.outputPath('composer-folder-picker.png') });
    await picker.getByRole('button', { name: 'Add folder', exact: true }).click();
    await expect(picker).toBeHidden();
    await expect(page.locator('.mention-chip')).toContainText(path);
    await expect(page.locator('#task')).toHaveValue('Inspect this folder');
    await page.locator('#send').click();
    const method = codex ? 'codex.turn.start' : 'agent.start';
    await expect.poll(() => app.requests.find(r => r.method === method)).toBeTruthy();
    const request = app.requests.find(r => r.method === method);
    if (codex) {
      expect(request.params.input).toContainEqual({ type: 'mention', name: 'Project & "notes"', path });
    } else {
      expect(request.params.task).toContain('<file path="/Users/test/Project &amp; &quot;notes&quot;"/>');
    }
    expect(app.requests.slice(before).filter(r => r.method === 'fs.browse')).toHaveLength(2);
    expect(attachmentRequests(app)).toEqual([]);
    expect(app.requests.slice(before).some(r => r.method === 'workspace.add')).toBe(false);
    expect(app.pageErrors).toEqual([]);
  });
}

test('cancelled folder browse replies cannot replace a reopened picker or alter the draft', async ({ page }) => {
  const app = await open(page);
  const pending = Promise.withResolvers();
  const reply = app.replyFor.bind(app);
  let browseCount = 0;
  app.replyFor = request => request.method === 'fs.browse' && ++browseCount === 1
    ? pending.promise : reply(request);
  await page.locator('#task').fill('Keep this draft');
  let picker = await openFolder(page);
  await expect(picker.getByRole('button', { name: 'Add folder', exact: true })).toBeDisabled();
  await page.keyboard.press('Escape');
  await expect(picker).toBeHidden();
  await expect(page.locator('#task')).toHaveValue('Keep this draft');
  await expect(page.locator('.mention-chip')).toHaveCount(0);
  picker = await openFolder(page);
  await expect(picker.locator('.picker-current-path')).toHaveText('/Users/test');
  pending.resolve({ path: '/stale-folder', parent: '/', entries: [] });
  await expect(picker.locator('.picker-current-path')).toHaveText('/Users/test');
  await picker.getByRole('button', { name: 'Add folder', exact: true }).click();
  await expect(page.locator('.mention-chip')).toContainText('/Users/test');
  await expect(page.locator('.mention-chip')).not.toContainText('/stale-folder');
  expect(attachmentRequests(app)).toEqual([]);
  expect(app.pageErrors).toEqual([]);
});


test('folder picker owns shortcuts and reports browse failures without losing the draft', async ({ page }) => {
  const app = await open(page);
  await page.locator('#task').fill('Keep this draft');
  const picker = await openFolder(page);
  await expect(picker.locator('.picker-current-path')).toHaveText('/Users/test');
  const modifier = await page.evaluate(() => navigator.platform.includes('Mac') ? 'Meta' : 'Control');
  await page.keyboard.press(`${modifier}+p`);
  await expect(page.locator('#quick-open-input')).toHaveCount(0);
  await page.keyboard.press(`${modifier}+o`);
  await expect(page.getByRole('dialog')).toHaveCount(1);
  app.rpcErrors.set('fs.browse', 'Permission denied for folder');
  await picker.getByRole('button', { name: 'Open folder Projects', exact: true }).click();
  await expect(page.getByText('Permission denied for folder', { exact: false }).first()).toBeVisible();
  await expect(picker.locator('.picker-current-path')).toHaveText('/Users/test');
  await picker.getByRole('button', { name: 'Cancel', exact: true }).click();
  await expect(page.locator('#task')).toHaveValue('Keep this draft');
  expect(app.pageErrors).toEqual([]);
});
