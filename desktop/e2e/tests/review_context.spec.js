import { test, expect } from '@playwright/test';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';

async function openReview(page, app) {
  await app.install();
  await app.goto();
  await app.openSession();
  await app.openReview();
  await page.locator('#review-changes-body').getByRole('treeitem', { name: /View diff: src\/main\.mbt/ }).click();
}

const contextButtons = page => page.locator('.review-hunk-context-button:visible');

async function hoverContextHunk(page, button) {
  await expect(async () => {
    await expect(button).toBeVisible();
    const bounds = await button.evaluate(node =>
      node.closest('.moonbit-diff-hunk-action').getBoundingClientRect().toJSON());
    expect(bounds.width).toBeGreaterThan(0);
    expect(bounds.height).toBeGreaterThan(0);
    // File switches can replace the hunk after it becomes visible. Re-read its
    // geometry on retry, then hover the code beneath the overlay.
    await page.mouse.move(bounds.x + bounds.width * 0.7, bounds.y + Math.min(bounds.height / 2, 8));
    await expect(button.locator('..')).toHaveCSS('opacity', '1', { timeout: 250 });
  }).toPass({ timeout: 5000 });
}

async function clickHunkContext(page, button = contextButtons(page).first()) {
  await hoverContextHunk(page, button);
  await button.click();
}

test('selected changes retain their preview during live language switching', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  await openReview(page, app);
  await clickHunkContext(page);
  const chip = page.locator('.composer-changes .changes-chip .mention-jump');
  await chip.click();
  const region = page.locator('.composer-changes .editor-diff-preview');
  await expect(region).toHaveAccessibleName(/^src\/main\.mbt: Old L.+ → New L.+$/);
  const preview = await page.locator('.composer-changes .changes-preview').allTextContents();
  await page.evaluate(() => {
    Object.defineProperty(navigator, 'languages', { configurable: true, value: ['zh-CN'] });
    window.dispatchEvent(new Event('languagechange'));
  });
  await expect(chip).toContainText('更改 · 1 个文件');
  const popup = page.getByRole('dialog', { name: '所选更改' });
  await expect(popup).toBeVisible();
  await expect(popup.getByRole('button', { name: '在审阅中打开', exact: true })).toBeVisible();
  await expect(popup).toContainText('仅包含所选更改。');
  await expect(region).toHaveAccessibleName(/^src\/main\.mbt: 原始 L.+ → 修改后 L.+$/);
  expect(await popup.locator('.changes-preview').allTextContents()).toEqual(preview);
  await page.evaluate(() => {
    Object.defineProperty(navigator, 'languages', { configurable: true, value: ['ja-JP'] });
    window.dispatchEvent(new Event('languagechange'));
  });
  await expect(chip).toContainText('変更 · 1 ファイル');
  const japanesePopup = page.getByRole('dialog', { name: '選択した変更', exact: true });
  await expect(japanesePopup).toBeVisible();
  await expect(japanesePopup.getByRole('button', { name: 'レビューで開く', exact: true })).toBeVisible();
  await expect(japanesePopup).toContainText('選択した変更のみが含まれます。');
  await expect(region).toHaveAccessibleName(/^src\/main\.mbt: 変更前 L.+ → 変更後 L.+$/);
  expect(await japanesePopup.locator('.changes-preview').allTextContents()).toEqual(preview);
  await page.evaluate(() => {
    Object.defineProperty(navigator, 'languages', { configurable: true, value: ['zh-Hant'] });
    window.dispatchEvent(new Event('languagechange'));
  });
  await expect(chip).toContainText('更改 · 1 個檔案');
  const traditionalPopup = page.getByRole('dialog', { name: '所選更改', exact: true });
  await expect(traditionalPopup).toBeVisible();
  await expect(traditionalPopup.getByRole('button', { name: '在審閱中開啟', exact: true })).toBeVisible();
  await expect(region).toHaveAccessibleName(/^src\/main\.mbt: 原始 L.+ → 修改後 L.+$/);
  expect(await traditionalPopup.locator('.changes-preview').allTextContents()).toEqual(preview);
  expect(app.pageErrors).toEqual([]);
});

