import { test, expect } from './support/test.js';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';

async function openNative(page, pick, prepare) {
  const app = new DesktopBrowserHarness(page);
  await app.install();
  app.onRpc('host.pick_attachment', () => pick());
  if (prepare) app.onRpc('fs.prepare_attachment', () => prepare());
  await app.installNative();
  await page.goto('/index.html');
  await page.getByRole('main').waitFor();
  await page.locator('#task').fill('Keep this draft');
  return app;
}

test('native picker cancellation leaves draft usable (delayed)', async ({ page }) => {
  let cancel;
  const app = await openNative(page, () => new Promise(resolve => { cancel = () => resolve({}); }));
  for (let attempt = 0; attempt < 3; attempt++) {
    await page.getByRole('button', { name: 'Attach files', exact: true }).click();
    await expect.poll(() => app.requests.filter(r => r.method === 'host.pick_attachment').length).toBe(attempt + 1);
    await expect(page.getByRole('button', { name: 'Model', exact: true })).toBeEnabled();
    await expect(page.locator('#send')).toBeEnabled();
    await expect(page.getByText('Reading attachments…', { exact: true })).toBeHidden();
    cancel();
    await expect(page.locator('#task')).toHaveValue('Keep this draft');
  }
  expect(app.requests.some(r => r.method === 'fs.prepare_attachment')).toBe(false);
});

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
});

test('native picker failure shows an error without blocking the draft', async ({ page }) => {
  const app = await openNative(page, () => { throw new Error('picker failed'); });
  await page.getByRole('button', { name: 'Attach files', exact: true }).click();
  await expect(page.getByRole('alert').filter({ hasText: 'picker failed' })).toBeVisible();
  await expect(page.locator('#send')).toBeEnabled();
  await expect(page.getByRole('button', { name: 'Model', exact: true })).toBeEnabled();
  await expect(page.getByText('Reading attachments…', { exact: true })).toBeHidden();
  expect(app.requests.some(r => r.method === 'fs.prepare_attachment')).toBe(false);
});
