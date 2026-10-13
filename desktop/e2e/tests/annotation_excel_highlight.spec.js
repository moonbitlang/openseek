import { test, expect } from '@playwright/test';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';

test('Excel annotation highlights retain the full source range while the live selection moves', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  app.searchFiles = ['docs/book1.xlsx'];
  await app.install();
  await app.goto();
  await app.openSession();
  await page.getByRole('button', { name: 'Hide sidebar', exact: true }).click();
  await app.openReview({ waitForHistory: false });
  await page.getByRole('tab', { name: 'Files', exact: true }).click();
  await app.openQuickOpen();
  await page.locator('#quick-open-input').fill('book1.xlsx');
  await page.getByRole('option', { name: /book1\.xlsx/ }).click();
  const cell = address => page.locator(`.sheet-document section:not([hidden]) td[data-cell="${address}"]`);
  const first = await cell('A1').boundingBox();
  const last = await cell('B2').boundingBox();
  await page.mouse.move(first.x + first.width / 2, first.y + first.height / 2);
  await page.mouse.down();
  await page.mouse.move(last.x + last.width / 2, last.y + last.height / 2);
  await page.mouse.up();
  const preview = page.locator('#office-feedback-input');
  const input = preview.locator('textarea');
  await expect(input).toBeVisible();
  await expect(preview).toHaveAttribute('title', /A1:B2/);
  await input.fill('Explain the original four cells');
  await cell('A1').click();
  await expect(page.locator('.office-cell-selected')).toHaveCount(1);
  await expect(preview).toHaveAttribute('title', /A1:B2/);
  await expect(input).toHaveValue('Explain the original four cells');
  const highlightedCells = () => page.evaluate(() => {
    const highlights = [...document.querySelectorAll('.feedback-source-selection')].map(el => el.getBoundingClientRect());
    return [...document.querySelectorAll('.sheet-document section:not([hidden]) td[data-cell]')].filter(cell => {
      const rect = cell.getBoundingClientRect();
      return highlights.some(h => Math.abs(h.left - rect.left) < 1 && Math.abs(h.top - rect.top) < 1
        && Math.abs(h.width - rect.width) < 1 && Math.abs(h.height - rect.height) < 1);
    }).map(cell => cell.dataset.cell).sort();
  });
  await expect.poll(highlightedCells).toEqual(['A1', 'A2', 'B1', 'B2']);
  await page.getByRole('button', { name: 'Zoom in', exact: true }).click();
  await expect.poll(highlightedCells).toEqual(['A1', 'A2', 'B1', 'B2']);
  await preview.getByRole('checkbox').check();
  await input.press('Enter');
  await expect(input).toBeHidden();
  await expect(page.locator('.feedback-source-selection')).toHaveCount(0);
  await page.locator('#task').fill('Inspect the annotated cells');
  await page.getByTitle('Send', { exact: true }).click();
  await expect.poll(() => app.requests.find(r => r.method === 'agent.start')?.params.task).toContain('<office_selection>');
  const task = app.requests.find(r => r.method === 'agent.start').params.task;
  const quote = JSON.parse(task.match(/<office_selection>([\s\S]*?)<\/office_selection>/)[1]);
  expect(quote.selection.range).toBe('A1:B2');
  expect(quote.comment).toBe('Explain the original four cells');
  expect(app.pageErrors).toEqual([]);
});
