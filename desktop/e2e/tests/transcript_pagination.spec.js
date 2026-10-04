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

async function mount(page, turns, minimal = false, configure = () => {}) {
  await page.addInitScript(minimal => localStorage.setItem('openseek.minimal_transcript', String(minimal)), minimal);
  const app = new DesktopBrowserHarness(page);
  app.sessionEvents = events(turns);
  configure(app);
  await app.install();
  await app.goto();
  await page.getByText('Rabbita browser fixture', { exact: true }).first().click();
  await expect(page.locator('#transcript .msg.user .msg-content').last()).toHaveText(`Question ${turns}`);
  return app;
}

async function navigationFrames(page, selector, first, shortRail = false) {
  return page.evaluate(async ({ selector, first, shortRail }) => {
    const transcript = document.querySelector('#transcript');
    const rail = document.querySelector('.overview-rail');
    // A short rail forces this adjacent page out of its visible window.
    if (shortRail) {
      rail.style.maxHeight = '60px';
      rail.scrollTop = rail.scrollHeight;
    }
    const marker = document.querySelector('.overview-rail-content');
    const samples = [];
    const sample = () => {
      const loader = document.querySelector('.transcript-page-loading .conversation-load-state');
      return {
        busy: transcript.getAttribute('aria-busy') === 'true',
        first: transcript.querySelector('.msg.user .msg-content')?.textContent,
        hidden: getComputedStyle(document.querySelector('#stream')).visibility === 'hidden',
        loading: Boolean(loader && loader.getBoundingClientRect().height > 0),
        y: new DOMMatrixReadOnly(getComputedStyle(marker, '::before').transform).m42,
        railTop: rail.scrollTop,
      };
    };
    samples.push(sample());
    document.querySelector(selector).click();
    await new Promise(resolve => {
      const deadline = performance.now() + 3000;
      function frame() {
        const current = sample(); samples.push(current);
        if ((!current.busy && current.first === first) || performance.now() > deadline) resolve();
        else requestAnimationFrame(frame);
      }
      requestAnimationFrame(frame);
    });
    return samples;
  }, { selector, first, shortRail });
}

async function firstPage(page) {
  await page.locator('.overview-tick-button').first().click();
  await expect(page.locator('#transcript .msg.user .msg-content').first()).toHaveText('Question 1');
  await expect(page.locator('#transcript')).toHaveAttribute('aria-busy', 'false');
}

async function wheelAtEdge(page, forward = true) {
  const transcript = page.locator('#transcript');
  await transcript.evaluate((node, forward) => { node.scrollTop = forward ? node.scrollHeight : 0; }, forward);
  const rect = await transcript.boundingBox();
  await page.mouse.move(rect.x + rect.width / 2, forward ? rect.y + rect.height - 30 : rect.y + 30);
  await page.mouse.wheel(0, forward ? 100 : -100);
}

