import { test, expect } from '@playwright/test';
import { VizBrowserHarness } from './support/viz_browser_harness.js';

// Exercise the mounted session viewer rather than serializing Rabbita's
// virtual DOM into a test-only string representation.
test('session viewer mounts log cards and interactive filters in Chromium', async ({ page }) => {
  const viewer = new VizBrowserHarness(page);
  await viewer.install();
  await viewer.goto();

  await expect(page.locator('.session-root-name')).toHaveText('/workspace');
  await expect(page.locator('.session-item')).toContainText('Inspect the session viewer');
  await viewer.openSession();

  await expect(page.locator('.header-strip')).toContainText('session header loaded');
  await expect(page.locator('.card.user')).toContainText('Inspect the session viewer');
  await expect(page.locator('.tool-call.tool-call-escalated')).toContainText('shell');
  await expect(page.locator('.card.tool.error.escalated')).toContainText('fixture failure');
  await expect(page.locator('.error-count')).toContainText('1 tool error');
  await expect(page.locator('.escalated-count')).toContainText('1 escalated tool call');

  await page.getByRole('button', { name: 'Model view' }).click();
  await expect(page.getByRole('button', { name: 'Model view' })).toHaveClass(/active/);
  await page.getByRole('button', { name: 'Original' }).click();
  await expect(page.locator('.session-view')).toHaveClass(/show-original/);

  await page.getByRole('button', { name: 'Errors only' }).click();
  await expect(page.locator('.session-view')).toHaveClass(/errors-only/);
  await expect(page.getByRole('button', { name: 'Errors only: on' })).toBeVisible();
  expect(viewer.pageErrors).toEqual([]);
});

test('a dropped session file replaces the served selection without another fetch', async ({ page }) => {
  const viewer = new VizBrowserHarness(page);
  await viewer.install();
  await viewer.goto();
  const requestsBeforeDrop = viewer.apiRequests.length;

  const dataTransfer = await page.evaluateHandle(events => {
    const transfer = new DataTransfer();
    transfer.items.add(new File([events], 'dropped-session.jsonl', {
      type: 'application/x-ndjson',
    }));
    return transfer;
  }, viewer.events);
  await page.locator('.app').dispatchEvent('drop', { dataTransfer });

  await expect(page.locator('.header-id')).toHaveText('viz-1');
  await expect(page.locator('.header-meta')).toContainText(
    'dropped file: dropped-session.jsonl',
  );
  expect(viewer.apiRequests).toHaveLength(requestsBeforeDrop);
  expect(viewer.pageErrors).toEqual([]);
  await dataTransfer.dispose();
});

test('URL hash restores the session, raw view, and sequence scroll position', async ({ page }) => {
  await page.addInitScript(() => {
    window.__scrollTargets = [];
    const scrollIntoView = Element.prototype.scrollIntoView;
    Element.prototype.scrollIntoView = function (options) {
      window.__scrollTargets.push({ id: this.id, className: this.className });
      return scrollIntoView.call(this, options);
    };
  });
  const viewer = new VizBrowserHarness(page);
  await viewer.install();
  await viewer.goto('#s=viz-1&v=raw&seq=2');

  await expect(page.locator('.header-id')).toHaveText('viz-1');
  await expect(page.getByRole('button', { name: 'Raw log' })).toHaveClass(/active/);
  await expect.poll(() => page.evaluate(() => window.__scrollTargets))
    .toContainEqual(expect.objectContaining({ id: 'seq-2' }));
  await expect.poll(() => page.evaluate(() => {
    const params = new URLSearchParams(location.hash.slice(1));
    return {
      session: params.get('s'),
      view: params.get('v'),
      sequence: params.get('seq'),
    };
  })).toEqual({ session: 'viz-1', view: 'raw', sequence: '2' });
  expect(viewer.pageErrors).toEqual([]);
});

test('keyboard shortcuts navigate failures and unfold the nearest card', async ({ page }) => {
  await page.addInitScript(() => {
    window.__scrollTargets = [];
    const scrollIntoView = Element.prototype.scrollIntoView;
    Element.prototype.scrollIntoView = function (options) {
      window.__scrollTargets.push({ id: this.id, className: this.className });
      return scrollIntoView.call(this, options);
    };
  });
  const viewer = new VizBrowserHarness(page);
  await viewer.install();
  await viewer.goto();
  await viewer.openSession();

  await page.keyboard.press('n');
  await expect.poll(() => page.evaluate(() => window.__scrollTargets.length))
    .toBeGreaterThan(0);
  await expect.poll(() => page.evaluate(() =>
    window.__scrollTargets.at(-1)?.className || ''))
    .toContain('error');
  const jumpsAfterNext = await page.evaluate(() => window.__scrollTargets.length);
  await page.keyboard.press('p');
  await expect.poll(() => page.evaluate(() => window.__scrollTargets.length))
    .toBeGreaterThan(jumpsAfterNext);

  const openBefore = await page.locator('details[open]').count();
  await page.keyboard.press('u');
  await expect.poll(() => page.locator('details[open]').count())
    .toBeGreaterThan(openBefore);
  expect(viewer.pageErrors).toEqual([]);
});

test('standalone export reads embedded data and auto-opens in raw mode', async ({ page }) => {
  const viewer = new VizBrowserHarness(page);
  await viewer.install({ standalone: true });
  await viewer.goto();

  await expect(page.locator('.header-id')).toHaveText('viz-1');
  await expect(page.getByRole('button', { name: 'Raw log' })).toHaveClass(/active/);
  await expect(page.locator('.card.user')).toContainText('Inspect the session viewer');
  expect(viewer.apiRequests).toEqual([]);
  expect(viewer.pageErrors).toEqual([]);
});

test('Light, Dark, and System theme controls apply their browser palettes', async ({ page }) => {
  await page.emulateMedia({ colorScheme: 'dark' });
  const viewer = new VizBrowserHarness(page);
  await viewer.install();
  await viewer.goto();

  await page.getByRole('button', { name: 'Light' }).click();
  await expect(page.locator('html')).toHaveAttribute('data-theme', 'light');
  const lightBackground = await page.evaluate(() =>
    getComputedStyle(document.documentElement).getPropertyValue('--bg'));

  await page.getByRole('button', { name: 'Dark' }).click();
  await expect(page.locator('html')).toHaveAttribute('data-theme', 'dark');
  const darkBackground = await page.evaluate(() =>
    getComputedStyle(document.documentElement).getPropertyValue('--bg'));
  expect(darkBackground).not.toBe(lightBackground);

  await page.getByRole('button', { name: 'System' }).click();
  await expect(page.locator('html')).toHaveAttribute('data-theme', 'system');
  await expect(page.getByRole('button', { name: 'System' })).toHaveClass(/active/);
  const systemBackground = await page.evaluate(() =>
    getComputedStyle(document.documentElement).getPropertyValue('--bg'));
  expect(systemBackground).toBe(darkBackground);
  expect(viewer.pageErrors).toEqual([]);
});
