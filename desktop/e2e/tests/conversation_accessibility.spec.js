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
  app.rpcDelays.set('session.load', 600);
  await page.keyboard.press('Enter');
  await expect(first).toHaveClass(/active/);
  await expect(openFirst).toHaveAttribute('aria-current', 'true');
  await expect.poll(() => app.requests.filter(r => r.method === 'session.load' && r.params?.session === 'session-1').length).toBe(1);
  await page.keyboard.press('Tab');
  // A live row's actions sit behind one overflow trigger.
  const actions = first.getByRole('button', { name: 'Conversation actions' });
  await expect(actions).toBeFocused();
  // The load spinner leaving the row must not take the focused trigger with it.
  await expect(first).toHaveClass(/loading/);
  await expect(first).not.toHaveClass(/loading/);
  app.rpcDelays.delete('session.load');
  await expect(actions).toBeFocused();
  await expect(actions).toBeVisible();
  await openSecond.focus();
  await page.keyboard.press('Space');
  await expect(second).toHaveClass(/active/);
  await expect(openSecond).toHaveAttribute('aria-current', 'true');
  await expect(openFirst).toHaveAttribute('aria-current', 'false');
  await expect.poll(() => app.requests.filter(r => r.method === 'session.load' && r.params?.session === 'session-2').length).toBe(1);
  expect(app.requests.filter(r => r.method === 'session.archive' || r.method === 'session.unarchive')).toEqual([]);
  await openFirst.focus();
  await page.keyboard.press('Tab');
  await expect(actions).toBeFocused();
  await page.keyboard.press('Enter');
  const menu = page.getByRole('menu', { name: 'Conversation actions' });
  await expect(menu).toBeFocused();
  await page.keyboard.press('End');
  await expect(menu.getByRole('menuitem', { name: 'Archive' })).toBeFocused();
  await page.keyboard.press('Enter');
  await expect(first).toHaveCount(0);
  await expect(second).toHaveClass(/active/);
  expect(app.requests.filter(r => r.method === 'session.archive')).toHaveLength(1);
  expect(app.requests.filter(r => r.method === 'session.load' && r.params?.session === 'session-1')).toHaveLength(1);
  expect(app.pageErrors).toEqual([]);
});

test('a live row always shows its actions trigger; archived actions stay hover-revealed', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  app.archivedSessions.push({ id: 'session-9', title: 'Archived conversation', updated_at_ms: 1 });
  await app.install();
  await app.goto();
  const first = page.locator('.conversation-row[title="session-1"]');
  const actions = first.getByRole('button', { name: 'Conversation actions' });
  // No hover needed: the trigger is part of the row at rest.
  await page.mouse.move(1439, 899);
  await expect(actions).toBeVisible();
  await actions.click();
  await expect(actions).toHaveAttribute('aria-expanded', 'true');
  await expect(page.getByRole('menu', { name: 'Conversation actions' })).toBeVisible();
  await page.keyboard.press('Escape');
  await expect(page.getByRole('menu')).toHaveCount(0);

  await page.locator('.section-heading', { hasText: 'Archived chats (1)' }).click();
  const archived = page.locator('.conversation-row[title="session-9"]');
  const openArchived = archived.getByRole('button', { name: 'Archived conversation', exact: true });
  // By class: a hidden button is outside the accessibility tree.
  const restore = archived.locator('.row-archive').first();
  // A pointer press must not leave focus on the title: once the pointer
  // leaves the row, the row shows its status slot again rather than the
  // actions a lingering focus would pin open.
  await openArchived.click();
  await expect(archived).toHaveClass(/active/);
  await page.mouse.move(1439, 899);
  await expect(restore).toBeHidden();
  // Hover is still the pointer affordance for the direct actions.
  await archived.hover();
  await expect(restore).toBeVisible();
  expect(app.pageErrors).toEqual([]);
});
