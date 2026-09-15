import { test, expect } from '@playwright/test';
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
      await page.getByRole('button', { name: 'Code search', exact: true }).click();
      await page.getByRole('textbox', { name: 'pattern', exact: true }).fill('inspect($(x:arg))');
    } else {
      await page.getByRole('textbox', { name: 'Search', exact: true }).fill('moon');
    }
    const results = page.locator('.search-results');
    const row = results.locator('.search-result-row');
    const destination = row.getByRole('button', { name: mode === 'Text' ? /moon moon/ : /inspect\($/ });
    await expect(row).toBeVisible();
    if (mode === 'Code') {
      await expect(row.locator('.search-result-line')).toHaveText(['1', '2', '3', '4', '5', '6']);
      await expect(row.getByRole('button', { name: /second/ })).toHaveAttribute('title', 'Open src/main.mbt:5');
    }
    await expect(results.locator('.search-summary')).toHaveText(
      '2 matches in 1 file',
    );
    await expect(row.locator('.search-match-highlight')).toHaveText(
      mode === 'Text' ? ['moon', 'moon'] : ['inspect(', '    "moon moon",', '  )', 'inspect("second")'],
    );
    // Preview blocks must fit the panel, and every line must share its gutter
    // and text columns after neighboring contexts have been combined.
    const geometry = await row.evaluate(element => {
      const rect = element.getBoundingClientRect();
      const panel = element.closest('.search-results').getBoundingClientRect();
      return {
        overflow: Math.max(0, rect.right - panel.right),
        textStarts: [...element.querySelectorAll('.search-result-preview')].map(node => node.getBoundingClientRect().left),
      };
    });
    expect(geometry.overflow).toBeLessThanOrEqual(1);
    expect(Math.max(...geometry.textStarts) - Math.min(...geometry.textStarts)).toBeLessThanOrEqual(1);
    await destination.focus();
    await page.keyboard.press('Enter');
    await expect(page.locator('#viewer-host .view-lines')).toContainText('moon moon');
    const header = results.getByRole('button', { name: /main.mbt.*src/ });
    const expectChevronAligned = async () => {
      const offset = await header.evaluate(element => {
        const icon = element.querySelector('.search-file-chevron svg').getBoundingClientRect();
        const name = element.querySelector('.search-file-name').getBoundingClientRect();
        return Math.abs((icon.top + icon.bottom - name.top - name.bottom) / 2);
      });
      expect(offset).toBeLessThanOrEqual(1);
    };
    await expectChevronAligned();
    await expect(results).not.toContainText(app.semanticSearchMatches[0].rule_id);
    await header.click();
    await expectChevronAligned();
    await expect(row).toBeHidden();
    await header.click();
    await expect(row).toBeVisible();
    scanFailed = true;
    await page.locator('.workspace-search').getByRole('button', { name: 'Refresh', exact: true }).click();
    await expect(results.getByRole('alert')).toContainText('One file could not be read.');
    await expect(row).toBeVisible();
    expect(app.pageErrors).toEqual([]);
  });
}

test('code search repairs a pattern in one click', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  const replyFor = app.replyFor.bind(app);
  let repairRequest;
  app.rpcDelays.set('pattern.repair', 30);
  app.replyFor = request => {
    if (request.method === 'pattern.repair') {
      repairRequest = request.params;
      return {
        root: request.params.root,
        generation: request.params.generation,
        candidate_pattern: 'inspect($_)',
        valid: true,
        validation_status: 'passed',
        message: 'Repaired.',
      };
    }
    return replyFor(request);
  };
  await app.install();
  await app.goto();
  await app.openSession();
  const shortcut = await page.evaluate(() =>
    navigator.platform.includes('Mac') ? 'Meta+Shift+F' : 'Control+Shift+F');
  await page.keyboard.press(shortcut);
  await page.getByRole('button', { name: 'Code search', exact: true }).click();
  const pattern = page.getByRole('textbox', { name: 'pattern', exact: true }).first();
  await pattern.fill('inspect($(x:arg');
  await expect(page.getByRole('button', { name: 'Fix Pattern', exact: true })).toBeVisible();
  const repair = page.locator('.pattern-repair-button');
  await repair.click();
  await expect(repair).toBeDisabled();
  await expect(page.locator('.search-pattern-repair-status')).toHaveText('Repairing pattern…');
  await expect(pattern).toHaveValue('inspect($_)');
  await expect(page.locator('.search-pattern-repair-status')).toBeHidden();
  expect(repairRequest.instruction).toBe(
    'Repair this MoonBit pattern with the smallest syntax-only change.',
  );
  await expect.poll(() => app.requests
    .filter(request => request.method === 'fs.search_semantic')
    .at(-1)?.params?.patterns?.[0]).toBe('inspect($_)');
  await expect(page.getByRole('textbox', { name: 'Pattern repair instruction' })).toHaveCount(0);
  await expect(page.getByRole('button', { name: 'Use pattern' })).toHaveCount(0);
  expect(app.pageErrors).toEqual([]);
});