test('composer script previews pin one coordinate and sign while code scrolls', async ({ page }, testInfo) => {
  const app = new DesktopBrowserHarness(page);
  const file = 'scripts/example.mbtx';
  const original = `let message = "old ${'long source '.repeat(18)}"`;
  const modified = original.replace('old ', 'new ');
  app.gitChanges = [{ path: file, index_status: ' ', worktree_status: 'M', kind: 'modified' }];
  app.gitFilesByRevision[app.gitBaseline][file] = `${original}\n`;
  app.workingFiles[file] = `${modified}\n`;
  await app.install();
  await app.goto();
  await app.openSession();
  await app.openReview();
  await page.locator('#review-changes-body').getByRole('treeitem', { name: /View diff: scripts\/example\.mbtx/ }).click();
  await clickHunkContext(page);
  await page.setViewportSize({ width: 1060, height: 800 });
  await page.locator('.composer-changes .changes-chip .mention-jump').click();
  const popup = page.getByRole('dialog', { name: 'Selected changes' });
  const preview = popup.locator('.editor-diff-preview');
  await expect(preview.locator('.editor-diff-source')).toHaveText([original, modified]);
  await expect(preview.locator('.editor-diff-number')).toHaveText(['1', '1']);
  await expect(preview.locator('.editor-diff-sign')).toHaveText(['−', '+']);
  await expect(preview.locator('.editor-diff-row.removed')).toHaveCount(1);
  await expect(preview.locator('.editor-diff-row.added')).toHaveCount(1);
  const geometry = () => preview.evaluate(node => {
    const bounds = selector => node.querySelector(selector).getBoundingClientRect();
    return {
      number: bounds('.editor-diff-number').x,
      sign: bounds('.editor-diff-sign').x,
      source: bounds('.editor-diff-source').x,
      width: node.clientWidth,
      scrollWidth: node.scrollWidth,
      scrollLeft: node.scrollLeft,
    };
  });
  for (const theme of ['light', 'dark']) {
    await page.evaluate(theme => document.documentElement.dataset.theme = theme, theme);
    await preview.evaluate(node => { node.scrollLeft = 0; });
    const before = await geometry();
    expect(before.scrollWidth).toBeGreaterThan(before.width);
    const sourceColor = await preview.locator('.editor-diff-source').first().evaluate(node => getComputedStyle(node).color);
    const stringColor = await preview.locator('.mtk5').first().evaluate(node => getComputedStyle(node).color);
    expect(stringColor).not.toBe(sourceColor);
    await preview.evaluate(node => { node.scrollLeft = 180; });
    await expect.poll(async () => (await geometry()).scrollLeft).toBe(180);
    const after = await geometry();
    expect(after.number).toBeCloseTo(before.number, 1);
    expect(after.sign).toBeCloseTo(before.sign, 1);
    expect(after.source).toBeCloseTo(before.source - 180, 1);
    await page.screenshot({ path: testInfo.outputPath(`composer-diff-${theme}-scrolled.png`) });
  }
  expect(app.pageErrors).toEqual([]);
});

