import { test, expect } from '@playwright/test';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';

// The `auth.status` shape (docs/remote-protocol.md): absent fields, never
// null, stand for a signed-out user and device.
const relay = 'https://relay.test';
const signedOut = { connected: false, server_url: relay };
const signedIn = {
  connected: true,
  server_url: relay,
  user: { login: 'octocat', avatar_url: '' },
  device: { id: 'd_1', name: 'Test Mac', url: `${relay}/console/?device=d_1` },
};

// Replace only Proton's transport, as close_shortcut.spec.js does. The relay
// sign-in is scripted: `auth.connect` stays pending until the test settles
// it, the way the real host waits for the browser round-trip.
async function installDesktop(page) {
  const app = new DesktopBrowserHarness(page);
  await app.install();
  const auth = { status: signedOut, finishConnect: null };
  await page.exposeFunction('desktopRequest', request => {
    app.requests.push(request);
    switch (request.method) {
      case 'app.system_appearance':
        return { dark: false };
      case 'auth.status':
        return auth.status;
      case 'auth.connect':
        return new Promise(resolve => {
          auth.finishConnect = () => {
            auth.status = signedIn;
            resolve(auth.status);
          };
        });
      case 'auth.disconnect':
        auth.status = signedOut;
        return auth.status;
      default:
        return app.replyFor(request);
    }
  });
  await page.addInitScript(() => {
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
            window.desktopEvent('openseek.agent.connected', { stage: 'serving' });
          }
          return window.desktopRequest({ method, params });
        },
      }),
    };
  });
  await page.goto('/dist/browser/index.html');
  await page.getByRole('main').waitFor();
  return auth;
}

test('Disconnect stays clickable after the Connect button it replaces', async ({ page }) => {
  const auth = await installDesktop(page);
  await page.getByRole('button', { name: 'Settings', exact: true }).click();
  const section = page.locator('.settings-group', { hasText: 'Remote access' });

  const connect = section.getByRole('button', { name: 'Connect with GitHub' });
  await expect(connect).toBeEnabled();
  await connect.click();

  // The sign-in is waiting on the browser: the same slot is now a disabled
  // in-progress button.
  const waiting = section.getByRole('button', { name: 'Waiting for the browser…' });
  await expect(waiting).toBeDisabled();
  await expect(section.getByRole('button', { name: 'Cancel' })).toBeVisible();
  await expect.poll(() => auth.finishConnect !== null).toBe(true);

  // The signed-in row replaces the Connect row in place. Rabbita patches the
  // existing <button>, so the disabled state must actually be cleared rather
  // than left behind as a DOM property the diff cannot remove.
  auth.finishConnect();
  const disconnect = section.getByRole('button', { name: 'Disconnect' });
  await expect(section.getByText('@octocat — online — reachable from your browser')).toBeVisible();
  await expect(disconnect).toBeEnabled();

  await disconnect.click();
  await expect(section.getByRole('button', { name: 'Connect with GitHub' })).toBeEnabled();
});
