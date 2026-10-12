import { test, expect } from '@playwright/test';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';

for (const existing of [false, true]) {
  test(`PDF annotations recover a temporarily missing anchor (${existing ? 'replacement' : 'first selection'})`, async ({ page }) => {
    const app = new DesktopBrowserHarness(page);
    app.searchFiles = ['docs/report.pdf'];
    await app.install();
    await app.goto();
    await app.openSession();
    await page.getByRole('button', { name: 'Hide sidebar', exact: true }).click();
    await app.openReview({ waitForHistory: false });
    await page.getByRole('tab', { name: 'Files', exact: true }).click();
    await app.openQuickOpen();
    await page.locator('#quick-open-input').fill('report.pdf');
    await page.getByRole('option', { name: /report\.pdf/ }).click();
    await expect(page.locator('#openseek-office-surface')).toHaveAttribute('data-pdf-painted', 'true');
    const items = page.locator('.page[data-page-number="1"] [data-pdf-item]');
    const select = async item => item.evaluate(element => {
      const range = document.createRange();
      range.selectNodeContents(element);
      const selection = getSelection();
      selection.removeAllRanges();
      selection.addRange(range);
      document.dispatchEvent(new Event('selectionchange'));
    });
    const input = page.locator('#office-feedback-input textarea');
    if (existing) {
      await select(items.first());
      await expect(input).toBeVisible();
    }
    // Inject a text-layer replacement precisely between PDF.js delivering
    // the selection and the host's after-render mounting command.
    await page.evaluate(() => {
      const runtime = document.getElementById('openseek-office-surface').__officeViewerPdf;
      const deliver = runtime.options.onSelection;
      runtime.options.onSelection = value => {
        runtime.options.onSelection = deliver;
        const reference = JSON.parse(value).reference;
        const { page, item_index } = reference.start;
        const item = document.querySelector(`[data-pdf-page="${page}"][data-pdf-item="${item_index}"]`);
        const placeholder = document.createComment('text layer being replaced');
        deliver(value);
        item.replaceWith(placeholder);
        getSelection().removeAllRanges();
        window.pendingAnnotationAnchor = { item, placeholder, reference };
      };
    });
    const target = items.nth(existing ? 1 : 0);
    const text = await target.textContent();
    await select(target);
    await expect.poll(() => page.evaluate(() => Boolean(window.pendingAnnotationAnchor))).toBe(true);
    await expect(input).toBeHidden();
    const reference = await page.evaluate(() => {
      const pending = window.pendingAnnotationAnchor;
      pending.placeholder.replaceWith(pending.item);
      return pending.reference;
    });
    await expect(input).toBeVisible();
    await expect(page.locator('#office-feedback-input')).toHaveAttribute('title', new RegExp(text.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')));
    await expect(page.locator('.feedback-source-selection')).not.toHaveCount(0);
    await input.fill('Annotate the recovered selection');
    await page.locator('#office-feedback-input').getByRole('checkbox').check();
    await input.press('Enter');
    await page.locator('#task').fill('Explain the selected passage');
    await page.getByTitle('Send', { exact: true }).click();
    await expect.poll(() => app.requests.find(r => r.method === 'agent.start')?.params.task).toContain('<office_selection>');
    const task = app.requests.find(r => r.method === 'agent.start').params.task;
    const quote = JSON.parse(task.match(/<office_selection>([\s\S]*?)<\/office_selection>/)[1]);
    expect(quote.source.reference).toEqual(reference);
    expect(quote.selection.text).toBe(text);
    expect(quote.comment).toBe('Annotate the recovered selection');
    expect(app.pageErrors).toEqual([]);
  });
}

test('an unavailable Word anchor clears the old composer and permits reselection', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  app.searchFiles = ['docs/report.docx'];
  await app.install();
  await app.goto();
  await app.openSession();
  await page.getByRole('button', { name: 'Hide sidebar', exact: true }).click();
  await app.openReview({ waitForHistory: false });
  await page.getByRole('tab', { name: 'Files', exact: true }).click();
  await app.openQuickOpen();
  await page.locator('#quick-open-input').fill('report.docx');
  await page.getByRole('option', { name: /report\.docx/ }).click();
  const source = page.locator('.word-page svg text').first();
  const select = (end, clear) => source.evaluate((element, { end, clear }) => {
    const range = document.createRange();
    range.setStart(element.firstChild, 0);
    range.setEnd(element.firstChild, end);
    const selection = getSelection();
    selection.removeAllRanges();
    selection.addRange(range);
    document.dispatchEvent(new Event('selectionchange'));
    if (clear) selection.removeAllRanges();
  }, { end, clear });
  const input = page.locator('#office-feedback-input textarea');
  await select(4, false);
  await expect(input).toBeVisible();
  await select(7, true);
  await expect(input).toBeHidden();
  await expect(page.locator('#office-feedback-input')).toBeHidden();
  await select(7, false);
  await expect(input).toBeVisible();
  await input.fill('A fresh, valid source');
  await expect(input).toHaveValue('A fresh, valid source');
  expect(app.pageErrors).toEqual([]);
});
