import { test, expect } from '@playwright/test';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';

async function openCode(page) {
  const app = new DesktopBrowserHarness(page);
  app.sessionEvents = [
    { sequence: 1, item: { kind: 'user', payload: { content: 'Show the browser fixture' } } },
    { sequence: 2, item: { kind: 'assistant', payload: { content: '```text\ncopy this\n```' } } },
  ];
  await page.addInitScript(() => {
    window.copiedText = [];
    window.failCopy = false;
    Object.defineProperty(navigator.clipboard, 'writeText', {
      value: text => {
        if (window.failCopy) return Promise.reject(new Error('denied'));
        window.copiedText.push(text);
        return Promise.resolve();
      },
    });
  });
  await app.install();
  await app.goto();
  await app.openSession();
  await page.locator('.chat-code-block').first().hover();
  return { app, button: page.locator('.chat-code-copy').first() };
}

test('copy feedback restarts its timer and restores accessible labels', async ({ page }) => {
  const { app, button } = await openCode(page);
  await page.clock.install();
  const title = await button.getAttribute('title');
  const label = await button.getAttribute('aria-label');
  await button.click();
  await expect(button).toHaveAttribute('data-copy-state', 'copied');
  await expect(button).toHaveAttribute('aria-label', 'Copied');
  await page.clock.runFor(1200);
  await button.click();
  await page.clock.runFor(1200);
  await expect(button).toHaveAttribute('data-copy-state', 'copied');
  await page.clock.runFor(900);
  await expect(button).not.toHaveAttribute('data-copy-state');
  await expect(button).toHaveAttribute('title', title);
  await expect(button).toHaveAttribute('aria-label', label);
  expect(await page.evaluate(() => window.copiedText.length)).toBe(2);
  expect(app.pageErrors).toEqual([]);
});

test('copy failure is temporary and removing the button leaves no exception', async ({ page }) => {
  const { app, button } = await openCode(page);
  await page.clock.install();
  await page.evaluate(() => { window.failCopy = true; });
  await button.click();
  await expect(button).toHaveAttribute('data-copy-state', 'failed');
  await expect(button).toHaveAttribute('aria-label', 'Copy failed. Try again.');
  await page.clock.runFor(2100);
  await expect(button).not.toHaveAttribute('data-copy-state');
  await page.evaluate(() => { window.failCopy = false; });
  await button.click();
  await expect(button).toHaveAttribute('data-copy-state', 'copied');
  await button.evaluate(element => element.remove());
  await page.clock.runFor(2100);
  expect(app.pageErrors).toEqual([]);
});
