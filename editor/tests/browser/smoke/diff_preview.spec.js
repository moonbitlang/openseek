import { expect, test } from '../support/test.js';

// Subgrid sizing, sticky gutters and glyph bounds require a real browser.
for (const theme of ['light', 'dark']) {
  test(`static diff pins complete gutters in ${theme} theme`, async ({ page }, testInfo) => {
    await page.setViewportSize({ width: 640, height: 900 });
    await page.goto('/diff-preview.html');
    if (theme === 'dark') await page.getByRole('button', { name: 'Dark theme' }).click();
    await expect(page.locator('.diff-preview-demo')).toHaveAttribute('data-theme', theme);
    const card = page.locator('.preview-card').first();
    const preview = card.locator('.editor-diff-preview');
    await expect(preview).toHaveAccessibleName('src/main.mbtx: recorded changes');
    const gutters = preview.locator('.editor-diff-gutter');
    const before = await gutters.evaluateAll(nodes => nodes.map(node => node.getBoundingClientRect().x));
    const titleBefore = await card.locator('.preview-title').boundingBox();
    const sourceBefore = await preview.locator('.editor-diff-source').first().boundingBox();
    const geometry = await preview.evaluate(el => ({
      width: el.clientWidth, scrollWidth: el.scrollWidth,
      rows: [...el.querySelectorAll('.editor-diff-row')].map(row => ({
        width: row.getBoundingClientRect().width, height: row.getBoundingClientRect().height,
      })),
      lineHeight: parseFloat(getComputedStyle(el).lineHeight),
    }));
    expect(geometry.scrollWidth).toBeGreaterThan(geometry.width);
    for (const row of geometry.rows) {
      expect(row.height).toBeCloseTo(geometry.lineHeight, 0);
      expect(row.width).toBeCloseTo(geometry.rows[0].width, 0);
    }
    const cells = await gutters.evaluateAll(nodes => nodes.map(node => {
      return [...node.children].map(cell => {
        const range = document.createRange(); range.selectNodeContents(cell);
        return { x: cell.getBoundingClientRect().x, textRight: range.getBoundingClientRect().right };
      });
    }));
    for (const row of cells) {
      if (row[0].textRight > 0) expect(row[1].x - row[0].textRight).toBeGreaterThanOrEqual(7);
      expect(row).toHaveLength(2);
    }
    await expect(preview.locator('.context .editor-diff-number')).toHaveText(['1528', '1531']);
    await expect(preview.locator('.removed .editor-diff-number')).toHaveText(['1529', '99999']);
    await expect(preview.locator('.added .editor-diff-number')).toHaveText(['1529', '1530', '100000']);
    await expect(preview.locator('.editor-diff-number', { hasText: /^100000$/ })).toBeVisible();
    await preview.evaluate(el => { el.scrollLeft = 180; });
    await expect.poll(() => preview.evaluate(el => el.scrollLeft)).toBe(180);
    expect(await gutters.evaluateAll(nodes => nodes.map(node => node.getBoundingClientRect().x))).toEqual(before);
    expect(await card.locator('.preview-title').boundingBox()).toEqual(titleBefore);
    const sourceAfter = await preview.locator('.editor-diff-source').first().boundingBox();
    expect(sourceBefore.x - sourceAfter.x).toBe(180);
    const paint = await gutters.first().evaluate(el => {
      const box = el.getBoundingClientRect();
      return el.contains(document.elementFromPoint(box.right - 2, box.y + box.height / 2));
    });
    expect(paint).toBe(true);
    await card.screenshot({ path: testInfo.outputPath(`pinned-${theme}.png`) });
    await page.getByRole('button', { name: 'Wide layout' }).click();
    await expect.poll(() => preview.evaluate(el => el.clientWidth)).toBeGreaterThan(geometry.width);
    await page.setViewportSize({ width: 360, height: 800 });
    expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(360);
    const pinnedLeft = (await preview.boundingBox()).x;
    expect(await gutters.evaluateAll(nodes => nodes.map(node => node.getBoundingClientRect().x)))
      .toEqual(Array(before.length).fill(pinnedLeft));
  });
}

test('static diff preserves side-specific syntax, escaped text and empty rows', async ({ page }) => {
  await page.goto('/diff-preview.html');
  const moonbit = page.locator('.preview-card').nth(0);
  const javascript = page.locator('.preview-card').nth(1);
  const plain = page.locator('.preview-card').nth(2);
  await expect(moonbit.locator('.mtk3', { hasText: 'fn' })).toBeVisible();
  await expect(javascript.locator('.removed .mtk7', { hasText: 'still a comment' })).toBeVisible();
  await expect(javascript.locator('.added .mtk3', { hasText: 'const' }).first()).toBeVisible();
  await expect(javascript.locator('.added .mtk7', { hasText: 'continues here' })).toBeVisible();
  await expect(javascript.locator('.added .mtk5', { hasText: '<img src=x' })).toBeVisible();
  await expect(javascript.locator('img')).toHaveCount(0);
  await expect(plain.locator('.editor-diff-source').first()).toHaveText('<before> & "quoted"');
  await expect(plain.locator('.editor-diff-number').filter({ hasText: /\d/ })).toHaveCount(0);
  const blank = plain.locator('.editor-diff-row').nth(2);
  await expect(blank.locator('.editor-diff-source')).toBeEmpty();
  expect((await blank.boundingBox()).height).toBeGreaterThanOrEqual(21);
});
