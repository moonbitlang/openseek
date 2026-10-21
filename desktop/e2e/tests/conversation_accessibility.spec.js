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
  await expect(menu.getByRole('menuitem', { name: 'Delete…' })).toBeFocused();
  await page.keyboard.press('ArrowUp');
  await expect(menu.getByRole('menuitem', { name: 'Archive' })).toBeFocused();
  await page.keyboard.press('Enter');
  // The archived row stays mounted, but the folded section clips it and
  // excludes its controls from keyboard focus.
  await expect(first).not.toBeInViewport();
  expect(await first.locator('.conversation-open').evaluate(button => {
    button.focus();
    return document.activeElement === button;
  })).toBe(false);
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
  // By class: the hidden trigger is outside the accessibility tree.
  const actions = first.locator('.row-menu-button');
  await expect(actions).toHaveCount(1);
  // A pointer press must not leave focus on the title: once the pointer
  // leaves the row, the row shows its status slot again rather than the
  // actions a lingering focus would pin open.
  await openFirst.click();
  await expect(first).toHaveClass(/active/);
  await expect.poll(() => app.requests.filter(r => r.method === 'session.load' && r.params?.session === 'session-1').length).toBe(1);
  await page.mouse.move(1439, 899);
  await expect(actions).toBeHidden();
  // Hover is still the pointer affordance for the actions.
  await first.hover();
  await expect(actions).toBeVisible();
  // An open menu keeps its trigger in place after the pointer leaves the row.
  await actions.click();
  await expect(page.getByRole('menu', { name: 'Conversation actions' })).toBeVisible();
  await page.mouse.move(1439, 899);
  await expect(actions).toBeVisible();
  await expect(actions).toHaveAttribute('aria-expanded', 'true');
  await page.keyboard.press('Escape');
  await expect(page.getByRole('menu')).toHaveCount(0);
  expect(app.pageErrors).toEqual([]);
});

test('opening another conversation saves a title being edited', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  app.liveSessions.push({ id: 'session-2', title: 'Second conversation', updated_at_ms: 2 });
  await app.install();
  await app.goto();
  const first = page.locator('.conversation-row[title="session-1"]');
  const second = page.locator('.conversation-row[title="session-2"]');
  await first.hover();
  await first.locator('.row-menu-button').click();
  await page.getByRole('menuitem', { name: 'Rename…' }).click();
  const input = first.getByRole('textbox', { name: 'Rename conversation' });
  await expect(input).toBeFocused();
  await input.fill('Saved by opening another');
  // A title's pointer press keeps focus where it was, so the field never sees
  // focus leave; opening the other conversation still commits the edit.
  await second.getByRole('button', { name: 'Second conversation', exact: true }).click();
  await expect(second).toHaveClass(/active/);
  await expect(input).toHaveCount(0);
  await expect(
    first.getByRole('button', { name: 'Saved by opening another', exact: true }),
  ).toBeVisible();
  expect(app.requests.filter(r => r.method === 'session.rename').map(r => r.params.title))
    .toEqual(['Saved by opening another']);
  // The renamed row is left at rest: focus was not handed back to it, so its
  // actions are not pinned open.
  await page.mouse.move(1439, 899);
  await expect(first.locator('.row-menu-button')).toBeHidden();
  expect(app.pageErrors).toEqual([]);
});

test('a background reorder does not end or save a title being edited', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  app.liveSessions[0].updated_at_ms = 5;
  app.liveSessions.push({ id: 'session-2', title: 'Second conversation', updated_at_ms: 6 });
  app.liveSessions.push({ id: 'session-3', title: 'Third conversation', updated_at_ms: 7 });
  await app.install();
  await app.goto();
  const order = () => page.locator('.conversation-row').evaluateAll(
    rows => rows.map(row => row.getAttribute('title')));
  await expect.poll(order).toEqual(['session-3', 'session-2', 'session-1']);
  const row = page.locator('.conversation-row[title="session-3"]');
  await row.hover();
  await row.locator('.row-menu-button').click();
  await page.getByRole('menuitem', { name: 'Rename…' }).click();
  const input = row.getByRole('textbox', { name: 'Rename conversation' });
  await expect(input).toBeFocused();
  await input.pressSequentially('Half');
  // The edited row drops to the end: the list re-inserts its node, which
  // blurs the field without the user leaving it.
  app.liveSessions.find(session => session.id === 'session-3').updated_at_ms = 1;
  app.notify('session.changed', { change: 'created', session: 'session-3', workspace: '/workspace' });
  await expect.poll(order).toEqual(['session-2', 'session-1', 'session-3']);
  await expect(input).toBeFocused();
  await input.pressSequentially(' typed');
  await expect(input).toHaveValue('Half typed');
  expect(app.requests.filter(r => r.method === 'session.rename')).toEqual([]);
  await input.press('Enter');
  await expect.poll(() => app.requests.filter(r => r.method === 'session.rename')
    .map(r => r.params.title)).toEqual(['Half typed']);
  expect(app.pageErrors).toEqual([]);
});

