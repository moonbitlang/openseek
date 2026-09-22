import { test, expect } from '@playwright/test';
import { readFileSync } from 'node:fs';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';

const bytes = readFileSync(new URL('../../../deepseek/client/testdata/two-colors.png', import.meta.url));
const png = bytes.toString('base64');
const url = `data:image/png;base64,${png}`;
const image = { name: 'two-colors.png', mimeType: 'image/png', buffer: bytes };

async function open(page) {
  const app = new DesktopBrowserHarness(page);
  await app.install();
  await app.goto();
  await app.openSession();
  await expect(page.getByRole('button', { name: 'Attach images', exact: true })).toBeVisible();
  return app;
}

async function select(page) {
  const chooser = page.waitForEvent('filechooser');
  await page.getByRole('button', { name: 'Attach images', exact: true }).click();
  await (await chooser).setFiles(image);
  await expect(page.locator('.composer-image img')).toHaveAttribute('src', url);
}

async function paste(page) {
  await page.locator('#task').evaluate((target, png) => {
    const transfer = new DataTransfer();
    transfer.items.add(new File([Uint8Array.from(atob(png), c => c.charCodeAt(0))], 'pasted.png', { type: 'image/png' }));
    target.dispatchEvent(new ClipboardEvent('paste', { clipboardData: transfer, bubbles: true, cancelable: true }));
  }, png);
  await expect(page.locator('.composer-image img')).toHaveAttribute('src', url);
}

function started(app) {
  const request = app.requests.filter(r => r.method === 'agent.start').at(-1);
  app.notify('agent.started', {
    run_id: 'run-e2e', session: 'session-1', session_root: '/workspace/.openseek',
    submission_id: request.params.submission_id, model: 'deepseek-v4-pro', max_steps: 1000,
  });
}

test('image-only OpenSeek input is sent and renders from durable history after reload', async ({ page }) => {
  const app = await open(page);
  await select(page);
  await page.locator('#send').click();
  await expect.poll(() => app.requests.find(r => r.method === 'agent.start')?.params.images).toEqual([url]);
  const request = app.requests.find(r => r.method === 'agent.start');
  expect(request.params.task).toBe('');
  await expect(page.locator('.composer-image')).toHaveCount(0);
  const event = { sequence: 18, item: { kind: 'user', payload: {
    content: [{ type: 'text', text: '' }, { type: 'image', media_type: 'image/png', data: png }],
    submission_id: request.params.submission_id,
  } } };
  app.sessionEvents.push(event);
  app.notify('session.event', { session: 'session-1', session_root: '/workspace/.openseek', sequence: 18, event });
  await expect(page.locator('.user-image')).toHaveAttribute('src', url);
  await expect.poll(() => page.locator('.user-image').evaluate(img => img.naturalWidth)).toBeGreaterThan(0);
  await page.reload();
  await app.openSession();
  await expect(page.locator('.user-image')).toHaveAttribute('src', url);
  expect(app.pageErrors).toEqual([]);
});

test('OpenSeek restores images after rejection and includes pasted images in steering', async ({ page }) => {
  const app = await open(page);
  app.rpcErrors.set('agent.start', 'Image start rejected');
  await select(page);
  await page.locator('#task').fill('Inspect both colors');
  await page.locator('#send').click();
  await expect(page.getByText('Image start rejected', { exact: false }).first()).toBeVisible();
  await expect(page.locator('.composer-image')).toHaveCount(1);
  await expect(page.locator('#task')).toHaveValue('Inspect both colors');
  app.rpcErrors.delete('agent.start');
  await page.locator('#send').click();
  await expect.poll(() => app.requests.filter(r => r.method === 'agent.start').length).toBe(2);
  started(app);
  await expect(page.locator('.composer-image')).toHaveCount(0);
  await paste(page);
  app.rpcErrors.set('agent.steer', 'Steer refused');
  await page.locator('#send').click();
  await expect.poll(() => app.requests.find(r => r.method === 'agent.steer')?.params.images).toEqual([url]);
  await expect(page.locator('.composer-image')).toHaveCount(1);
  expect(app.pageErrors).toEqual([]);
});

test('queued OpenSeek images survive editing', async ({ page }) => {
  const app = await open(page);
  app.hostSettings.followup_behavior = 'queue';
  await page.reload();
  await app.openSession();
  await page.locator('#task').fill('Begin');
  await page.locator('#send').click();
  await expect.poll(() => app.requests.some(r => r.method === 'agent.start')).toBe(true);
  started(app);
  await select(page);
  await page.locator('#send').click();
  await expect.poll(() => app.requests.find(r => r.method === 'agent.queue')?.params.images).toEqual([url]);
  await expect(page.locator('.composer-image')).toHaveCount(0);
  await page.locator('.queued-input-action[aria-label="Edit"]').click();
  await expect(page.locator('.composer-image img')).toHaveAttribute('src', url);
  await page.locator('#task').fill('Compare these');
  await page.locator('#send').click();
  await expect.poll(() => app.requests.find(r => r.method === 'agent.queue' && r.params.action === 'edit')?.params.images).toEqual([url]);
  expect(app.pageErrors).toEqual([]);
});

test('durable user and tool content render images between their text parts', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  const part = { type: 'image', media_type: 'image/png', data: png };
  const content = [{ type: 'text', text: 'Show the browser fixture before picture' }, part, { type: 'text', text: 'After picture' }];
  app.sessionEvents = [
    { sequence: 1, item: { kind: 'user', payload: { content } } },
    { sequence: 2, item: { kind: 'assistant', payload: { content: '', tool_calls: [
      { id: 'mixed', name: 'read_image', arguments: '{}' },
      { id: 'picture', name: 'read_image', arguments: '{}' },
    ] } } },
    { sequence: 3, item: { kind: 'tool_result', payload: {
      tool_call_id: 'mixed', tool_name: 'read_image', content, is_error: false,
    } } },
    { sequence: 4, item: { kind: 'tool_result', payload: {
      tool_call_id: 'picture', tool_name: 'read_image', content: [part], is_error: false,
    } } },
  ];
  await app.install();
  await app.goto();
  await app.openSession();
  const user = page.locator('.user-bubble');
  await expect(user.locator('.user-image')).toHaveAttribute('src', url);
  expect(await user.locator('.msg-content, .user-images').evaluateAll(nodes =>
    nodes.map(node => node.querySelector('img') ? 'image' : node.textContent),
  )).toEqual(['Show the browser fixture before picture', 'image', 'After picture']);
  const results = page.locator('#transcript details.tool-result');
  await expect(results).toHaveCount(2);
  for (const result of await results.all()) {
    await result.locator('.tool-result-summary').click();
    await expect(result.locator('.user-image')).toBeVisible();
    await expect.poll(() => result.locator('.user-image').evaluate(img => img.naturalWidth)).toBeGreaterThan(0);
  }
  const sections = await results.first().locator(':scope > .tool-call-section, :scope > .user-images').evaluateAll(nodes =>
    nodes.map(node => node.querySelector('img') ? 'image' : node.textContent),
  );
  expect(sections).toEqual([expect.stringContaining('Show the browser fixture before picture'), 'image', expect.stringContaining('After picture')]);
  expect(app.pageErrors).toEqual([]);
});
