import { test, expect } from '@playwright/test';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';
import { pagedWord, pagedPdf } from './support/page_thumbnail_fixtures.js';

async function openFile(app, name) {
  await app.openQuickOpen();
  await app.page.locator('#quick-open-input').fill(name);
  await app.page.getByRole('option', { name: new RegExp(name.replaceAll('.', '\\.')) }).click();
}

async function setup(page) {
  const app = new DesktopBrowserHarness(page);
  app.officeFiles['docs/pages.docx'] = pagedWord();
  app.officeFiles['docs/pages.pdf'] = pagedPdf();
  app.officeFiles['docs/long.pdf'] = pagedPdf(70);
  app.searchFiles = ['docs/pages.docx', 'docs/pages.pdf', 'docs/long.pdf', 'docs/book1.xlsx'];
  await app.install();
  await app.goto();
  await app.openSession();
  await page.getByRole('button', { name: 'Hide sidebar', exact: true }).click();
  await app.openReview({ waitForHistory: false });
  await page.getByRole('tab', { name: 'Files', exact: true }).click();
  return app;
}

const rail = page => page.getByRole('navigation', { name: 'Page thumbnails', exact: true });
const thumbnail = (page, number) => rail(page).getByRole('button', { name: `Page ${number}`, exact: true });

test('PDF thumbnails paint real pages, navigate, follow scrolling, and rotate', async ({ page }) => {
  const app = await setup(page);
  await openFile(app, 'pages.pdf');
  await expect(page.locator('#openseek-office-surface')).toHaveAttribute('data-pdf-painted', 'true');
  await expect(rail(page)).toBeHidden();
  await page.getByRole('button', { name: 'Page thumbnails', exact: true }).click();
  await expect(rail(page)).toBeVisible();
  await expect(rail(page).locator('.office-page-count')).toHaveText('Pages · 6');
  await expect(thumbnail(page, 1)).toHaveAttribute('data-painted', 'true');
  const colored = await thumbnail(page, 1).locator('canvas').evaluate(canvas => {
    const { data } = canvas.getContext('2d').getImageData(0, 0, canvas.width, canvas.height);
    let count = 0;
    for (let i = 0; i < data.length; i += 4) if (data[i] < 100 && data[i + 1] < 160 && data[i + 2] > 50) count++;
    return count / (canvas.width * canvas.height);
  });
  expect(colored).toBeGreaterThan(0.08);
  await thumbnail(page, 4).click();
  await expect(page.getByRole('spinbutton', { name: 'PDF page number', exact: true })).toHaveValue('4');
  await expect(thumbnail(page, 4)).toHaveAttribute('aria-current', 'page');
  await page.locator('.pdf-container').evaluate(container => {
    container.scrollTop = container.querySelector('[data-page-number="2"]').offsetTop;
  });
  await expect(thumbnail(page, 2)).toHaveAttribute('aria-current', 'page');
  await page.getByRole('button', { name: 'Rotate clockwise', exact: true }).click();
  await expect(thumbnail(page, 2)).toHaveAttribute('data-painted', 'true');
  await expect.poll(() => thumbnail(page, 2).locator('canvas').evaluate(canvas => canvas.width > canvas.height)).toBe(true);
  expect(app.pageErrors).toEqual([]);
});