test('review hunk context stays independent and sends only selected snapshots', async ({ page }, testInfo) => {
  const app = new DesktopBrowserHarness(page);
  const old = ['fn first() -> Int {', '  1', '}', ...Array(24).fill(''), 'fn second() -> Int {', '  2', '}', ''].join('\n');
  app.gitFilesByRevision[app.gitBaseline]['src/main.mbt'] = old;
  app.workingFiles['src/main.mbt'] = old.replace('  1', '  100').replace('  2', '  200');
  await openReview(page, app);
  const first = contextButtons(page).first();
  await expect(first).toHaveText('Add to context');
  const context = first.locator('..');
  await expect(context).toHaveCSS('opacity', '0');
  await expect(context).toHaveCSS('pointer-events', 'none');
  await hoverContextHunk(page, first);
  await page.mouse.move(0, 0);
  await expect(context).toHaveCSS('opacity', '0');
  await clickHunkContext(page, first);
  await expect(first).toHaveText('In context');
  await expect(first).toBeFocused();
  await page.mouse.move(0, 0);
  await expect(context).toHaveCSS('opacity', '0');
  await expect(context).toHaveCSS('pointer-events', 'none');
  await expect(page.getByRole('button', { name: 'Mark hunk viewed', exact: true })).toHaveAttribute('aria-pressed', 'false');
  await page.getByRole('button', { name: 'Mark hunk viewed', exact: true }).click();
  await expect(first).toHaveText('In context');
  const chip = page.locator('.composer-changes .changes-chip .mention-jump');
  await expect(chip).toContainText('Changes · 1 file');
  await page.locator('#task').fill('Extract the selected change');
  await chip.click();
  const popup = page.getByRole('dialog', { name: 'Selected changes' });
  await expect(popup).toBeVisible();
  await expect(popup.locator('.changes-preview')).toContainText('100');
  await expect(popup.locator('.changes-preview')).not.toContainText('200');
  await expect(popup).toContainText('Only selected changes are included.');
  // The composer preview needs the token palette outside the editor host.
  const selectedPreview = await popup.locator('.editor-diff-source').allTextContents();
  const plainColor = await popup.locator('.editor-diff-source').first().evaluate(node => getComputedStyle(node).color);
  await expect.poll(() => popup.locator('.mtk6').first().evaluate(node => getComputedStyle(node).color))
    .not.toBe(plainColor);
  await page.screenshot({ path: testInfo.outputPath('selected-context.png') });
  await popup.getByRole('button', { name: 'Open in review', exact: true }).click();
  await expect(popup).toBeHidden();
  await expect(first).toHaveText('In context');
  await chip.click();
  await page.keyboard.press('Escape');
  await expect(popup).toBeHidden();
  await chip.click();
  await popup.getByRole('button', { name: 'Remove change', exact: true }).click();
  await expect(chip).toHaveCount(0);
  await expect(first).toHaveText('Add to context');
  await expect(page.locator('#task')).toHaveValue('Extract the selected change');
  await clickHunkContext(page, first);
  await expect(chip).toContainText('Changes · 1 file');
  await page.getByTitle('Send', { exact: true }).click();
  await expect.poll(() => app.requests.find(request => request.method === 'agent.start')?.params.task).toContain('<review_changes workspace=');
  const prompt = app.requests.find(request => request.method === 'agent.start').params.task;
  expect(prompt).toContain('Extract the selected change');
  expect(prompt).toContain(`<review_changes workspace="/workspace" base="${app.gitBaseline}">`);
  expect(prompt).toMatch(/<file path="src\/main\.mbt" version="[a-f0-9]{64}">/);
  expect(prompt).toContain('<hunk>\n<original lines="2">\n  1\n</original>\n<modified lines="2">\n  100\n</modified>\n</hunk>');
  expect(prompt).not.toContain('\n  200\n');
  await expect(chip).toHaveCount(0);
  await expect(first).toHaveText('Add to context');
  const event = {
    sequence: 18,
    item: { kind: 'user', payload: {
      content: prompt,
      submission_id: app.requests.find(request => request.method === 'agent.start').params.submission_id,
    } },
  };
  app.notify('session.event', {
    session: 'session-1', session_root: '/workspace/.openseek', sequence: event.sequence, event,
  });
  const sentChip = page.locator('.user-bubble .changes-chip .mention-jump');
  await expect(sentChip).toHaveText('Changes · 1 file');
  await sentChip.click();
  await expect(popup).toContainText('Included in this message');
  await expect(popup.locator('.editor-diff-source')).toHaveText(selectedPreview);
  await expect(popup.getByRole('button', { name: /Remove/ })).toHaveCount(0);
  await popup.getByRole('button', { name: 'Open in review', exact: true }).click();
  await expect(popup).toBeHidden();
  await expect(first).toHaveText('Add to context');
  // Reload from the persisted message text, without any composer state.
  app.sessionEvents = [
    app.sessionEvents[0],
    { sequence: 2, item: { kind: 'user', payload: { content: prompt } } },
  ];
  await page.reload();
  await app.openSession();
  await sentChip.click();
  await expect(popup.locator('.editor-diff-source')).toHaveText(selectedPreview);
  await expect(popup.getByRole('button', { name: /Remove/ })).toHaveCount(0);
  await page.screenshot({ path: testInfo.outputPath('sent-context-reloaded.png') });
  await page.keyboard.press('Escape');
  await expect(sentChip).toBeFocused();
  // A fresh session has no Review inventory yet. The saved message must be
  // enough to open and load the review without visiting the panel first.
  await expect(contextButtons(page)).toHaveCount(0);
  const changesRequests = app.requests.filter(request => request.method === 'git.changes').length;
  await sentChip.click();
  await popup.getByRole('button', { name: 'Open in review', exact: true }).click();
  await expect(popup).toBeHidden();
  await expect(first).toHaveText('Add to context');
  await expect(page.locator('.notification')).toHaveCount(0);
  expect(app.requests.filter(request => request.method === 'git.changes').length).toBeGreaterThan(changesRequests);
  await page.screenshot({ path: testInfo.outputPath('sent-context-cold-review.png') });
  expect(app.pageErrors).toEqual([]);
});

