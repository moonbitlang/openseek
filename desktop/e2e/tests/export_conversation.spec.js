import { test, expect } from '@playwright/test';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';

// Substitute only the native transport. The production dialog, modal focus,
// typed codecs, clipboard effect and update loop run unchanged in Chromium.
class ExportHarness extends DesktopBrowserHarness {
  constructor(page) {
    super(page);
    this.downloadReply = { opened: false };
    this.shareReply = {
      status: 'shared',
      url: 'http://shares.example.test/v1/shares/sh_test',
      expires_at: '2026-09-22T00:00:00Z',
    };
    this.pendingShare = null;
    this.signInError = null;
  }

  async openDesktop() {
    await this.install();
    await this.page.exposeFunction('desktopRequest', async request => {
      this.requests.push(request);
      if (request.method === 'session.export') return this.downloadReply;
      if (request.method === 'session.share') {
        if (this.pendingShare) await this.pendingShare;
        return this.shareReply;
      }
      if (request.method === 'auth.connect') {
        if (this.signInError) throw new Error(this.signInError);
        return { connected: true };
      }
      return this.replyFor(request);
    });
    await this.page.addInitScript(() => {
      const listeners = new Map();
      const events = {
        on(name, callback) {
          const callbacks = listeners.get(name) || new Set();
          listeners.set(name, callbacks);
          callbacks.add(callback);
          return () => callbacks.delete(callback);
        },
      };
      window.__MoonBit__ = {
        getTitlebarArea: async () => null,
        app: events,
        events,
        openseek: new Proxy({}, {
          get: (_, method) => async params => {
            if (method === 'host.connect') {
              for (const callback of listeners.get('openseek.agent.connected') || []) {
                callback({ payload: { stage: 'serving' } });
              }
            }
            return window.desktopRequest({ method, params });
          },
        }),
      };
    });
    await this.page.goto('/dist/browser/index.html');
    await this.openSession();
  }

  count(method) { return this.requests.filter(request => request.method === method).length; }

  async openExport() {
    await this.page.getByRole('button', { name: 'Export conversation', exact: true }).click();
    const dialog = this.page.getByRole('dialog', { name: 'Export conversation', exact: true });
    await expect(dialog).toBeVisible();
    return dialog;
  }
}

test('export opens choices, downloads locally and restores focus on Escape', async ({ page }) => {
  const app = new ExportHarness(page);
  await app.openDesktop();
  const dialog = await app.openExport();
  expect(app.count('session.export')).toBe(0);
  expect(app.count('session.share')).toBe(0);
  await expect(dialog).toContainText('Anyone with the link can view it for 7 days');
  await dialog.getByRole('button', { name: 'Download', exact: true }).click();
  await expect.poll(() => app.count('session.export')).toBe(1);
  await expect(dialog.getByRole('button', { name: 'Download', exact: true })).toBeEnabled();
  await expect(dialog).toBeVisible(); // cancelling the native save is not an error
  app.downloadReply = { path: '/exports/conversation.html', opened: false };
  await dialog.getByRole('button', { name: 'Download', exact: true }).click();
  await expect(dialog).toContainText("couldn't open it automatically");
  expect(app.requests.find(request => request.method === 'session.export').params).toMatchObject({
    session: 'session-1', workspace: '/workspace', archived: false,
  });
  await page.keyboard.press('Escape');
  await expect(dialog).not.toBeVisible();
  await expect(page.getByRole('button', { name: 'Export conversation', exact: true })).toBeFocused();
  expect(app.count('session.share')).toBe(0);
  expect(app.pageErrors).toEqual([]);
});