test('Word thumbnails preserve SVG content and the live surface while navigating by click and keyboard', async ({ page }) => {
  const app = await setup(page);
  await openFile(app, 'pages.docx');
  await expect(page.locator('#openseek-office-surface .word-page')).toHaveCount(6);
  await page.evaluate(() => { window.firstLiveWordPage = document.querySelector('#openseek-office-surface .word-page'); });
  await expect(rail(page)).toBeHidden();
  await page.getByRole('button', { name: 'Page thumbnails', exact: true }).click();
  await expect(thumbnail(page, 1)).toHaveAttribute('data-painted', 'true');
  await expect(thumbnail(page, 1).locator('svg')).toContainText('Document page 1');
  await thumbnail(page, 4).click();
  await expect(thumbnail(page, 4)).toHaveAttribute('aria-current', 'page');
  await expect.poll(() => page.locator('#openseek-office-surface .word-page').nth(3).evaluate(node => {
    const host = node.closest('.office-viewer-surface');
    return Math.abs(node.getBoundingClientRect().top - host.getBoundingClientRect().top - 20);
  })).toBeLessThan(3);
  await page.locator('#openseek-office-surface').evaluate(host => {
    host.scrollTop += host.querySelectorAll('.word-page')[1].getBoundingClientRect().top - host.getBoundingClientRect().top - 20;
  });
  await expect(thumbnail(page, 2)).toHaveAttribute('aria-current', 'page');
  await thumbnail(page, 2).focus();
  await page.keyboard.press('End');
  await expect(thumbnail(page, 6)).toHaveAttribute('aria-current', 'page');
  await page.keyboard.press('ArrowUp');
  await expect(thumbnail(page, 5)).toHaveAttribute('aria-current', 'page');
  await page.getByRole('button', { name: 'Hide page thumbnails', exact: true }).click();
  await expect(rail(page)).toBeHidden();
  expect(await page.evaluate(() => window.firstLiveWordPage === document.querySelector('#openseek-office-surface .word-page'))).toBe(true);
  expect(app.pageErrors).toEqual([]);
});

test('long PDFs load nearby thumbnails and release the old navigator on document switches', async ({ page }) => {
  const app = await setup(page);
  await openFile(app, 'long.pdf');
  await expect(page.locator('#openseek-office-surface')).toHaveAttribute('data-pdf-ready', 'true');
  await page.getByRole('button', { name: 'Page thumbnails', exact: true }).click();
  await expect(thumbnail(page, 1)).toHaveAttribute('data-painted', 'true');
  await expect(rail(page).locator('.office-page-item')).toHaveCount(70);
  expect(await rail(page).locator('canvas').count()).toBeLessThan(12);
  for (const number of [15, 30, 45, 60, 70]) {
    await thumbnail(page, number).click();
    await expect(thumbnail(page, number)).toHaveAttribute('data-painted', 'true');
  }
  expect(await rail(page).locator('canvas').count()).toBeLessThanOrEqual(24);
  await openFile(app, 'pages.docx');
  await expect(rail(page).locator('.office-page-item')).toHaveCount(6);
  await expect(rail(page).locator('canvas')).toHaveCount(0);
  await expect(thumbnail(page, 1).locator('svg')).toBeVisible();
  await openFile(app, 'book1.xlsx');
  await expect(page.locator('#openseek-office-pages')).toBeHidden();
  await expect(page.getByRole('button', { name: 'Page thumbnails', exact: true })).toHaveCount(0);
  expect(app.pageErrors).toEqual([]);
});

test('a narrow preview floats the page window without shrinking the live document', async ({ page }) => {
  const app = await setup(page);
  await openFile(app, 'pages.pdf');
  await expect(page.locator('#openseek-office-surface')).toHaveAttribute('data-pdf-ready', 'true');
  await page.evaluate(() => { document.querySelector('.viewer-stack').style.maxWidth = '460px'; });
  const before = await page.locator('#openseek-office-surface').evaluate(host => host.clientWidth);
  await page.getByRole('button', { name: 'Page thumbnails', exact: true }).click();
  await expect(rail(page)).toHaveAttribute('data-overlay', 'true');
  await expect.poll(() => page.locator('#openseek-office-surface').evaluate(host => host.clientWidth)).toBe(before);
  await thumbnail(page, 3).click();
  await expect(page.getByRole('spinbutton', { name: 'PDF page number', exact: true })).toHaveValue('3');
  await page.getByRole('button', { name: 'Hide page thumbnails', exact: true }).click();
  await expect(page.locator('#openseek-office-pages')).toBeHidden();
  await expect(page.getByRole('spinbutton', { name: 'PDF page number', exact: true })).toHaveValue('3');
  expect(app.pageErrors).toEqual([]);
});
