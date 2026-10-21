import { test, expect } from '@playwright/test';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';

// Observe real rendered frames so removing rows or shortening the outgoing
// preview cannot pass merely because the final collapsed height is correct.
async function toggleFrames(disclosure) {
  return disclosure.evaluate(async button => {
    const content = document.getElementById(button.getAttribute('aria-controls'));
    const nodes = [...content.querySelectorAll('.conversation-row')];
    const snapshot = () => ({
      height: content.getBoundingClientRect().height,
      rows: content.querySelectorAll('.conversation-row').length,
      connected: nodes.every(node => node.isConnected),
    });
    const frames = [snapshot()];
    // Rabbita commits the click asynchronously. Start observing the new
    // preview after that commit, rather than counting the still-folded DOM
    // in a requestAnimationFrame that happened to precede it.
    const committed = new Promise(resolve => {
      const observer = new MutationObserver(() => {
        observer.disconnect();
        resolve();
      });
      observer.observe(content, { attributes: true, attributeFilter: ['aria-hidden'] });
    });
    button.click();
    const started = performance.now();
    await committed;
    await new Promise(resolve => {
      const sample = () => {
        frames.push(snapshot());
        if (performance.now() - started < 450) requestAnimationFrame(sample);
        else resolve();
      };
      requestAnimationFrame(sample);
    });
    return frames;
  });
}

function expectSmoothFold(frames, count) {
  const height = frames[0].height;
  expect(height).toBeGreaterThan(0);
  expect(frames.at(-1).height).toBe(0);
  expect(frames.some(frame => frame.height > 0 && frame.height < height - 1)).toBe(true);
  expect(frames.every(frame => frame.rows === count && frame.connected)).toBe(true);
}

function expectSmoothOpen(frames, count) {
  const height = frames.at(-1).height;
  expect(frames[0].height).toBe(0);
  expect(height).toBeGreaterThan(0);
  expect(frames.some(frame => frame.height > 0 && frame.height < height - 1)).toBe(true);
  expect(frames.slice(1).every(frame => frame.rows === count)).toBe(true);
}

async function expectInert(content) {
  await expect(content).toHaveAttribute('inert', '');
  await expect(content).toHaveAttribute('aria-hidden', 'true');
  expect(await content.locator('.conversation-open').first().evaluate(button => {
    button.focus();
    return document.activeElement === button;
  })).toBe(false);
}

test('projects retain the outgoing preview during folding and reopen with five chats', async ({ page }, testInfo) => {
  const app = new DesktopBrowserHarness(page);
  app.liveSessions = Array.from({ length: 14 }, (_, i) => ({
    id: `session-${i + 1}`, title: `Animation demo ${i + 1}`, updated_at_ms: 14 - i,
  }));
  await app.install();
  await app.goto();
  const project = page.locator('.sidebar-project').first();
  const disclosure = project.locator('.workspace-disclosure');
  const content = project.locator('.project-conversations');
  await expect(content.locator('.conversation-row')).toHaveCount(5);
  await project.getByRole('button', { name: 'Show more', exact: true }).click();
  await expect(content.locator('.conversation-row')).toHaveCount(12);
  const first = await content.locator('.conversation-row').first().elementHandle();
  await page.screenshot({ path: testInfo.outputPath('project-expanded.png') });
  expectSmoothFold(await toggleFrames(disclosure), 12);
  await expectInert(content);
  await expect(content.locator('.project-show-more')).toHaveCount(1);
  await page.screenshot({ path: testInfo.outputPath('project-folded.png') });
  expectSmoothOpen(await toggleFrames(disclosure), 5);
  await expect(content.locator('.conversation-row')).toHaveCount(5);
  expect(await first.evaluate(node => node === document.querySelector('.project-conversations .conversation-row'))).toBe(true);
  await project.getByRole('button', { name: 'Show more', exact: true }).click();
  await expect(content.locator('.conversation-row')).toHaveCount(12);
  // Folding after revealing the entire list must not reinsert Show more into
  // the outgoing preview either.
  await project.getByRole('button', { name: 'Show more', exact: true }).click();
  await expect(content.locator('.conversation-row')).toHaveCount(14);
  expectSmoothFold(await toggleFrames(disclosure), 14);
  await expect(content.locator('.project-show-more')).toHaveCount(0);
  expect(app.pageErrors).toEqual([]);
});

test('sub-runs stay mounted and inert when folded and keep identity across project folds', async ({ page }, testInfo) => {
  const app = new DesktopBrowserHarness(page);
  app.liveSessions.push({ id: 'session-1-sr-1', title: 'Inspect animation', updated_at_ms: 2 });
  await app.install();
  await app.goto();
  const parent = page.locator('.sidebar-conversation').filter({
    has: page.locator('.conversation-row[title="session-1"]'),
  }).first();
  const disclosure = parent.locator(':scope > .conversation-row .row-twisty');
  const children = parent.locator(':scope > .conversation-children');
  const child = children.locator('.conversation-row');
  await expect(child).toHaveCount(1);
  await expectInert(children);
  const node = await child.elementHandle();
  expectSmoothOpen(await toggleFrames(disclosure), 1);
  await expect(disclosure).toHaveAttribute('aria-expanded', 'true');
  await expect(child.getByRole('button', { name: /Inspect animation/ })).toBeVisible();
  await page.screenshot({ path: testInfo.outputPath('subrun-expanded.png') });
  expectSmoothFold(await toggleFrames(disclosure), 1);
  await expectInert(children);
  expect(await node.evaluate(node => node.isConnected)).toBe(true);
  await disclosure.click();
  const projectDisclosure = page.locator('.workspace-disclosure').first();
  expectSmoothFold(await toggleFrames(projectDisclosure), 2);
  await projectDisclosure.click();
  await expect(disclosure).toHaveAttribute('aria-expanded', 'true');
  expect(await node.evaluate(node => node === document.querySelector('.conversation-row.subrun'))).toBe(true);
  // The selected child keeps its parent open, as before.
  await child.locator('.conversation-open').click();
  await expect(child).toHaveClass(/active/);
  await disclosure.click();
  await expect(disclosure).toHaveAttribute('aria-expanded', 'true');
  expect(app.pageErrors).toEqual([]);
});

test('reduced motion disables project, sub-run and indicator transitions', async ({ page }) => {
  await page.emulateMedia({ reducedMotion: 'reduce' });
  const app = new DesktopBrowserHarness(page);
  app.liveSessions.push({ id: 'session-1-sr-1', title: 'Inspect animation', updated_at_ms: 2 });
  await app.install();
  await app.goto();
  const twisty = page.locator('button.row-twisty');
  await twisty.click();
  await expect(twisty).toHaveAttribute('aria-expanded', 'true');
  const durations = await page.locator('.sidebar-branch, .sidebar-branch-content, .row-twisty .icon')
    .evaluateAll(nodes => nodes.map(node => getComputedStyle(node).transitionDuration));
  expect(durations.every(duration => duration === '0s')).toBe(true);
  await page.locator('.workspace-disclosure').click();
  await expect(page.locator('.workspace-disclosure')).toHaveAttribute('aria-expanded', 'false');
  expect(await page.locator('.project-conversations').evaluate(node => node.getBoundingClientRect().height)).toBe(0);
  expect(app.pageErrors).toEqual([]);
});