test('review context survives regrouping and a partial group changes only on explicit action', async ({ page }, testInfo) => {
  const app = new DesktopBrowserHarness(page);
  // Line groups nearby edits together; semantic sections split the functions.
  const old = 'fn first() -> Int { 1 }\n\nfn second() -> Int { 2 }\n';
  app.gitFilesByRevision[app.gitBaseline]['src/main.mbt'] = old;
  app.workingFiles['src/main.mbt'] = old.replace('{ 1 }', '{ 10 }').replace('{ 2 }', '{ 20 }');
  await openReview(page, app);
  await page.getByRole('button', { name: 'Token diff', exact: true }).click();
  await expect(contextButtons(page)).toHaveCount(2);
  await clickHunkContext(page);
  await expect(contextButtons(page).first()).toHaveText('In context');
  await expect(contextButtons(page).last()).toHaveText('Add to context');
  await page.getByRole('button', { name: 'Line diff', exact: true }).click();
  await expect(contextButtons(page)).toHaveCount(1);
  await expect(contextButtons(page)).toHaveText('Partly in context');
  await page.locator('.composer-changes .changes-chip .mention-jump').click();
  const popup = page.getByRole('dialog', { name: 'Selected changes' });
  await expect(popup).toContainText('10');
  await expect(popup.locator('.changes-preview')).not.toContainText('20');
  await page.keyboard.press('Escape');
  // Dismissal restores focus in an after-render command. Finish that transition
  // before opening the hunk menu, whose outside-focus listener would close it.
  await expect(popup).toBeHidden();
  await expect(page.locator('.composer-changes .changes-chip .mention-jump')).toBeFocused();
  await clickHunkContext(page, contextButtons(page));
  await expect(page.getByRole('menuitem', { name: 'Add remaining changes' })).toBeVisible();
  const menu = page.getByRole('menu');
  const sash = await page.locator('.moonbit-diff-editor-sash:visible').boundingBox();
  const menuBounds = await menu.boundingBox();
  const point = { x: sash.x + sash.width / 2, y: menuBounds.y + menuBounds.height / 2 };
  expect(point.x).toBeGreaterThan(menuBounds.x);
  expect(point.x).toBeLessThan(menuBounds.x + menuBounds.width);
  expect(await menu.evaluate((node, point) => node.contains(document.elementFromPoint(point.x, point.y)), point))
    .toBe(true);
  await page.screenshot({ path: testInfo.outputPath('partial-context.png') });
  await page.keyboard.press('ArrowDown');
  await expect(page.getByRole('menuitem', { name: 'Add remaining changes' })).toBeFocused();
  await page.keyboard.press('Enter');
  await expect(contextButtons(page)).toHaveText('In context');
  await expect(contextButtons(page)).toBeFocused();
  await page.getByRole('button', { name: 'Tree diff', exact: true }).click();
  await expect(contextButtons(page)).toHaveCount(2);
  for (const button of await contextButtons(page).all()) await expect(button).toHaveText('In context');
  await clickHunkContext(page, contextButtons(page).last());
  await page.getByRole('button', { name: 'Line diff', exact: true }).click();
  await expect(contextButtons(page)).toHaveCount(1);
  await expect(contextButtons(page)).toHaveText('Partly in context');
  await clickHunkContext(page, contextButtons(page));
  await page.getByRole('menuitem', { name: 'Remove included changes' }).click();
  await expect(page.locator('.composer-changes .changes-chip')).toHaveCount(0);
  await expect(contextButtons(page)).toHaveText('Add to context');
  expect(app.pageErrors).toEqual([]);
});

