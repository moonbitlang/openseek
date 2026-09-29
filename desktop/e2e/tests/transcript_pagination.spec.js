import { test, expect } from '@playwright/test';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';

function events(turns) {
  const result = [];
  for (let turn = 1; turn <= turns; turn += 1) {
    result.push({ sequence: result.length + 1, item: { kind: 'user', payload: { content: `Question ${turn}` } } });
    result.push({ sequence: result.length + 1, item: { kind: 'assistant', payload: {
      content: `Answer ${turn}\n\n` + 'A paragraph of historical content.\n\n'.repeat(5),
    } } });
  }
  return result;
}

async function mount(page, turns, minimal = false) {
  await page.addInitScript(minimal => localStorage.setItem('openseek.minimal_transcript', String(minimal)), minimal);
  const app = new DesktopBrowserHarness(page);
  app.sessionEvents = events(turns);
  await app.install();
  await app.goto();
  await page.getByText('Rabbita browser fixture', { exact: true }).first().click();
  await expect(page.locator('#transcript .msg.user .msg-content').last()).toHaveText(`Question ${turns}`);
  return app;
}

for (const minimal of [false, true]) {
  test(`history pages preserve the full rail and locate cross-page turns (${minimal ? 'minimal' : 'detailed'})`, async ({ page }) => {
    const app = await mount(page, 53, minimal);
    const rail = page.locator('.overview-rail');
    const users = page.locator('#transcript .msg.user .msg-content');
    const previous = page.getByRole('button', { name: 'Previous history page' });
    const next = page.getByRole('button', { name: 'Next history page' });
    await expect(rail.locator('.overview-tick')).toHaveCount(53);
    await expect(users).toHaveCount(13);
    await expect(users.first()).toHaveText('Question 41');
    await expect(rail.locator('.in-page')).toHaveCount(13);
    await expect(next).toBeDisabled();
    await previous.focus();
    await page.keyboard.press('Enter');
    await expect(users).toHaveCount(20);
    await expect(users.first()).toHaveText('Question 21');
    await expect(users.last()).toHaveText('Question 40');
    await expect(rail.locator('.in-page')).toHaveCount(20);
    await expect(rail.locator('.overview-tick').nth(20)).toHaveClass(/page-start/);
    await expect(rail.locator('.overview-tick').nth(39)).toHaveClass(/page-end/);
    await expect(next).toBeEnabled();
    await expect(previous).toBeFocused();
    await rail.getByRole('button', { name: 'Question 3', exact: true }).click();
    await expect(users.first()).toHaveText('Question 1');
    await expect(previous).toBeDisabled();
    await expect.poll(() => page.locator('#turn-s5').evaluate(node => {
      const scroller = document.querySelector('#transcript');
      return Math.abs(node.getBoundingClientRect().top - scroller.getBoundingClientRect().top - 10);
    })).toBeLessThan(3);
    await expect(rail.locator('.overview-tick')).toHaveCount(53);
    await page.setViewportSize({ width: 900, height: 800 });
    await expect(next).toBeVisible();
    await next.click();
    await expect(users.first()).toHaveText('Question 21');
    expect(app.pageErrors).toEqual([]);
  });
}

test('new history and streaming keep the older page until jumping to latest', async ({ page }) => {
  const app = await mount(page, 40);
  await page.getByRole('button', { name: 'Previous history page' }).click();
  const users = page.locator('#transcript .msg.user .msg-content');
  await expect(users.first()).toHaveText('Question 1');
  await page.locator('#transcript').evaluate(node => { node.scrollTop = node.scrollHeight; });
  const event = { sequence: 81, item: { kind: 'user', payload: { content: 'Question 41' } } };
  app.sessionEvents.push(event);
  app.notify('session.event', { session: 'session-1', session_root: '/workspace/.openseek', sequence: 81, event });
  app.notify('agent.started', { run_id: 'page-stream', session: 'session-1', session_root: '/workspace/.openseek', model: 'deepseek-v4-pro', max_steps: 1000 });
  app.notify('agent.event', { run_id: 'page-stream', session: 'session-1', event: { event: 'assistant_delta', content: 'Only visible on the latest page' } });
  await expect(page.locator('.overview-tick')).toHaveCount(41);
  await expect(users).toHaveCount(20);
  await expect(users.first()).toHaveText('Question 1');
  await expect(page.locator('#stream')).not.toContainText('Only visible on the latest page');
  await page.getByTitle('Jump to latest', { exact: true }).click();
  await expect(users.first()).toHaveText('Question 41');
  await expect(page.locator('#stream')).toContainText('Only visible on the latest page');
  expect(app.pageErrors).toEqual([]);
});

test('three thousand turns mount one page while keeping all history ticks', async ({ page }) => {
  test.setTimeout(60_000);
  const app = await mount(page, 3000);
  await expect(page.locator('.overview-tick')).toHaveCount(3000);
  await expect(page.locator('#transcript .msg.user .msg-content')).toHaveCount(20);
  await expect(page.locator('#transcript .msg.user .msg-content').first()).toHaveText('Question 2981');
  expect(await page.locator('#stream *').count()).toBeLessThan(5000);
  await page.locator('.overview-tick-button').first().click();
  await expect(page.locator('#transcript .msg.user .msg-content').first()).toHaveText('Question 1');
  await expect(page.locator('#transcript .msg.user .msg-content')).toHaveCount(20);
  expect(await page.locator('#stream *').count()).toBeLessThan(5000);
  expect(app.pageErrors).toEqual([]);
});

test('a pinned reader follows the first turn of a new page', async ({ page }) => {
  const app = await mount(page, 20);
  await expect(page.locator('.overview-page-button')).toHaveCount(0);
  const event = { sequence: 41, item: { kind: 'user', payload: { content: 'Question 21' } } };
  app.sessionEvents.push(event);
  app.notify('session.event', { session: 'session-1', session_root: '/workspace/.openseek', sequence: 41, event });
  await expect(page.locator('#transcript .msg.user .msg-content').first()).toHaveText('Question 21');
  await expect(page.locator('#transcript .msg.user')).toHaveCount(1);
  await expect(page.locator('.overview-tick')).toHaveCount(21);
  await expect(page.locator('.overview-tick.in-page')).toHaveCount(1);
  await expect(page.getByRole('button', { name: 'Next history page' })).toBeDisabled();
  expect(app.pageErrors).toEqual([]);
});
