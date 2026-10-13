import { test, expect } from '@playwright/test';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';

const event = (sequence, kind, payload) => ({ sequence, item: { kind, payload } });
const history = [
  event(1, 'user', { content: 'Explore the first approach.' }),
  event(2, 'assistant', { content: 'First answer.' }),
  event(3, 'terminal', { kind: 'finished', message: 'First answer.' }),
  event(4, 'user', { content: 'Explore another approach.' }),
  event(5, 'assistant', { content: 'Let me investigate.' }),
  event(6, 'terminal', { kind: 'finished', message: 'Second answer.' }),
  event(7, 'user', { content: 'Continue working.' }),
  event(8, 'assistant', { content: 'Still working.' }),
];

async function setup(page, minimal, child = false) {
  await page.addInitScript(value => localStorage.setItem('openseek.minimal_transcript', String(value)), minimal);
  const app = new DesktopBrowserHarness(page);
  app.liveSessions.push({ id: 'session-other', title: 'Other conversation', updated_at_ms: 2 });
  if (child) app.liveSessions.push({ id: 'session-1-sr-1', title: 'Subtask answer', updated_at_ms: 3 });
  app.sessionEvents = history;
  const replies = new Map();
  const original = app.replyFor.bind(app);
  app.replyFor = request => {
    if (request.method === 'session.fork') {
      const session = 'fork-session';
      const title = request.params.source_title;
      replies.set(session, history.filter(e => e.sequence <= request.params.through));
      app.liveSessions.push({ id: session, title, updated_at_ms: 10 });
      return { session, title };
    }
    if (request.method === 'session.load' && replies.has(request.params.session)) {
      const events = replies.get(request.params.session);
      return { session: { version: 1, id: request.params.session, events }, watermark: events.at(-1).sequence, prediction: null };
    }
    return original(request);
  };
  await app.install();
  await app.goto();
  await page.getByText('Rabbita browser fixture', { exact: true }).first().click();
  await expect(page.getByRole('button', { name: 'Fork from here', exact: true })).toHaveCount(2);
  return app;
}

for (const minimal of [false, true]) {
  test(`${minimal ? 'minimal' : 'detailed'} Fork uses the terminal boundary and opens an idle copy`, async ({ page }, testInfo) => {
    const app = await setup(page, minimal);
    const buttons = page.getByRole('button', { name: 'Fork from here', exact: true });
    expect(await buttons.first().textContent()).toBe('');
    app.rpcDelays.set('session.fork', 500);
    await buttons.first().focus();
    await page.keyboard.press('Enter');
    await expect(buttons.first()).toBeDisabled();
    await expect(buttons.last()).toBeDisabled();
    await expect(page.locator('.message-fork-spinner')).toHaveCount(1);
    await expect(page.locator('.conversation-row[title="fork-session"]')).toHaveClass(/active/);
    await expect(page.getByRole('button', { name: 'Fork from here', exact: true })).toHaveCount(1);
    await expect(page.locator('#transcript')).not.toContainText('Second answer.');
    await expect(page.locator('#transcript')).not.toContainText('Still working.');
    await expect(page.getByRole('textbox', { name: 'Ask SeekMoon to inspect, edit, or explain this workspace.', exact: true })).toBeFocused();
    expect(app.requests.filter(r => r.method === 'session.fork').map(r => r.params.through)).toEqual([3]);
    expect(app.requests.find(r => r.method === 'session.fork').params.source_title).toBe('Rabbita browser fixture');
    await expect(page.getByRole('button', { name: 'Rabbita browser fixture', exact: true })).toHaveCount(2);
    expect(app.requests.filter(r => r.method === 'agent.start')).toEqual([]);
    expect(app.pageErrors).toEqual([]);
    await page.screenshot({ path: testInfo.outputPath(`fork-${minimal ? 'minimal' : 'detailed'}.png`) });
  });
}

for (const minimal of [false, true]) {
  test(`${minimal ? 'minimal' : 'detailed'} subrun answers do not offer Fork`, async ({ page }) => {
    const app = await setup(page, minimal, true);
    await page.locator('.conversation-row[title="session-1"] .row-twisty').click();
    const child = page.locator('.conversation-row[title="session-1-sr-1"]');
    await child.getByRole('button', { name: 'sr-1 · Subtask answer', exact: true }).click();
    await expect(child).toHaveClass(/active/);
    await expect(page.locator('#transcript')).toContainText('First answer.');
    await expect(page.getByRole('button', { name: 'Fork from here', exact: true })).toHaveCount(0);
    expect(app.requests.filter(r => r.method === 'session.fork')).toHaveLength(0);
    expect(app.pageErrors).toEqual([]);
  });

  // Rendering differs by layout; completion handling is shared.
  const failed = minimal;
  test(`${minimal ? 'minimal' : 'detailed'} Fork disables other conversations until ${failed ? 'failure' : 'success'}`, async ({ page }) => {
    const app = await setup(page, minimal);
    app.rpcDelays.set('session.fork', 2500);
    if (failed) app.rpcErrors.set('session.fork', 'Fork fixture unavailable');
    const buttons = page.getByRole('button', { name: 'Fork from here', exact: true });
    await buttons.first().click();
    await expect(page.locator('.message-fork-spinner')).toHaveCount(1);
    await page.getByRole('button', { name: 'Other conversation', exact: true }).click();
    await expect(page.locator('.conversation-row[title="session-other"]')).toHaveClass(/active/);
    await expect(buttons).toHaveCount(2);
    await expect(buttons.first()).toBeDisabled();
    await expect(buttons.last()).toBeDisabled();
    await expect(buttons.first()).toHaveAttribute('title', 'Forking, please wait');
    await expect(page.locator('.message-fork-spinner')).toHaveCount(0);
    expect(app.requests.filter(r => r.method === 'session.fork')).toHaveLength(1);
    if (failed) {
      await expect(page.getByText('Fork fixture unavailable', { exact: false })).toBeVisible();
    } else {
      await expect(page.locator('.conversation-row[title="fork-session"]')).toBeVisible();
      await expect(page.locator('.conversation-row[title="fork-session"]')).not.toHaveClass(/active/);
    }
    await expect(buttons.first()).toBeEnabled();
    await expect(buttons.last()).toBeEnabled();
    await expect(page.locator('.conversation-row[title="session-other"]')).toHaveClass(/active/);
    if (failed) {
      app.rpcErrors.delete('session.fork');
      app.rpcDelays.delete('session.fork');
      await buttons.first().click();
      await expect(page.locator('.conversation-row[title="fork-session"]')).toHaveClass(/active/);
      expect(app.requests.filter(r => r.method === 'session.fork')).toHaveLength(2);
    }
    expect(app.pageErrors).toEqual([]);
  });
}

test('a streamed answer gains Fork only when its terminal is committed', async ({ page }) => {
  const app = await setup(page, true);
  const committed = event(9, 'terminal', { kind: 'finished', message: 'Still working.' });
  app.sessionEvents = [...history, committed];
  app.notify('session.event', { session: 'session-1', session_root: '/workspace/.openseek', sequence: 9, event: committed });
  await expect(page.getByRole('button', { name: 'Fork from here', exact: true })).toHaveCount(3);
  await page.getByRole('button', { name: 'Fork from here', exact: true }).last().click();
  await expect.poll(() => app.requests.filter(r => r.method === 'session.fork').map(r => r.params.through)).toEqual([9]);
  expect(app.pageErrors).toEqual([]);
});