async function expectTurnAligned(page, sequence) {
  await expect.poll(() => page.locator(`#turn-s${sequence}`).evaluate(node => {
    return Math.abs(node.getBoundingClientRect().top - document.querySelector('#transcript').getBoundingClientRect().top - 10);
  })).toBeLessThan(3);
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
    await expectTurnAligned(page, 5);
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
  await firstPage(page);
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

for (const minimal of [false, true]) {
  test(`wheel crosses page boundaries with a stable overlapping turn (${minimal ? 'minimal' : 'detailed'})`, async ({ page }) => {
    const app = await mount(page, 53, minimal);
    const transcript = page.locator('#transcript');
    const users = transcript.locator('.msg.user .msg-content');
    await firstPage(page);
    await wheelAtEdge(page);
    await page.waitForTimeout(80);
    await expect(users.first()).toHaveText('Question 1');
    await page.waitForTimeout(300);
    await page.mouse.wheel(0, 100);
    await expect(users.first()).toHaveText('Question 20');
    await expect(users.last()).toHaveText('Question 40');
    await expect(users).toHaveCount(21);
    await expect(page.locator('.overview-tick.in-page')).toHaveCount(20);
    // A short overlapping turn cannot retain a lower screen position without
    // inserting blank padding. Clamp naturally at the new page's top.
    await expect.poll(() => transcript.evaluate(node => node.scrollTop)).toBe(0);
    await expect(page.locator('#turn-s39')).toBeInViewport();
    // Continuing the same gesture cannot skip another page.
    for (let i = 0; i < 5; i += 1) await page.mouse.wheel(0, 20);
    await expect(users.last()).toHaveText('Question 40');
    await wheelAtEdge(page, false);
    await page.waitForTimeout(80);
    await expect(users.last()).toHaveText('Question 40');
    const upper = await page.locator('#turn-s41').evaluate(node => node.getBoundingClientRect().top);
    await page.waitForTimeout(300);
    await page.mouse.wheel(0, -100);
    await expect(users.first()).toHaveText('Question 1');
    await expect(users.last()).toHaveText('Question 21');
    await expect.poll(() => page.locator('#turn-s41').evaluate(node => node.getBoundingClientRect().top).then(top => Math.abs(top - upper))).toBeLessThan(3);
    await expect(page.locator('#turn-s41')).toBeInViewport();
    expect(app.pageErrors).toEqual([]);
  });
}

test('long overlapping turns retain their screen position across a wheel page change', async ({ page }) => {
  const app = await mount(page, 40, false, app => {
    app.sessionEvents[39].item.payload.content += '\n\nLong boundary paragraph.\n\n'.repeat(70);
  });
  await firstPage(page);
  const transcript = page.locator('#transcript');
  await expect(transcript.locator('.msg.user .msg-content').first()).toHaveText('Question 1');
  await wheelAtEdge(page);
  await page.waitForTimeout(300);
  const before = await page.locator('#turn-s39').evaluate(node => node.getBoundingClientRect().top);
  await page.mouse.wheel(0, 100);
  await expect(transcript.locator('.msg.user .msg-content').first()).toHaveText('Question 20');
  await expect.poll(() => page.locator('#turn-s39').evaluate(node => node.getBoundingClientRect().top).then(top => Math.abs(top - before))).toBeLessThan(3);
  expect(app.pageErrors).toEqual([]);
});

test('nested scrolling and zoom gestures do not navigate history pages', async ({ page }) => {
  const app = await mount(page, 40);
  await firstPage(page);
  const transcript = page.locator('#transcript');
  await expect(transcript.locator('.msg.user .msg-content').first()).toHaveText('Question 1');
  await transcript.evaluate(node => { node.scrollTop = node.scrollHeight; });
  await page.locator('#stream').evaluate(node => {
    const nested = document.createElement('div');
    nested.id = 'nested-scroll-fixture';
    nested.style.cssText = 'height:100px;overflow:auto';
    nested.innerHTML = '<div style="height:1000px">Nested content</div>';
    node.append(nested);
  });
  await transcript.evaluate(node => { node.scrollTop = node.scrollHeight; });
  const nested = page.locator('#nested-scroll-fixture');
  await nested.hover();
  await page.mouse.wheel(0, 30);
  await page.waitForTimeout(300);
  await page.mouse.wheel(0, 30);
  await expect.poll(() => nested.evaluate(node => node.scrollTop)).toBeGreaterThan(0);
  await nested.evaluate(node => node.remove());
  for (let i = 0; i < 2; i += 1) {
    await transcript.dispatchEvent('wheel', { deltaY: 100, ctrlKey: true });
    await page.waitForTimeout(300);
  }
  await expect(transcript.locator('.msg.user .msg-content').first()).toHaveText('Question 1');
  expect(app.pageErrors).toEqual([]);
});

test('returning to a wheel-paged conversation restores its overlap and offset', async ({ page }) => {
  const app = await mount(page, 53, false, app => {
    app.liveSessions.push({ id: 'session-2', title: 'Other history', updated_at_ms: 2 });
  });
  await firstPage(page);
  const transcript = page.locator('#transcript');
  const users = transcript.locator('.msg.user .msg-content');
  await expect(users.first()).toHaveText('Question 1');
  await wheelAtEdge(page);
  await page.waitForTimeout(300);
  await page.mouse.wheel(0, 100);
  await expect(users.first()).toHaveText('Question 20');
  await transcript.evaluate(node => { node.scrollTop = 500; });
  await expect.poll(() => transcript.evaluate(node => node.scrollTop)).toBe(500);
  await page.locator('.conversation-row[title="session-2"]').click();
  await expect(users.first()).toHaveText('Question 41');
  await page.locator('.conversation-row[title="session-1"]').click();
  await expect(users.first()).toHaveText('Question 20');
  await expect(users).toHaveCount(21);
  await expect.poll(() => transcript.evaluate(node => node.scrollTop)).toBe(500);
  expect(app.pageErrors).toEqual([]);
});

test('page buttons paint loading and animate the rail before replacing the transcript', async ({ page }) => {
  const app = await mount(page, 200);
  const frames = await navigationFrames(page, '.overview-page-button.previous', 'Question 161', true);
  expect(frames.some(frame => frame.busy && frame.loading && frame.hidden && frame.first === 'Question 181')).toBe(true);
  expect(frames.some(frame => frame.y < 1080 && frame.y > 960)).toBe(true);
  expect(frames.some(frame => frame.railTop < frames[0].railTop)).toBe(true);
  expect(frames.at(-1)).toMatchObject({ busy: false, hidden: false, loading: false, first: 'Question 161' });
  await expect(page.locator('.overview-tick')).toHaveCount(200);
  expect(app.pageErrors).toEqual([]);
});

test('rapid page buttons finish at the latest requested page', async ({ page }) => {
  const app = await mount(page, 100);
  await page.evaluate(() => document.querySelector('.overview-page-button.previous').click());
  await expect(page.locator('#transcript')).toHaveAttribute('aria-busy', 'true');
  await page.evaluate(() => document.querySelector('.overview-page-button.previous').click());
  await expect(page.locator('#transcript')).toHaveAttribute('aria-busy', 'false');
  await expect(page.locator('#transcript .msg.user .msg-content').first()).toHaveText('Question 41');
  await page.waitForTimeout(250);
  await expect(page.locator('#transcript .msg.user .msg-content').first()).toHaveText('Question 41');
  expect(app.pageErrors).toEqual([]);
});

test('page navigation respects reduced motion', async ({ page }) => {
  await page.emulateMedia({ reducedMotion: 'reduce' });
  const app = await mount(page, 60);
  await page.getByRole('button', { name: 'Previous history page' }).click();
  await expect(page.locator('#transcript')).toHaveAttribute('aria-busy', 'false');
  await expect(page.locator('#transcript .msg.user .msg-content').first()).toHaveText('Question 21');
  expect(await page.locator('.overview-rail-content').evaluate(node => getComputedStyle(node, '::before').transitionDuration)).toBe('0s');
  expect(app.pageErrors).toEqual([]);
});

test('cross-page tick clicks paint loading before rendering and land on the selected conversation', async ({ page }) => {
  const app = await mount(page, 60);
  const samples = await navigationFrames(page, '.overview-tick-button[aria-label="Question 7"]', 'Question 1');
  expect(samples.some(frame => frame.busy && frame.loading && frame.first === 'Question 41')).toBe(true);
  expect(samples.at(-1)).toMatchObject({ busy: false, loading: false, first: 'Question 1' });
  await expectTurnAligned(page, 13);
  expect(app.pageErrors).toEqual([]);
});

test('a second tick in a pending page replaces the first destination', async ({ page }) => {
  const app = await mount(page, 60);
  await page.evaluate(() => document.querySelector('.overview-tick-button[aria-label="Question 3"]').click());
  await expect(page.locator('#transcript')).toHaveAttribute('aria-busy', 'true');
  await page.evaluate(() => document.querySelector('.overview-tick-button[aria-label="Question 9"]').click());
  await expect(page.locator('#transcript')).toHaveAttribute('aria-busy', 'false');
  await expectTurnAligned(page, 17);
  expect(app.pageErrors).toEqual([]);
});