test('share publishes once and shows a selectable link with a copy button on its right', async ({ page, context }) => {
  await context.grantPermissions(['clipboard-read', 'clipboard-write']);
  const app = new ExportHarness(page);
  let finish;
  app.pendingShare = new Promise(resolve => { finish = resolve; });
  await app.openDesktop();
  const dialog = await app.openExport();
  await dialog.getByRole('button', { name: 'Share', exact: true }).click();
  await expect(dialog.getByRole('button', { name: 'Sharing…' })).toBeDisabled();
  await expect(dialog.getByRole('button', { name: 'Download' })).toBeDisabled();
  finish();
  const link = dialog.getByRole('textbox', { name: 'Share link' });
  await expect(link).toHaveValue(app.shareReply.url);
  const copy = dialog.getByRole('button', { name: 'Copy share link' });
  const linkBox = await link.boundingBox();
  const copyBox = await copy.boundingBox();
  expect(copyBox.x).toBeGreaterThanOrEqual(linkBox.x + linkBox.width);
  expect(Math.abs(copyBox.y - linkBox.y)).toBeLessThan(1);
  expect(Math.abs(copyBox.height - linkBox.height)).toBeLessThan(1);
  const copyIcon = await copy.locator('svg').boundingBox();
  expect(Math.abs(copyIcon.x + copyIcon.width / 2 - copyBox.x - copyBox.width / 2)).toBeLessThan(1);
  expect(Math.abs(copyIcon.y + copyIcon.height / 2 - copyBox.y - copyBox.height / 2)).toBeLessThan(1);
  await copy.click();
  const copied = dialog.getByRole('button', { name: 'Share link copied', exact: true });
  await expect(copied).toBeVisible();
  await expect(copied).toHaveCSS('color', 'rgb(31, 138, 91)');
  await expect(dialog).not.toContainText('Link copied.');
  await expect(dialog).not.toContainText('Expires:');
  await expect(dialog).not.toContainText(app.shareReply.expires_at);
  expect(await page.evaluate(() => navigator.clipboard.readText())).toBe(app.shareReply.url);
  await expect(dialog.getByRole('button', { name: 'Share', exact: true })).toBeDisabled();
  for (const width of [1440, 390]) {
    await page.setViewportSize({ width, height: 900 });
    const inputBox = await link.boundingBox();
    const buttonBox = await copied.boundingBox();
    const shareBox = await dialog.getByRole('button', { name: 'Share', exact: true }).boundingBox();
    const downloadBox = await dialog.getByRole('button', { name: 'Download', exact: true }).boundingBox();
    const iconBox = await copied.locator('svg').boundingBox();
    expect(Math.abs(inputBox.y - buttonBox.y)).toBeLessThan(1);
    expect(Math.abs(inputBox.height - buttonBox.height)).toBeLessThan(1);
    expect(Math.abs(shareBox.y - downloadBox.y)).toBeLessThan(1);
    expect(Math.abs(shareBox.height - downloadBox.height)).toBeLessThan(1);
    expect(Math.abs(shareBox.height - inputBox.height)).toBeLessThan(1);
    expect(Math.abs(shareBox.x + shareBox.width - buttonBox.x - buttonBox.width)).toBeLessThan(1);
    expect(Math.abs(iconBox.x + iconBox.width / 2 - buttonBox.x - buttonBox.width / 2)).toBeLessThan(1);
    expect(Math.abs(iconBox.y + iconBox.height / 2 - buttonBox.y - buttonBox.height / 2)).toBeLessThan(1);
    if (width === 390) expect(buttonBox.height).toBeGreaterThanOrEqual(44);
  }
  await page.setViewportSize({ width: 1440, height: 900 });
  expect(app.count('session.share')).toBe(1);
  expect(app.count('session.export')).toBe(0);
  await page.screenshot({ path: 'test-results/export-conversation-shared.png' });
  await dialog.getByRole('button', { name: 'Download', exact: true }).click();
  await expect(dialog.getByRole('button', { name: 'Download', exact: true })).toBeEnabled();
  await expect(link).toHaveValue(app.shareReply.url);
  await expect(dialog.getByRole('button', { name: 'Share', exact: true })).toBeDisabled();
  expect(app.pageErrors).toEqual([]);
});

test('share offers sign-in and keeps upload failures actionable', async ({ page }) => {
  const app = new ExportHarness(page);
  app.shareReply = { status: 'sign_in_required' };
  await app.openDesktop();
  const dialog = await app.openExport();
  await dialog.getByRole('button', { name: 'Share', exact: true }).click();
  await dialog.getByRole('button', { name: 'Sign in', exact: true }).click();
  await expect(dialog.getByRole('button', { name: 'Share', exact: true })).toBeEnabled();
  expect(app.count('auth.connect')).toBe(1);
  expect(app.count('session.share')).toBe(1); // sign-in does not silently publish
  app.shareReply = { status: 'failed', message: 'Sharing is unavailable on this server.' };
  await dialog.getByRole('button', { name: 'Share', exact: true }).click();
  await expect(dialog).toContainText('Sharing is unavailable on this server.');
  await expect(dialog.getByRole('button', { name: 'Download', exact: true })).toBeEnabled();
  await expect(dialog.getByRole('button', { name: 'Share', exact: true })).toBeEnabled();
  expect(app.pageErrors).toEqual([]);
});

test('sign-in errors explain recovery without exposing internal operation names', async ({ page }) => {
  const app = new ExportHarness(page);
  app.shareReply = { status: 'sign_in_required' };
  app.signInError = 'op ext:openseek/auth.connect failed';
  await app.openDesktop();
  const dialog = await app.openExport();
  await dialog.getByRole('button', { name: 'Share', exact: true }).click();
  await dialog.getByRole('button', { name: 'Sign in', exact: true }).click();
  await expect(dialog).toContainText('Sign-in could not be completed.');
  await expect(dialog).toContainText('You can still download this conversation.');
  await expect(dialog).not.toContainText('auth.connect');
  await expect(dialog).not.toContainText('op ext:');
  await expect(dialog.getByRole('button', { name: 'Download', exact: true })).toBeEnabled();
  app.signInError = null;
  await dialog.getByRole('button', { name: 'Try signing in again', exact: true }).click();
  await expect(dialog.getByRole('button', { name: 'Share', exact: true })).toBeEnabled();
  await expect(dialog).not.toContainText('Sign-in could not be completed.');
  expect(app.count('auth.connect')).toBe(2);
  expect(app.count('session.share')).toBe(1); // retrying sign-in does not publish
  expect(app.pageErrors).toEqual([]);
});

test('closing an upload ignores its late reply and narrow dialogs fit the viewport', async ({ page }) => {
  const app = new ExportHarness(page);
  let finish;
  app.pendingShare = new Promise(resolve => { finish = resolve; });
  await app.openDesktop();
  const dialog = await app.openExport();
  await dialog.getByRole('button', { name: 'Share', exact: true }).click();
  await expect.poll(() => app.count('session.share')).toBe(1);
  await dialog.getByRole('button', { name: 'Close export dialog' }).click();
  await expect(dialog).not.toBeVisible();
  await app.openExport();
  finish();
  await expect(dialog.getByRole('button', { name: 'Share', exact: true })).toBeEnabled();
  await expect(dialog.getByRole('textbox', { name: 'Share link' })).toHaveCount(0);
  await page.setViewportSize({ width: 390, height: 700 });
  const box = await dialog.boundingBox();
  expect(box.x).toBeGreaterThanOrEqual(0);
  expect(box.x + box.width).toBeLessThanOrEqual(390);
  expect(app.pageErrors).toEqual([]);
});