test('Codex composer groups multiple files and preserves deletion context on send', async ({ page }, testInfo) => {
  const app = new DesktopBrowserHarness(page);
  app.codexModels = [{ id: 'gpt-5.4-codex', displayName: 'GPT-5.4 Codex', isDefault: true,
    defaultReasoningEffort: 'medium', supportedReasoningEfforts: [{ reasoningEffort: 'medium', description: 'Balanced' }] }];
  app.gitChanges[1] = { path: 'src/lib.mbt', index_status: ' ', worktree_status: 'D', kind: 'deleted' };
  delete app.workingFiles['src/lib.mbt'];
  await app.install();
  await app.goto();
  await page.getByRole('button', { name: 'Model', exact: true }).click();
  await page.getByRole('option', { name: 'GPT-5.4 Codex' }).click();
  await app.openReview();
  const files = page.locator('#review-changes-body');
  await files.getByRole('treeitem', { name: /View diff: src\/main\.mbt/ }).click();
  await clickHunkContext(page);
  await files.getByRole('treeitem', { name: /View diff: src\/lib\.mbt/ }).click();
  await clickHunkContext(page);
  const chip = page.locator('.composer-changes .changes-chip .mention-jump');
  await expect(chip).toContainText('Changes · 2 files');
  await chip.click();
  const popup = page.getByRole('dialog', { name: 'Selected changes' });
  const deleted = popup.locator('.changes-file').filter({ hasText: 'lib.mbt' });
  await expect(deleted.locator('.editor-diff-row.removed').first()).toBeVisible();
  await expect(deleted.locator('.editor-diff-row.added')).toHaveCount(0);
  await popup.getByTitle('src/lib.mbt', { exact: true }).click();
  await expect(deleted.locator('.changes-preview')).toHaveCount(0);
  await popup.getByTitle('src/lib.mbt', { exact: true }).click();
  await expect(deleted.locator('.changes-preview')).toBeVisible();
  // A narrow composer owns its popup width and independently scrolls long diffs.
  await page.setViewportSize({ width: 1060, height: 800 });
  await page.screenshot({ path: testInfo.outputPath('codex-multiple-files.png') });
  const box = await popup.boundingBox();
  expect(box.x).toBeGreaterThanOrEqual(0);
  expect(box.x + box.width).toBeLessThanOrEqual(1060);
  await page.keyboard.press('Escape');
  await expect(chip).toBeFocused();
  await page.locator('#task').fill('Explain these selected changes');
  await page.getByTitle('Send', { exact: true }).click();
  await expect.poll(() => app.requests.find(request => request.method === 'codex.turn.start'))
    .toBeTruthy();
  const input = app.requests.find(request => request.method === 'codex.turn.start').params.input;
  const selected = input.filter(item => item.type === 'text' && item.text.includes('<review_changes workspace='));
  expect(selected).toHaveLength(1);
  expect(selected[0].text.match(/<review_changes /g)).toHaveLength(1);
  expect(selected[0].text).toContain('<file path="src/main.mbt"');
  const deletion = selected[0].text.split('<file path="src/lib.mbt"')[1].split('</file>')[0];
  expect(deletion).toContain('<modified/>');
  expect(deletion).toContain('\n  41\n');
  expect(deletion).toContain('<original lines=');
  await expect(chip).toHaveCount(0);
  const sentChip = page.locator('.user-bubble .changes-chip .mention-jump');
  await expect(sentChip).toHaveText('Changes · 2 files');
  await sentChip.click();
  await expect(popup.locator('.changes-file')).toHaveCount(2);
  await expect(popup.locator('.changes-file').filter({ hasText: 'lib.mbt' })
    .locator('.editor-diff-row.added')).toHaveCount(0);
  await expect(popup.getByRole('button', { name: /Remove/ })).toHaveCount(0);
  await page.screenshot({ path: testInfo.outputPath('codex-sent-multiple-files.png') });
  expect(app.pageErrors).toEqual([]);
});


