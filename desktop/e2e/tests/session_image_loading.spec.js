import { test, expect } from '@playwright/test';
import { readFileSync } from 'node:fs';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';

const png = readFileSync(new URL('../../../deepseek/client/testdata/two-colors.png', import.meta.url)).toString('base64');
const dataURL = `data:image/png;base64,${png}`;
const reference = sequence => ({ record: '/workspace/.openseek/sessions/demo/record.jsonl', offset: String(sequence * 100), length: 100, sequence, part: 1 });
const picture = sequence => ({ type: 'image_ref', image: reference(sequence) });
function fixture(page) {
  const app = new DesktopBrowserHarness(page);
  const reply = app.replyFor.bind(app);
  app.replyFor = request => request.method === 'session.image' ? { data_url: dataURL } : reply(request);
  return app;
}
const reads = app => app.requests.filter(r => r.method === 'session.image');

for (const minimal of [false, true]) {
  test(`durable images load only in the viewport (${minimal ? 'minimal' : 'detailed'})`, async ({ page }, testInfo) => {
    await page.addInitScript(minimal => localStorage.setItem('openseek.minimal_transcript', String(minimal)), minimal);
    const app = fixture(page);
    app.sessionEvents = Array.from({ length: 30 }, (_, index) => ({ sequence: index + 1, item: { kind: 'user', payload: {
      content: [{ type: 'text', text: `Image ${index + 1}` }, picture(index + 1)],
    } } }));
    await app.install(); await app.goto(); await page.getByText("Rabbita browser fixture", { exact: true }).first().click();
    const images = page.locator('.user-image');
    await expect(images).toHaveCount(30);
    await expect(images.last()).toHaveAttribute('src', dataURL);
    await expect.poll(() => page.locator('#transcript').evaluate(node => node.scrollHeight - node.scrollTop - node.clientHeight)).toBeLessThan(5);
    await page.screenshot({ path: testInfo.outputPath('session-image-loading.png') });
    expect(reads(app).some(r => r.params.sequence === 15)).toBe(false);
    expect(reads(app).length).toBeLessThan(15);
    await images.nth(14).scrollIntoViewIfNeeded();
    await expect(images.nth(14)).toHaveAttribute('src', dataURL);
    expect(reads(app).filter(r => r.params.sequence === 15)).toHaveLength(1);
    await images.last().scrollIntoViewIfNeeded();
    await images.nth(14).scrollIntoViewIfNeeded();
    await expect(images.nth(14)).toHaveAttribute('src', dataURL);
    expect(reads(app).filter(r => r.params.sequence === 15)).toHaveLength(1);
    expect(app.pageErrors).toEqual([]);
  });
}

test('collapsed tool images wait until expanded and failed reads settle', async ({ page }) => {
  const app = fixture(page);
  app.sessionEvents = [
    { sequence: 1, item: { kind: 'user', payload: { content: 'Inspect the image' } } },
    { sequence: 2, item: { kind: 'assistant', payload: { content: '', tool_calls: [{ id: 'picture', name: 'read_image', arguments: '{}' }] } } },
    { sequence: 3, item: { kind: 'tool_result', payload: { tool_call_id: 'picture', tool_name: 'read_image', content: [picture(3)], is_error: false } } },
  ];
  await app.install(); await app.goto(); await page.getByText("Rabbita browser fixture", { exact: true }).first().click();
  const result = page.locator('details.tool-result');
  await expect(result).toBeVisible();
  expect(reads(app)).toHaveLength(0);
  app.rpcErrors.set('session.image', 'Image no longer available');
  await result.locator('summary').click();
  await expect(result.locator('.user-image')).toHaveClass(/unavailable/);
  await expect(result.locator('.user-image')).toHaveAttribute('title', /Image no longer available/);
  expect(reads(app)).toHaveLength(1);
  await result.locator('summary').click();
  await result.locator('summary').click();
  await expect(result.locator('.user-image')).toHaveClass(/unavailable/);
  expect(reads(app)).toHaveLength(1);
  expect(app.pageErrors).toEqual([]);
});

test('new durable image commits use the same deferred reader', async ({ page }) => {
  const app = fixture(page);
  await app.install(); await app.goto(); await page.getByText("Rabbita browser fixture", { exact: true }).first().click();
  await expect(page.locator('.transcript .msg-content').filter({ hasText: 'Show the browser fixture' })).toBeVisible();
  expect(reads(app)).toHaveLength(0);
  const event = { sequence: 18, item: { kind: 'user', payload: { content: [picture(18)] } } };
  app.notify('session.event', { session: 'session-1', session_root: '/workspace/.openseek', sequence: 18, event });
  await expect(page.locator('.user-image')).toHaveAttribute('src', dataURL);
  expect(reads(app)).toHaveLength(1);
  expect(reads(app)[0].params).toEqual(reference(18));
  expect(app.pageErrors).toEqual([]);
});
