import { test, expect } from './support/test.js';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';

for (const mode of ['Text', 'Code']) {
  test(`${mode} results keep previews aligned and support keyboard navigation`, async ({ page }) => {
    const app = new DesktopBrowserHarness(page);
    app.workingFiles['src/main.mbt'] = 'fn main {\n  inspect(\n    "moon moon",\n  )\n  inspect("second")\n}\n';
    app.textSearchMatches = [{
      path: 'src/main.mbt', line_number: 3,
      preview: '    "moon moon",', preview_start_column: 1,
      ranges: [{ start_column: 6, end_column: 10 }, { start_column: 11, end_column: 15 }],
    }];
    app.textSearchMatchCount = 2;
    app.semanticSearchMatches = [{
      path: 'src/main.mbt', rule_id: 'inspect($(argument:arg))'.repeat(15),
      description: 'A long rule name must fit within the result panel.',
      start_line: 2, start_column: 3, end_line: 4, end_column: 4,
      matched_source: 'inspect(\n    "moon moon",\n  )',
      source_context: app.workingFiles['src/main.mbt'].trimEnd().split('\n').slice(0, 5).map((text, index) => ({
        line: index + 1, text, is_match: index >= 1 && index <= 3,
      })),
    }];
    app.semanticSearchMatches.push({
      ...app.semanticSearchMatches[0],
      start_line: 5, start_column: 3, end_line: 5, end_column: 20,
      matched_source: 'inspect("second")',
      source_context: app.workingFiles['src/main.mbt'].trimEnd().split('\n').slice(2).map((text, index) => ({
        line: index + 3, text, is_match: index === 2,
      })),
    });
    // Both providers can finish with useful rows and a diagnostic.
    const replyFor = app.replyFor.bind(app);
    let scanFailed = false;
    app.replyFor = request => {
      const reply = replyFor(request);
      if (scanFailed && ['fs.search_text', 'fs.search_semantic'].includes(request.method)) {
        return { ...reply, error_code: 'search_failed', error_message: 'One file could not be read.' };
      }
      return reply;
    };
    await app.install();
    await app.goto();
    await app.openSession();
    const shortcut = await page.evaluate(() =>
      navigator.platform.includes('Mac') ? 'Meta+Shift+F' : 'Control+Shift+F');
    await page.keyboard.press(shortcut);
    if (mode === 'Code') {
      await page.locator('#search-mode-code').click();
      await page.locator('#search-pattern-0').fill('inspect($(x:arg))');
    } else {
      await page.locator('#workspace-search-input').fill('moon');
    }
    const results = page.locator('.search-results');
    const row = results.locator('.search-result-row');
    const expectedRowCount = mode === 'Text' ? 1 : 2;
    const expectVisibleRows = async () => {
      await expect(row).toHaveCount(expectedRowCount);
      for (let index = 0; index < expectedRowCount; index++) {
        await expect(row.nth(index)).toBeVisible();
      }
    };
    const destination = row.first().locator(`.search-preview-line[data-line="${mode === 'Text' ? 3 : 2}"]`);
    await expectVisibleRows();
    if (mode === 'Code') {
      await expect(row.nth(0).locator('.search-result-line')).toHaveText(['1', '2', '3', '4', '5']);
      await expect(row.nth(1).locator('.search-result-line')).toHaveText(['3', '4', '5', '6']);
      await expect(row.nth(1).locator('.search-preview-line[data-line="5"]')).toHaveAttribute('title', 'Open src/main.mbt:5');
    }
    await expect(results.locator('.search-summary')).toHaveText(
      '2 matches in 1 file',
    );
    if (mode === 'Text') {
      await expect(row.locator('.search-match-highlight')).toHaveText(['moon', 'moon']);
    } else {
      await expect(row.nth(0).locator('.search-match-highlight')).toHaveText([
        'inspect(',
        '    "moon moon",',
        '  )',
      ]);
      await expect(row.nth(1).locator('.search-match-highlight')).toHaveText(['inspect("second")']);
    }
    // Preview blocks must fit the panel, and every line must share its gutter
    // and text columns after neighboring contexts have been combined.
    const geometry = await row.evaluateAll(elements => elements.map(element => {
      const rect = element.getBoundingClientRect();
      const panel = element.closest('.search-results').getBoundingClientRect();
      return {
        overflow: Math.max(0, rect.right - panel.right),
        textStarts: [...element.querySelectorAll('.search-result-preview')].map(node => node.getBoundingClientRect().left),
      };
    }));
    for (const item of geometry) {
      expect(item.overflow).toBeLessThanOrEqual(1);
      expect(Math.max(...item.textStarts) - Math.min(...item.textStarts)).toBeLessThanOrEqual(1);
    }
    await destination.focus();
    await page.keyboard.press('Enter');
    await expect(page.locator('#viewer-host .view-lines')).toContainText('moon moon');
    await expect(results).toBeHidden();
    await page.locator('#file-tree-toggle').click();
    const header = results.locator('.search-file-header[data-path="src/main.mbt"]');
    await header.click();
    await expect(row).toHaveCount(0);
    await header.click();
    await expectVisibleRows();
    scanFailed = true;
    await page.locator('#search-refresh').click();
    await expect(results.getByRole('alert')).toContainText('One file could not be read.');
    await expectVisibleRows();
    expect(app.pageErrors).toEqual([]);
  });
}

