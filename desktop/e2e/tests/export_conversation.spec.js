import { test, expect } from '@playwright/test';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';

// Substitute only the native transport. The production dialog, modal focus,
// typed codecs, clipboard effect and update loop run unchanged in Chromium.
class ExportHarness extends DesktopBrowserHarness {
  constructor(page) {
    super(page);
    this.accountSignedIn = true;
    this.userId = '123';
    this.hostShares = [];
    this.pendingSnapshot = null;
    this.downloadReply = { opened: false };
    this.shareReply = {
      status: 'shared',
      url: 'http://shares.example.test/v1/shares/sh_test',
    };
    this.pendingShare = null;
    this.clientUploads = [];
    this.grantRequests = [];
    this.grantStatus = 201;
    this.pendingSignIn = null;
    this.pendingSignOut = null;
    this.signInError = null;
  }

  async openDesktop({ browser = false } = {}) {
    await this.install();
    await this.page.route('**/v2/shares', route => {
      this.clientUploads.push(route.request().url());
      return route.abort('failed');
    });
    await this.page.route('**/v2/shares/upload-grants', async route => {
      this.grantRequests.push({ url: route.request().url(), headers: await route.request().allHeaders(), body: route.request().postDataJSON() });
      await route.fulfill({ status: this.grantStatus, contentType: 'application/json', body: JSON.stringify({ upload_token: 'sug_fixture', expires_in: 600 }) });
    });
    if (!browser) {
    await this.page.exposeFunction('desktopRequest', async request => {
      this.requests.push(request);
      if (request.method === 'app.system_appearance') return { dark: false };
      if (request.method === 'session.export') return this.downloadReply;
      if (request.method === 'account.session') return this.accountSignedIn ? { session: { token: `ts_fixture-${this.userId}`, user: { user_id: this.userId, login: `user-${this.userId}`, avatar_url: '' } } } : {};
      if (request.method === 'auth.disconnect') {
        this.accountSignedIn = false;
        if (this.pendingSignOut) await this.pendingSignOut;
        return { connected: false };
      }
      if (request.method === 'auth.cancel') { this.signInCancelled = true; return { connected: false }; }
      if (request.method === 'auth.connect') {
        if (this.pendingSignIn) await this.pendingSignIn;
        if (this.signInError || this.signInCancelled) throw new Error(this.signInError || 'Sign-in cancelled');
        this.accountSignedIn = true;
        return { connected: false };
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
      window.desktopEvent = (name, payload) => {
        for (const callback of listeners.get(name) || []) callback({ payload });
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
    } else {
      await this.page.addInitScript(() => localStorage.setItem('seekmoon.account.v1', JSON.stringify({ token: 'ts_browser-account', user: { user_id: 'browser-account', login: 'browser-user', avatar_url: '' } })));
    }
    await this.page.goto('/dist/browser/index.html?device=device-a');
    await this.openSession();
  }

  async replyFor(request) {
    if (request.method === 'session.share') {
      this.hostShares.push(request.params);
      if (this.pendingShare) await this.pendingShare;
      return this.shareReply;
    }
    if (request.method === 'session.snapshot') {
      if (this.pendingSnapshot) await this.pendingSnapshot;
      return { html: '<html>Frozen snapshot</html>', json: '{"snapshot":"frozen"}' };
    }
    return super.replyFor(request);
  }

  count(method) { return this.requests.filter(request => request.method === method).length; }

  async openExport() {
    await this.page.getByRole('button', { name: 'Export and import', exact: true }).click();
    await this.page.getByRole('menuitem', { name: 'Export', exact: true }).click();
    const dialog = this.page.getByRole('dialog', { name: 'Export conversation', exact: true });
    await expect(dialog).toBeVisible();
    return dialog;
  }
}

test('export opens choices, downloads locally and restores focus on Escape', async ({ page }) => {
  const app = new ExportHarness(page);
  await app.openDesktop();
  const details = page.getByRole('button', { name: 'Detailed mode', exact: true });
  await expect(details).toHaveAttribute('aria-pressed', 'false');
  await expect(details).not.toHaveClass(/active/);
  await expect(details.locator('xpath=preceding-sibling::*[1]')).toHaveAttribute('title', 'Export and import');
  const dialog = await app.openExport();
  expect(app.count('session.export')).toBe(0);
  expect(app.hostShares.length).toBe(0);
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
  await expect(page.getByRole('button', { name: 'Export and import', exact: true })).toBeFocused();
  expect(app.hostShares.length).toBe(0);
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
  expect(app.hostShares.length).toBe(1);
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
  app.accountSignedIn = false;
  await app.openDesktop();
  const dialog = await app.openExport();
  await dialog.getByRole('button', { name: 'Share', exact: true }).click();
  await dialog.getByRole('button', { name: 'Sign in', exact: true }).click();
  await expect(dialog.getByRole('button', { name: 'Share', exact: true })).toBeEnabled();
  expect(app.count('auth.connect')).toBe(1);
  expect(app.hostShares.length).toBe(0); // sign-in does not silently publish
  app.shareReply = { status: 'failed', message: 'Sharing is unavailable on this server.' };
  await dialog.getByRole('button', { name: 'Share', exact: true }).click();
  await expect(dialog).toContainText('Sharing is unavailable on this server.');
  await expect(dialog.getByRole('button', { name: 'Download', exact: true })).toBeEnabled();
  await expect(dialog.getByRole('button', { name: 'Share', exact: true })).toBeEnabled();
  expect(app.pageErrors).toEqual([]);
});

test('sign-in errors preserve their cause and offer recovery', async ({ page }) => {
  const app = new ExportHarness(page);
  app.accountSignedIn = false;
  app.signInError = 'TLS certificate verification failed';
  await app.openDesktop();
  const dialog = await app.openExport();
  await dialog.getByRole('button', { name: 'Share', exact: true }).click();
  await dialog.getByRole('button', { name: 'Sign in', exact: true }).click();
  await expect(dialog).toContainText('TLS certificate verification failed');
  await expect(dialog).toContainText('You can try signing in again, or download this conversation.');
  await expect(dialog.getByRole('button', { name: 'Download', exact: true })).toBeEnabled();
  app.signInError = null;
  await dialog.getByRole('button', { name: 'Try signing in again', exact: true }).click();
  await expect(dialog.getByRole('button', { name: 'Share', exact: true })).toBeEnabled();
  await expect(dialog).not.toContainText('TLS certificate verification failed');
  expect(app.count('auth.connect')).toBe(2);
  expect(app.hostShares.length).toBe(0); // retrying sign-in does not publish
  expect(app.pageErrors).toEqual([]);
});

test('closing the dialog cancels a sign-in it started', async ({ page }) => {
  const app = new ExportHarness(page);
  app.accountSignedIn = false;
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
  await expect.poll(() => app.hostShares.length).toBe(1);
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


test('browser Work sharing captures the selected host but publishes as the browser account', async ({ page }) => {
  const app = new ExportHarness(page);
  await app.openDesktop({ browser: true });
  const dialog = await app.openExport();
  await dialog.getByRole('button', { name: 'Share', exact: true }).click();
  await expect(dialog.getByRole('textbox', { name: 'Share link' })).toHaveValue(app.shareReply.url);
  expect(app.hostShares).toHaveLength(1);
  expect(app.grantRequests).toHaveLength(1);
  expect(new URL(app.grantRequests[0].url).origin).toBe(new URL(page.url()).origin);
  expect(app.grantRequests[0].headers.authorization).toBe('Bearer ts_browser-account');
  expect(app.grantRequests[0].body).toEqual({ device_id: 'device-a', idempotency_key: app.hostShares[0].idempotency_key });
  expect(app.hostShares[0].authorization).toEqual({ kind: 'upload_grant', upload_token: 'sug_fixture' });
  expect(JSON.stringify(app.hostShares[0])).not.toContain('ts_');
  expect(app.clientUploads).toEqual([]);
  expect(app.count('session.snapshot')).toBe(0);
  expect(app.count('account.session')).toBe(0);
  expect(app.count('auth.connect')).toBe(0);
  expect(app.count('auth.disconnect')).toBe(0);
  const download = page.waitForEvent('download');
  await dialog.getByRole('button', { name: 'Download', exact: true }).click();
  expect((await download).suggestedFilename()).toBe('conversation.html');
  expect(app.count('session.export')).toBe(0);
  expect(app.pageErrors).toEqual([]);
});

test('a host share pending during account change never uses the new account or expires it', async ({ page }) => {
  const app = new ExportHarness(page);
  let finish;
  app.pendingShare = new Promise(resolve => finish = resolve);
  await app.openDesktop();
  const dialog = await app.openExport();
  await dialog.getByRole('button', { name: 'Share', exact: true }).click();
  await expect.poll(() => app.count('session.share')).toBe(1);
  await dialog.getByRole('button', { name: 'Close export dialog' }).click();
  await page.getByRole('button', { name: 'Settings', exact: true }).click();
  const account = page.locator('.settings-group', { has: page.getByRole('heading', { name: 'Account · Remote access', exact: true }) });
  await account.getByRole('button', { name: 'Sign out', exact: true }).click();
  await expect(account.getByRole('button', { name: 'Sign in', exact: true })).toBeEnabled();
  app.userId = '456';
  await account.getByRole('button', { name: 'Sign in', exact: true }).click();
  await expect(account).toContainText('@user-456');
  app.shareReply = { status: 'sign_in_required' };
  finish();
  await expect.poll(() => app.hostShares.length).toBe(1);
  expect(app.hostShares[0].authorization).toEqual({ kind: 'local_account', user_id: '123' });
  await expect(account).toContainText('@user-456');
  expect(app.count('auth.disconnect')).toBe(1);
  expect(app.pageErrors).toEqual([]);
});


test('host share phases stay indeterminate through retry and finish with the link', async ({ page }, testInfo) => {
  const app = new ExportHarness(page);
  let finish;
  app.pendingShare = new Promise(resolve => finish = resolve);
  try {
    await app.openDesktop();
    const dialog = await app.openExport();
    await dialog.getByRole('button', { name: 'Share', exact: true }).click();
    await expect.poll(() => app.hostShares.length).toBe(1);
    await expect(dialog).toContainText('Preparing conversation');
    const generation = app.hostShares[0].generation;
    for (const progress of [['Connecting', { attempt: 1 }], ['Uploading', { attempt: 1 }], ['Waiting', { attempt: 1 }], ['Connecting', { attempt: 2 }], ['Waiting', { attempt: 2 }]]) {
      await page.evaluate(({ generation, progress }) => window.desktopEvent('openseek.session.share_progress', { generation, progress }), { generation, progress });
    }
    await expect(dialog).toContainText('Retrying upload');
    await expect(dialog).toContainText('Waiting for share link');
    await expect(dialog.getByRole('progressbar')).not.toHaveAttribute('aria-valuenow');
    await expect(dialog.locator('.update-progress-fill.indeterminate')).toBeVisible();
    await expect(dialog).not.toContainText('100%');
    expect(app.count('session.share')).toBe(1);
    expect(app.count('session.snapshot')).toBe(0);
    expect(app.clientUploads).toEqual([]);
    await dialog.screenshot({ path: testInfo.outputPath('share-phases.png'), animations: 'disabled' });
    finish();
    await expect(dialog.getByRole('textbox', { name: 'Share link' })).toBeVisible();
    await expect(dialog.getByRole('progressbar')).toHaveCount(0);
    expect(app.pageErrors).toEqual([]);
  } finally { finish(); }
});


for (const status of [401, 403]) {
  test(`remote grant HTTP ${status} ${status === 401 ? 'expires only the account' : 'keeps the account retryable'}`, async ({ page }) => {
    const app = new ExportHarness(page);
    app.grantStatus = status;
    await app.openDesktop({ browser: true });
    const dialog = await app.openExport();
    await dialog.getByRole('button', { name: 'Share', exact: true }).click();
    await expect.poll(() => app.grantRequests.length).toBe(1);
    expect(app.hostShares).toEqual([]);
    if (status === 401) {
      await expect(dialog.getByRole('button', { name: 'Sign in', exact: true })).toBeVisible();
      expect(await page.evaluate(() => localStorage.getItem('seekmoon.account.v1'))).toBeNull();
    } else {
      await expect(dialog).toContainText('Could not prepare sharing (HTTP 403)');
      expect(await page.evaluate(() => localStorage.getItem('seekmoon.account.v1'))).toContain('ts_browser-account');
      await expect(dialog.getByRole('button', { name: 'Share', exact: true })).toBeEnabled();
    }
    expect(app.pageErrors).toEqual([]);
  });
}

test('a rejected upload grant does not sign out the browser account', async ({ page }) => {
  const app = new ExportHarness(page);
  app.shareReply = { status: 'failed', message: 'Sharing failed (HTTP 403): invalid_upload_grant' };
  await app.openDesktop({ browser: true });
  const dialog = await app.openExport();
  await dialog.getByRole('button', { name: 'Share', exact: true }).click();
  await expect(dialog).toContainText('invalid_upload_grant');
  expect(await page.evaluate(() => localStorage.getItem('seekmoon.account.v1'))).toContain('ts_browser-account');
  expect(app.count('auth.disconnect')).toBe(0);
  await expect(dialog.getByRole('button', { name: 'Share', exact: true })).toBeEnabled();
  expect(app.pageErrors).toEqual([]);
});

test('share login stays retryable while rejected account cleanup is pending', async ({ page }) => {
  const app = new ExportHarness(page);
  app.shareReply = { status: 'sign_in_required' };
  let finishSignOut;
  let finishSignIn;
  app.pendingSignOut = new Promise(resolve => { finishSignOut = resolve; });
  app.pendingSignIn = new Promise(resolve => { finishSignIn = resolve; });
  try {
    await app.openDesktop();
    const dialog = await app.openExport();
    await dialog.getByRole('button', { name: 'Share', exact: true }).click();
    const signIn = dialog.getByRole('button', { name: 'Sign in', exact: true });
    await expect(signIn).toBeVisible();
    await expect.poll(() => app.count('auth.disconnect')).toBe(1);
    await signIn.click();
    // Allow the click's scheduled render to settle before checking retained UI.
    await page.evaluate(() => new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve))));
    expect(app.count('auth.connect')).toBe(0);
    await expect(signIn).toBeVisible();
    await expect(dialog).not.toContainText('Complete sign-in in your browser, then click Share.');
    finishSignOut();
    await expect(async () => {
      if (app.count('auth.connect') === 0) await signIn.click();
      expect(app.count('auth.connect')).toBe(1);
    }).toPass({ timeout: 5000 });
    await expect(dialog).toContainText('Complete sign-in in your browser, then click Share.');
    finishSignIn();
    await expect(dialog.getByRole('button', { name: 'Share', exact: true })).toBeEnabled();
    expect(app.hostShares).toHaveLength(1); // sign-in returns to confirmation
    expect(app.pageErrors).toEqual([]);
  } finally {
    finishSignOut();
    finishSignIn();
  }
});

test('one header menu contains export and import, dismisses with Escape, and restores focus', async ({ page }, testInfo) => {
  const app = new ExportHarness(page);
  await app.openDesktop();
  const trigger = page.getByRole('button', { name: 'Export and import', exact: true });
  await expect(trigger).toHaveCount(1);
  await trigger.click();
  const menu = page.getByRole('menu', { name: 'Export and import', exact: true });
  await expect(menu.getByRole('menuitem', { name: 'Export', exact: true })).toBeVisible();
  await expect(menu.getByRole('menuitem', { name: 'Import', exact: true })).toBeVisible();
  await expect(menu.getByRole('separator')).toHaveCount(0);
  const triggerBounds = await trigger.boundingBox();
  const menuBounds = await menu.boundingBox();
  expect(Math.abs(menuBounds.x - triggerBounds.x)).toBeLessThanOrEqual(1);
  expect(menuBounds.x + menuBounds.width).toBeLessThanOrEqual(page.viewportSize().width);
  await page.screenshot({ path: testInfo.outputPath('share-import-menu.png') });
  await page.keyboard.press('Escape');
  await expect(menu).not.toBeVisible();
  await expect(trigger).toBeFocused();
  await trigger.click();
  await menu.getByRole('menuitem', { name: 'Import', exact: true }).click();
  const dialog = page.getByRole('dialog', { name: 'Import conversation', exact: true });
  await expect(dialog).toBeVisible();
  await expect(menu).not.toBeVisible();
  await page.keyboard.press('Escape');
  await expect(dialog).not.toBeVisible();
  await expect(trigger).toBeFocused();
  expect(app.pageErrors).toEqual([]);
});
