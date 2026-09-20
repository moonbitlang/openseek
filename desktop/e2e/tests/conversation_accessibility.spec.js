import { test, expect } from '@playwright/test';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';

test('conversation titles support keyboard activation and independent row actions', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  app.liveSessions.push({ id: 'session-2', title: 'Second conversation', updated_at_ms: 2 });
  await app.install();
  await app.goto();
  const first = page.locator('.conversation-row[title="session-1"]');
  const second = page.locator('.conversation-row[title="session-2"]');
  const openFirst = first.getByRole('button', { name: 'Rabbita browser fixture', exact: true });
  const openSecond = second.getByRole('button', { name: 'Second conversation', exact: true });
  await expect(openFirst).toBeVisible();
  // Reach the title using actual Tab navigation rather than focusing it directly.
  await page.getByRole('button', { name: 'Hide sidebar', exact: true }).focus();
  for (let i = 0; i < 30 && !(await openFirst.evaluate(el => el === document.activeElement)); i++) {
    await page.keyboard.press('Tab');
  }
  await expect(openFirst).toBeFocused();
  await page.keyboard.press('Enter');
  await expect(first).toHaveClass(/active/);
  await expect(openFirst).toHaveAttribute('aria-current', 'true');
  await expect.poll(() => app.requests.filter(r => r.method === 'session.load' && r.params?.session === 'session-1').length).toBe(1);
  await page.keyboard.press('Tab');
  const archive = first.getByRole('button', { name: /Archive/ });
  await expect(archive).toBeFocused();
  await expect(archive).toBeVisible();
  await openSecond.focus();
  await page.keyboard.press('Space');
  await expect(second).toHaveClass(/active/);
  await expect(openSecond).toHaveAttribute('aria-current', 'true');
  await expect(openFirst).toHaveAttribute('aria-current', 'false');
  await expect.poll(() => app.requests.filter(r => r.method === 'session.load' && r.params?.session === 'session-2').length).toBe(1);
  expect(app.requests.filter(r => r.method === 'session.archive' || r.method === 'session.unarchive')).toEqual([]);
  await openFirst.focus();
  await page.keyboard.press('Tab');
  await expect(archive).toBeFocused();
  await page.keyboard.press('Enter');
  await expect(first).toHaveCount(0);
  await expect(second).toHaveClass(/active/);
  expect(app.requests.filter(r => r.method === 'session.archive')).toHaveLength(1);
  expect(app.requests.filter(r => r.method === 'session.load' && r.params?.session === 'session-1')).toHaveLength(1);
  expect(app.pageErrors).toEqual([]);
});

test('pointer selection keeps the status slot instead of revealing row actions', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  app.liveSessions.push({ id: 'session-2', title: 'Second conversation', updated_at_ms: 2 });
  await app.install();
  await app.goto();
  const first = page.locator('.conversation-row[title="session-1"]');
  const openFirst = first.getByRole('button', { name: 'Rabbita browser fixture', exact: true });
  const archive = first.locator('.row-archive');
  await expect(archive).toHaveCount(1);
  // A pointer press must not leave focus on the title: once the pointer
  // leaves the row, the row shows its status slot again rather than the
  // actions a lingering focus would pin open.
  await openFirst.click();
  await expect(first).toHaveClass(/active/);
  await expect.poll(() => app.requests.filter(r => r.method === 'session.load' && r.params?.session === 'session-1').length).toBe(1);
  await page.mouse.move(1439, 899);
  await expect(archive).toBeHidden();
  // Hover is still the pointer affordance for the actions.
  await first.hover();
  await expect(archive).toBeVisible();
});
