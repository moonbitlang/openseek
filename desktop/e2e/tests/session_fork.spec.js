import { test, expect } from './support/test.js';
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

async function setup(page, minimal, child = false, events = history) {
  await page.addInitScript(value => localStorage.setItem('openseek.minimal_transcript', String(value)), minimal);
  const app = new DesktopBrowserHarness(page);
  app.liveSessions.push({ id: 'session-other', title: 'Other conversation', updated_at_ms: 2 });
  if (child) app.liveSessions.push({ id: 'session-1-sr-1', title: 'Subtask answer', updated_at_ms: 3 });
  app.sessionEvents = events;
  const sourceSessions = new Set(app.liveSessions.map(session => session.id));
  const replies = new Map();
  const original = app.replyFor.bind(app);
  app.replyFor = request => {
    if (request.method === 'session.fork' || request.method === 'session.edit') {
      const session = 'fork-session';
      const title = request.params.source_title;
      const copied = events.filter(e => request.params.through != null && e.sequence <= request.params.through);
      if (request.method === 'session.edit') {
        copied.push(event((copied.at(-1)?.sequence ?? 0) + 1, 'user', { content: request.params.task }));
      }
      replies.set(session, copied);
      app.liveSessions.push({ id: session, title, updated_at_ms: 10 });
      if (request.method === 'session.edit') {
        app.liveSessions = app.liveSessions.filter(row => row.id !== request.params.session);
        app.notify('session.changed', { change: 'deleted', session: request.params.session, workspace: '/workspace' });
      }
      return { session, title };
    }
    if (request.method === 'session.load') {
      // A newly created chat has no source history, including when the
      // post-send reload races the first render.
      const events = replies.get(request.params.session)
        ?? (sourceSessions.has(request.params.session) ? app.sessionEvents : []);
      return { session: { version: 1, id: request.params.session, events }, watermark: events.at(-1)?.sequence ?? 0, prediction: null };
    }
    return original(request);
  };
  await app.install();
  await app.goto();
  await page.getByText('Rabbita browser fixture', { exact: true }).first().click();
  await expect(page.locator('#transcript')).toContainText('First answer.');
  return app;
}

for (const minimal of [false, true]) {
  test(`${minimal ? 'minimal' : 'detailed'} Fork uses the terminal boundary and opens an idle copy`, async ({ page }) => {
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
  });
}

test('a delayed fork cannot replace a newer missing destination', async ({ page }) => {
  const app = await setup(page, false);
  await page.getByRole('button', { name: 'Other conversation', exact: true }).click();
  await expect(page).toHaveURL(/\/chat\/session\/session-other$/);
  await page.locator('.conversation-row[title="session-1"]').click();
  await expect(page).toHaveURL(/\/chat\/session\/session-1$/);
  const pending = Promise.withResolvers();
  const reply = app.replyFor.bind(app);
  app.replyFor = request => request.method === 'session.fork' ? pending.promise : reply(request);
  await page.getByRole('button', { name: 'Fork from here', exact: true }).first().click();
  await expect.poll(() => app.requests.some(r => r.method === 'session.fork')).toBe(true);
  app.liveSessions = app.liveSessions.filter(row => row.id !== 'session-other');
  app.notify('session.changed', { change: 'deleted', session: 'session-other', workspace: '/workspace' });
  await expect(page.locator('.conversation-row[title="session-other"]')).toHaveCount(0);
  await page.goBack();
  await expect(page).toHaveURL(/\/chat\/session\/session-other$/);
  const unavailable = page.getByText('This destination no longer exists or is no longer attached.');
  await expect(unavailable).toBeVisible();
  pending.resolve(reply(app.requests.find(r => r.method === 'session.fork')));
  const fork = page.locator('.conversation-row[title="fork-session"]');
  await expect(fork).toBeVisible();
  await expect(fork).not.toHaveClass(/active/);
  await expect(unavailable).toBeVisible();
  await expect(page).toHaveURL(/\/chat\/session\/session-other$/);
  expect(app.pageErrors).toEqual([]);
});

{
  const minimal = true;

  test(`${minimal ? 'minimal' : 'detailed'} edit stays inline until Send and preserves the original composer`, async ({ page }) => {
    const app = await setup(page, minimal);
    await page.locator('#task').fill('Keep my original draft');
    const original = page.locator('.conversation-row[title="session-1"]');
    const target = page.locator('.msg.user').filter({ hasText: 'Explore another approach.' });
    await target.getByRole('button', { name: 'Edit message', exact: true }).click();
    const editor = page.locator('.message-editor');
    const input = editor.getByRole('textbox', { name: 'Edit message', exact: true });
    await expect(input).toHaveValue('Explore another approach.');
    await expect(input).toBeFocused();
    await expect(original).toHaveClass(/active/);
    await expect(page.locator('#transcript')).toContainText('Second answer.');
    await expect(page.locator('#transcript')).toContainText('Still working.');
    await expect(page.locator('#task')).toHaveValue('Keep my original draft');
    expect(app.requests.filter(r => r.method === 'session.edit')).toHaveLength(0);
    await input.fill('Try my revised approach.');
    await input.press('End');
    await input.press('Shift+Enter');
    await input.press('x');
    await expect(input).toHaveValue('Try my revised approach.\nx');
    await expect(input).toBeFocused();
    await input.dispatchEvent('keydown', { key: 'Enter', isComposing: true });
    expect(app.requests.filter(r => r.method === 'session.edit')).toHaveLength(0);
    app.rpcDelays.set('session.edit', 500);
    // Use the same Enter-to-send contract as the bottom composer.
    await input.press('Enter');
    await expect(input).toBeDisabled();
    await expect(page.locator('#transcript')).toContainText('Second answer.');
    await expect(page.locator('.conversation-row[title="fork-session"]')).toHaveClass(/active/);
    await expect.poll(() => app.requests.filter(r => r.method === 'session.edit').length).toBe(1);
    expect(app.requests.filter(r => r.method === 'session.edit').map(r => r.params.through)).toEqual([3]);
    const sent = app.requests.find(r => r.method === 'session.edit');
    expect(sent.params.session).toBe('session-1');
    expect(sent.params.task).toBe('Try my revised approach.\nx');
    await expect(original).toHaveCount(0);
    await expect(page.locator('#task')).toHaveValue('');
    expect(app.requests.filter(r => r.method === 'agent.start')).toHaveLength(0);
    expect(app.pageErrors).toEqual([]);
  });


}