test('code search repairs a pattern in one click', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  const replyFor = app.replyFor.bind(app);
  let repairRequest;
  let resolveRepairReply;
  let signalRepairRequest;
  const repairReply = new Promise(resolve => { resolveRepairReply = resolve; });
  const repairRequestStarted = new Promise(resolve => { signalRepairRequest = resolve; });
  app.replyFor = request => {
    if (request.method === 'pattern.repair') {
      repairRequest = request.params;
      signalRepairRequest();
      return repairReply;
    }
    return replyFor(request);
  };
  await app.install();
  await app.goto();
  await app.openSession();
  const shortcut = await page.evaluate(() =>
    navigator.platform.includes('Mac') ? 'Meta+Shift+F' : 'Control+Shift+F');
  await page.keyboard.press(shortcut);
  await page.locator('#search-mode-code').click();
  const pattern = page.locator('#search-pattern-0').first();
  await pattern.fill('inspect($(x:arg');
  await expect(page.locator('#search-fix-pattern')).toBeVisible();
  const repair = page.locator('.pattern-repair-button');
  const repairStatus = page.locator('.search-pattern-repair-status');
  try {
    await repair.click();
    await expect(repair).toBeDisabled();
    await repairRequestStarted;
    await expect(repairStatus).toContainText('Thinking');
    expect(repairRequest).toMatchObject({
      pattern: 'inspect($(x:arg',
      instruction: 'Repair this MoonBit pattern with the smallest syntax-only change.',
    });
    expect(repairRequest.root).toBeTruthy();
    expect(Number.isInteger(repairRequest.generation)).toBe(true);
    expect(app.requests.filter(request => request.method === 'pattern.repair')).toHaveLength(1);
  } finally {
    if (repairRequest) {
      resolveRepairReply({
        root: repairRequest.root,
        generation: repairRequest.generation,
        candidate_pattern: 'inspect($_)',
        validation_status: 'passed',
        message: 'Repaired.',
        trace: [],
      });
    }
  }
  await expect(pattern).toHaveValue('inspect($_)');
  await expect(repairStatus).toBeHidden();
  await expect(repair).toBeEnabled();
  await expect.poll(() => app.requests
    .filter(request => request.method === 'fs.search_semantic')
    .at(-1)?.params?.patterns?.[0]).toBe('inspect($_)');
  await expect(page.locator('.search-pattern-repair textarea')).toHaveCount(0);
  await expect(page.locator('.search-pattern-repair button')).toHaveCount(0);
  expect(app.pageErrors).toEqual([]);
});
