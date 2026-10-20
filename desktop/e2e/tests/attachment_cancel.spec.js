import { test, expect } from '@playwright/test';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';

async function openNative(page, pick, prepare) {
  const app = new DesktopBrowserHarness(page);
  await app.install();
  await page.exposeFunction('attachmentDesktopRequest', request => {
    app.requests.push(request);
    if (request.method === 'app.system_appearance') return { dark: false };
    if (request.method === 'host.pick_attachment') return pick();
    if (request.method === 'fs.prepare_attachment' && prepare) return prepare();
    return app.replyFor(request);
  });
  await page.addInitScript(() => {
    const listeners = new Map();
    const events = { on(name, callback) {
      const callbacks = listeners.get(name) || new Set();
      listeners.set(name, callbacks);
      callbacks.add(callback);
      return () => callbacks.delete(callback);
    } };
    window.__MoonBit__ = {
      getTitlebarArea: async () => null,
      app: events, events,
      openseek: new Proxy({}, { get: (_, method) => async params => {
        if (method === 'host.connect') {
          for (const callback of listeners.get('openseek.agent.connected') || []) {
            callback({ payload: { protocol: 1 } });
          }
        }
        return window.attachmentDesktopRequest({ method, params });
      } }),
    };
  });
  await page.goto('/index.html');
  await page.getByRole('main').waitFor();
  await page.locator('#task').fill('Keep this draft');
  return app;
}

{
  const delayed = true;
  test(`native picker cancellation leaves draft usable (${delayed ? 'delayed' : 'immediate'})`, async ({ page }) => {
    let cancel;
    const app = await openNative(page, () => delayed
      ? new Promise(resolve => { cancel = () => resolve({}); }) : {});
    for (let attempt = 0; attempt < 3; attempt++) {
      await page.getByRole('button', { name: 'Attach files', exact: true }).click();
      await expect.poll(() => app.requests.filter(r => r.method === 'host.pick_attachment').length).toBe(attempt + 1);
      await expect(page.getByRole('button', { name: 'Model', exact: true })).toBeEnabled();
      await expect(page.locator('#send')).toBeEnabled();
      await expect(page.getByText('Reading attachments…', { exact: true })).toBeHidden();
      if (delayed) cancel();
      await expect(page.locator('#task')).toHaveValue('Keep this draft');
    }
    expect(app.requests.some(r => r.method === 'fs.prepare_attachment')).toBe(false);
    expect(app.pageErrors).toEqual([]);
  });
}

test('native selection blocks send only while preparing the selected attachment', async ({ page }) => {
  let finish;
  const app = await openNative(page, () => ({ path: '/workspace/report.pdf' }),
    () => new Promise(resolve => { finish = () => resolve({ kind: 'reference', path: 'report.pdf' }); }));
  await page.getByRole('button', { name: 'Attach files', exact: true }).click();
  await expect.poll(() => app.requests.filter(r => r.method === 'fs.prepare_attachment').length).toBe(1);
  await expect(page.locator('#send')).toBeDisabled();
  await expect(page.getByRole('button', { name: 'Model', exact: true })).toBeDisabled();
  finish();
  await expect(page.locator('.mention-chip').filter({ hasText: 'report.pdf' })).toBeVisible();
  await expect(page.locator('#send')).toBeEnabled();
  await expect(page.getByRole('button', { name: 'Model', exact: true })).toBeEnabled();
  expect(app.pageErrors).toEqual([]);
});

test('native picker failure shows an error without blocking the draft', async ({ page }) => {
  const app = await openNative(page, () => { throw new Error('picker failed'); });
  await page.getByRole('button', { name: 'Attach files', exact: true }).click();
  await expect(page.getByRole('alert').filter({ hasText: 'picker failed' })).toBeVisible();
  await expect(page.locator('#send')).toBeEnabled();
  await expect(page.getByRole('button', { name: 'Model', exact: true })).toBeEnabled();
  await expect(page.getByText('Reading attachments…', { exact: true })).toBeHidden();
  expect(app.requests.some(r => r.method === 'fs.prepare_attachment')).toBe(false);
  expect(app.pageErrors).toEqual([]);
});