test('cancel and Escape restore the original bubble without creating a conversation', async ({ page }) => {
  const app = await setup(page, true);
  await page.locator('#task').fill('My separate draft');
  for (const escape of [false, true]) {
    await page.getByRole('button', { name: 'Edit message', exact: true }).nth(1).click();
    const editor = page.locator('.message-editor');
    await editor.locator('textarea').fill('Unsent changes');
    if (escape) await editor.locator('textarea').press('Escape');
    else await editor.getByRole('button', { name: 'Cancel', exact: true }).click();
    await expect(editor).toHaveCount(0);
    await expect(page.locator('.msg.user').filter({ hasText: 'Explore another approach.' })).toBeVisible();
    await expect(page.locator('#task')).toHaveValue('My separate draft');
  }
  expect(app.requests.filter(r => r.method === 'session.edit')).toHaveLength(0);
  expect(app.pageErrors).toEqual([]);
});

test('expanding an older message keeps the reader in place while later answers stream', async ({ page }) => {
  const events = [...history];
  for (let turn = 0; turn < 12; turn += 1) {
    const sequence = 9 + turn * 3;
    events.push(event(sequence, 'terminal', { kind: 'finished', message: `Later answer ${turn}` }));
    events.push(event(sequence + 1, 'user', { content: `Later question ${turn}` }));
    events.push(event(sequence + 2, 'assistant', { content: `Later response ${turn}` }));
  }
  const app = await setup(page, true, false, events);
  const transcript = page.locator('#transcript');
  await transcript.evaluate(node => { node.scrollTop = 0; });
  const target = page.locator('.msg.user').filter({ hasText: 'Explore another approach.' });
  await expect(target).toBeInViewport();
  const edit = target.getByRole('button', { name: 'Edit message', exact: true });
  // Settle the entry animation and Playwright's scroll-into-view before
  // measuring: click() can otherwise move the reader before editing begins.
  await edit.click({ trial: true });
  const before = await target.boundingBox();
  await edit.click();
  const editor = page.locator('.message-editor');
  await expect(editor.locator('textarea')).toBeFocused();
  await expect.poll(async () => Math.abs((await editor.boundingBox()).y - before.y)).toBeLessThan(4);
  const streamed = event(45, 'terminal', { kind: 'finished', message: 'New answer while editing' });
  app.sessionEvents = [...events, streamed];
  app.notify('session.event', { session: 'session-1', session_root: '/workspace/.openseek', sequence: 45, event: streamed });
  await expect(transcript).toContainText('New answer while editing');
  await expect(editor.locator('textarea')).toBeFocused();
  await expect.poll(async () => Math.abs((await editor.boundingBox()).y - before.y)).toBeLessThan(4);
  expect(app.requests.filter(r => r.method === 'session.edit')).toHaveLength(0);
  expect(app.pageErrors).toEqual([]);
});

test('typing and an external run in the same render keep the draft and disable inline editing', async ({ page }) => {
  // Hold rendering, not message handling: both independent state changes must
  // reach the incremental graph before its next read, without timing sleeps.
  await page.addInitScript(() => {
    const frame = window.requestAnimationFrame.bind(window);
    const queued = [];
    window.__holdEditFrame = false;
    window.requestAnimationFrame = callback => frame(time => {
      if (window.__holdEditFrame) queued.push([callback, time]);
      else callback(time);
    });
    window.__releaseEditFrame = () => new Promise(resolve => frame(() => {
      window.__holdEditFrame = false;
      for (const [callback, time] of queued.splice(0)) callback(time);
      resolve();
    }));
  });
  const app = await setup(page, true);
  await page.getByRole('button', { name: 'Edit message', exact: true }).nth(1).click();
  const editor = page.locator('.message-editor');
  await expect(editor.locator('textarea')).toBeVisible();
  const probes = app.requests.filter(request => request.method === 'git.branch').length;
  await page.evaluate(() => { window.__holdEditFrame = true; });
  await editor.locator('textarea').fill('Keep my simultaneous edit');
  app.notify('agent.started', { session: 'session-1', run_id: 'same-frame-edit', session_root: '/workspace/.openseek', model: 'deepseek-flash', max_steps: 1000 });
  // Started emits a branch probe after installing its running state.
  await expect.poll(() => app.requests.filter(request => request.method === 'git.branch').length).toBeGreaterThan(probes);
  await page.evaluate(() => window.__releaseEditFrame());
  await expect(editor.locator('textarea')).toHaveValue('Keep my simultaneous edit');
  await expect(editor.locator('textarea')).toBeDisabled();
  await expect(editor.getByRole('button', { name: 'Send', exact: true })).toBeDisabled();
  await expect(editor.getByRole('button', { name: 'Cancel', exact: true })).toBeEnabled();
  await editor.getByRole('button', { name: 'Cancel', exact: true }).click();
  await expect(editor).toHaveCount(0);
  expect(app.requests.filter(r => ['agent.cancel', 'session.edit'].includes(r.method))).toHaveLength(0);
  expect(app.pageErrors).toEqual([]);
});
