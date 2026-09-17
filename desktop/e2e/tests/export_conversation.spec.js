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
    };
    this.pendingShare = null;
    this.pendingSignIn = null;
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
        if (this.pendingSignIn) await this.pendingSignIn;
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
  const details = page.getByRole('button', { name: 'Detailed mode', exact: true });
  await expect(details).toHaveAttribute('aria-pressed', 'true');
  await expect(details).toHaveClass(/active/);
  await expect(details.locator('xpath=following-sibling::*[1]')).toHaveAttribute('title', 'Export conversation');
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

test('share publishes once and shows a selectable link with a copy button', async ({ page, context }) => {
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
  await dialog.getByRole('button', { name: 'Copy share link' }).click();
  const copied = dialog.getByRole('button', { name: 'Share link copied', exact: true });
  await expect(copied).toBeVisible();
  await expect(copied).toHaveClass(/export-copy-success/);
  expect(await page.evaluate(() => navigator.clipboard.readText())).toBe(app.shareReply.url);
  await expect(dialog.getByRole('button', { name: 'Share', exact: true })).toBeDisabled();
  expect(app.count('session.share')).toBe(1);
  expect(app.count('session.export')).toBe(0);
  // Downloading afterward keeps the completed link in the same dialog.
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

test('sign-in errors preserve their cause and offer recovery', async ({ page }) => {
  const app = new ExportHarness(page);
  app.shareReply = { status: 'sign_in_required' };
  app.signInError = 'TLS certificate verification failed';
  await app.openDesktop();
  const dialog = await app.openExport();
  await dialog.getByRole('button', { name: 'Share', exact: true }).click();
  await dialog.getByRole('button', { name: 'Sign in', exact: true }).click();
  await expect(dialog).toContainText('Could not sign in: TLS certificate verification failed');
  await expect(dialog).toContainText('You can try signing in again, or download this conversation.');
  await expect(dialog.getByRole('button', { name: 'Download', exact: true })).toBeEnabled();
  app.signInError = null;
  await dialog.getByRole('button', { name: 'Try signing in again', exact: true }).click();
  await expect(dialog.getByRole('button', { name: 'Share', exact: true })).toBeEnabled();
  await expect(dialog).not.toContainText('TLS certificate verification failed');
  expect(app.count('auth.connect')).toBe(2);
  expect(app.count('session.share')).toBe(1); // retrying sign-in does not publish
  expect(app.pageErrors).toEqual([]);
});

test('closing the dialog cancels a sign-in it started', async ({ page }) => {
  const app = new ExportHarness(page);
  app.shareReply = { status: 'sign_in_required' };
  let finish;
  app.pendingSignIn = new Promise(resolve => { finish = resolve; });
  await app.openDesktop();
  const dialog = await app.openExport();
  await dialog.getByRole('button', { name: 'Share', exact: true }).click();
  await dialog.getByRole('button', { name: 'Sign in', exact: true }).click();
  await expect.poll(() => app.count('auth.connect')).toBe(1);
  await page.keyboard.press('Escape');
  await expect(dialog).not.toBeVisible();
  await expect.poll(() => app.count('auth.cancel')).toBe(1);
  finish();
  await app.openExport();
  await expect(dialog.getByRole('button', { name: 'Share', exact: true })).toBeEnabled();
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