test('a failed rename is reported even after its project is folded', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  await app.install();
  await app.goto();
  const row = page.locator('.conversation-row[title="session-1"]');
  await row.hover();
  await row.locator('.row-menu-button').click();
  await page.getByRole('menuitem', { name: 'Rename…' }).click();
  const input = row.getByRole('textbox', { name: 'Rename conversation' });
  await expect(input).toBeFocused();
  await input.fill('Will not save');
  app.rpcErrors.set('session.rename', 'fixture rename unavailable');
  app.rpcDelays.set('session.rename', 400);
  // Folding the project moves focus away, which starts the save; the row is
  // hidden and inert by the time the host refuses it.
  const disclosure = page.locator('.workspace-row[title="/workspace"] .workspace-disclosure');
  await disclosure.click();
  await expect(disclosure).toHaveAttribute('aria-expanded', 'false');
  await expect(page.locator('.notification')).toContainText(
    'Rename failed: fixture rename unavailable',
  );
  await disclosure.click();
  await expect(row.getByRole('button', { name: 'Rabbita browser fixture', exact: true })).toBeVisible();
  await expect(input).toHaveCount(0);
  expect(app.pageErrors).toEqual([]);
});

// Inspect the actual height transition at its midpoint without sampling
// rendered frames or depending on the disclosure's duration.
async function expectRetainedFold(disclosure) {
  const result = await disclosure.evaluate(async button => {
    const content = document.getElementById(button.getAttribute('aria-controls'));
    await Promise.all(content.getAnimations().map(animation => animation.finished));
    const nodes = [...content.querySelectorAll('.conversation-row')];
    const height = content.getBoundingClientRect().height;
    const committed = new Promise(resolve => {
      const observer = new MutationObserver(() => { observer.disconnect(); resolve(); });
      observer.observe(content, { attributes: true, attributeFilter: ['aria-hidden'] });
    });
    button.click();
    await committed;
    const animation = content.getAnimations().find(animation => animation.transitionProperty === 'height');
    if (!animation) throw new Error('Folding must animate the content height');
    animation.pause();
    animation.currentTime = animation.effect.getTiming().duration / 2;
    const midpoint = content.getBoundingClientRect().height;
    animation.finish();
    const title = content.querySelector('.conversation-open');
    title.focus();
    return {
      height, midpoint, foldedHeight: content.getBoundingClientRect().height,
      retained: nodes.every(node => content.contains(node)),
      hidden: content.getAttribute('aria-hidden'), inert: content.inert,
      focusable: document.activeElement === title,
    };
  });
  expect(result.midpoint).toBeGreaterThan(0);
  expect(result.midpoint).toBeLessThan(result.height);
  expect(result).toMatchObject({ foldedHeight: 0, retained: true, hidden: 'true', inert: true, focusable: false });
}

test('folding a project retains its expanded preview and reopens with five chats', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  app.liveSessions = Array.from({ length: 12 }, (_, i) => ({
    id: `session-${i + 1}`, title: `Conversation ${i + 1}`, updated_at_ms: 12 - i,
  }));
  await app.install();
  await app.goto();
  const project = page.locator('.sidebar-project').first();
  const disclosure = project.locator('.workspace-disclosure');
  const rows = project.locator('.conversation-row');
  await project.getByRole('button', { name: 'Show more', exact: true }).click();
  await expect(rows).toHaveCount(12);
  const first = await rows.first().elementHandle();
  await expectRetainedFold(disclosure);
  await expect(rows).toHaveCount(12);
  await disclosure.click();
  await expect(rows).toHaveCount(5);
  await expect(rows.first().getByRole('button', { name: 'Conversation 1', exact: true })).toBeVisible();
  expect(await first.evaluate(node => node === document.querySelector('.project-conversations .conversation-row'))).toBe(true);
  expect(app.pageErrors).toEqual([]);
});

test('sub-runs retain their DOM across their own and project folds', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  app.liveSessions.push({ id: 'session-1-sr-1', title: 'Inspect animation', updated_at_ms: 2 });
  await app.install();
  await app.goto();
  const disclosure = page.locator('button.row-twisty');
  const child = page.locator('.conversation-row.subrun');
  await expect(child).toHaveCount(1);
  const node = await child.elementHandle();
  await disclosure.click();
  await expect(child.getByRole('button', { name: /Inspect animation/ })).toBeVisible();
  await expectRetainedFold(disclosure);
  await disclosure.click();
  await expect(disclosure).toHaveAttribute('aria-expanded', 'true');
  const projectDisclosure = page.locator('.workspace-disclosure').first();
  await expectRetainedFold(projectDisclosure);
  await projectDisclosure.click();
  await expect(child.getByRole('button', { name: /Inspect animation/ })).toBeVisible();
  expect(await node.evaluate(node => node === document.querySelector('.conversation-row.subrun'))).toBe(true);
  expect(app.pageErrors).toEqual([]);
});