test('saved message changes keep independent disclosures and immutable previews', async ({ page }, testInfo) => {
  const app = new DesktopBrowserHarness(page);
  const selection = (file, oldText, newText, oldLine = 8, newLine = 9) => `<file path="${file}" version="saved-comparison">\n<hunk>\n<original lines="${oldLine}">\n${oldText}\n</original>\n<modified lines="${newLine}">\n${newText}\n</modified>\n</hunk>\n</file>`;
  const prompt = (task, selections) => `${task}\n\n<user_mentions>\n<review_changes workspace="/workspace">\n${
    selections.join('\n\n')
  }\n</review_changes>\n</user_mentions>`;
  app.sessionEvents = [
    { sequence: 1, item: { kind: 'user', payload: { content: prompt('Show the browser fixture first snapshot', [
      selection('src/main.mbt', 'let old_value = 1', 'let saved_value = 2'),
      selection('deleted/file.txt', 'saved removed text', 'saved replacement text'),
      selection('src/main.mbt', 'let later = 3', 'let later = 4', 20, 21),
    ]) } } },
    { sequence: 2, item: { kind: 'user', payload: { content: prompt('Second snapshot', [
      selection('src/main.mbt', 'let old_value = 10', 'let another_value = 20'),
    ]) } } },
  ];
  // Current files intentionally do not contain the saved text.
  app.workingFiles['src/main.mbt'] = 'fn main { println("current workspace") }\n';
  await app.install();
  await app.goto();
  await app.openSession();
  const chips = page.locator('.user-bubble .changes-chip .mention-jump');
  await expect(chips).toHaveText(['Changes · 2 files', 'Changes · 1 file']);
  await chips.first().click();
  const popup = page.getByRole('dialog', { name: 'Selected changes' });
  await expect(popup).toContainText('let saved_value = 2');
  await expect(popup).not.toContainText('current workspace');
  await expect(popup.locator('.changes-range').first()).toHaveText('Old L8 → New L9');
  await expect(popup.getByRole('region')).toHaveCount(3);
  for (const name of ['src/main.mbt: Old L8 → New L9', 'src/main.mbt: Old L20 → New L21',
    'deleted/file.txt: Old L8 → New L9']) {
    await expect(popup.getByRole('region', { name, exact: true })).toBeVisible();
  }
  await popup.getByTitle('src/main.mbt', { exact: true }).click();
  await expect(popup.locator('.changes-file').first().locator('.changes-preview')).toHaveCount(0);
  await page.evaluate(() => {
    Object.defineProperty(navigator, 'languages', { configurable: true, value: ['ja-JP'] });
    window.dispatchEvent(new Event('languagechange'));
  });
  const localizedPopup = page.getByRole('dialog', { name: '選択した変更', exact: true });
  await expect(localizedPopup).toBeVisible();
  await expect(chips.first()).toHaveText('変更 · 2 ファイル');
  await expect(localizedPopup.locator('.changes-file').first().locator('.changes-preview')).toHaveCount(0);
  await expect(localizedPopup).toContainText('このメッセージに含まれています');
  await page.evaluate(() => {
    Object.defineProperty(navigator, 'languages', { configurable: true, value: ['en'] });
    window.dispatchEvent(new Event('languagechange'));
  });
  await expect(popup).toBeVisible();
  await chips.last().click();
  await expect(page.getByRole('dialog', { name: 'Selected changes' })).toHaveCount(1);
  await expect(popup.locator('.changes-preview')).toContainText('let another_value = 20');
  await chips.first().click();
  await expect(popup.locator('.changes-file').first().locator('.changes-preview')).toHaveCount(0);
  await popup.getByTitle('src/main.mbt', { exact: true }).click();
  await expect(popup.locator('.changes-preview').first()).toContainText('let saved_value = 2');
  await page.setViewportSize({ width: 860, height: 640 });
  await chips.first().scrollIntoViewIfNeeded();
  await expect(popup).toBeVisible();
  const box = await popup.boundingBox();
  expect(box.x).toBeGreaterThanOrEqual(0);
  expect(box.y).toBeGreaterThanOrEqual(0);
  expect(box.x + box.width).toBeLessThanOrEqual(860);
  expect(box.y + box.height).toBeLessThanOrEqual(640);
  await page.screenshot({ path: testInfo.outputPath('saved-message-changes-narrow.png') });
  await page.getByText('Ready', { exact: true }).click();
  await expect(popup).toBeHidden();
  await page.locator('#task').click();
  await expect(page.locator('#task')).toBeFocused();
  await chips.first().click();
  await popup.getByRole('button', { name: 'Close selected changes', exact: true }).click();
  await expect(popup).toBeHidden();
  await expect(chips.first()).toBeFocused();
  expect(app.pageErrors).toEqual([]);
});


test('saved change excerpts preserve discontinuous coordinates and literal source', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  app.sessionEvents = [{ sequence: 1, item: { kind: 'user', payload: { content: `Show the browser fixture saved snapshot

<user_mentions>
<review_changes workspace="/workspace">
<file path="notes.txt" version="saved-comparison">
<hunk>
<original lines="8">
<before> & old
</original>
<original lines="12">
last removed
</original>
<modified lines="9">
<after> & new
</modified>
<modified lines="15">
last added
</modified>
</hunk>
</file>
</review_changes>
</user_mentions>` } } }];
  await app.install();
  await app.goto();
  await app.openSession();
  await page.locator('.user-bubble .changes-chip .mention-jump').click();
  const preview = page.getByRole('dialog', { name: 'Selected changes' }).locator('.editor-diff-preview');
  await expect(preview.locator('.editor-diff-number')).toHaveText(['8', '', '12', '9', '', '15']);
  await expect(preview.locator('.editor-diff-source')).toHaveText([
    '<before> & old', '…', 'last removed', '<after> & new', '…', 'last added',
  ]);
  await expect(preview.locator('.editor-diff-row.gap')).toHaveCount(2);
  await expect(preview.locator('before, after')).toHaveCount(0);
  expect(app.pageErrors).toEqual([]);
});
