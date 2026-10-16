import { test, expect } from '@playwright/test';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';

test('SSH project terminal uses its host route and survives app-server disconnect', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  await app.install();
  const direct = [];
  await page.exposeFunction('desktopRequest', request => {
    direct.push(request);
    if (request.method === 'ssh.profiles') return { hosts: [{
      id: 'ssh_demo', name: 'Demo SSH', destination: 'demo', launcher: '/bin/openseek',
      data_dir: '/data', build_id: 'demo',
    }] };
    if (request.method === 'ssh.cached_projects') return ['/workspace'];
    if (request.method === 'ssh.connect') return { status: 'completed', value: { ok: true } };
    if (request.method === 'workspace.list') return { workspaces: ['/local-workspace'], chat_root: app.chatRoot };
    if (request.method === 'session.list') return app.sessionGroups([]);
    if (request.method === 'ssh.request') {
      if (request.params.method.startsWith('terminal.')) throw new Error('Terminal reached app-server');
      const remote = { method: request.params.method, params: request.params.params };
      app.requests.push(remote);
      return { outcome: 'success', value: app.replyFor(remote) };
    }
    if (request.method === 'ssh.host_request') {
      expect(request.params.host_id).toBe('ssh_demo');
      const remote = { method: request.params.method, params: request.params.params };
      direct.push(remote);
      return { outcome: 'success', value: remote.method === 'terminal.open'
        ? { id: 'ssh-terminal-1' } : app.replyFor(remote) };
    }
    if (request.method === 'app.system_appearance') return { dark: false };
    if (request.method.startsWith('terminal.')) throw new Error('Remote terminal reached local host');
    app.requests.push(request);
    return app.replyFor(request);
  });
  await page.addInitScript(() => {
    const listeners = new Map();
    const events = { on(name, callback) {
      const callbacks = listeners.get(name) || new Set();
      listeners.set(name, callbacks); callbacks.add(callback);
      return () => callbacks.delete(callback);
    } };
    window.desktopEvent = (name, payload) => {
      for (const callback of listeners.get(name) || []) callback({ payload });
    };
    window.__MoonBit__ = { app: events, events, openseek: new Proxy({}, {
      get: (_, method) => async params => {
        if (method === 'host.connect') {
          window.desktopEvent('openseek.agent.connected', { stage: 'serving' });
        }
        if (method === 'ssh.connect') {
          window.desktopEvent('openseek.ssh.event', { host_id: params.id, event: { kind: 'connected', epoch: 1 } });
          window.desktopEvent('openseek.ssh.event', { host_id: params.id, event: { kind: 'notification', epoch: 1,
            value: { method: 'agent.connected', params: { stage: 'serving' } } } });
        }
        return window.desktopRequest({ method, params });
      },
    }) };
  });
  await page.goto('/dist/browser/index.html');
  await app.openSession();
  await expect(page.getByRole('button', { name: 'local-workspace', exact: true })).toBeVisible();
  await page.getByRole('button', { name: /^Show terminal/ }).click();
  await expect.poll(() => direct.filter(r => r.method === 'terminal.open').length).toBe(1);
  expect(direct.filter(r => r.method === 'ssh.host_request' && r.params.method === 'terminal.open')).toHaveLength(1);
  const opened = direct.find(r => r.method === 'terminal.open');
  expect(opened.params.workspace).toBe('/workspace');
  await page.evaluate(() => {
    window.desktopEvent('openseek.ssh.event', { host_id: 'ssh_demo', event: {
      kind: 'terminal', value: { method: 'terminal.output', params: {
        id: 'ssh-terminal-1', sequence: 1, data: btoa('SSH terminal ready\r\n'),
      } },
    } });
    window.desktopEvent('openseek.ssh.event', { host_id: 'ssh_demo', event: { kind: 'disconnected', epoch: 1, message: 'App-server restarting' } });
  });
  await expect.poll(() => direct.filter(r => r.method === 'terminal.ack').length).toBeGreaterThan(0);
  const input = page.locator('.terminal-instance textarea').first();
  await input.focus();
  await page.keyboard.type('echo still-here');
  await page.keyboard.press('Enter');
  await expect.poll(() => direct.filter(r => r.method === 'terminal.input')
    .map(r => r.params.data || '').join('')).toContain('echo still-here');
  await page.setViewportSize({ width: 1200, height: 820 });
  await expect.poll(() => direct.filter(r => r.method === 'terminal.resize').length).toBeGreaterThan(0);
  expect(direct.filter(r => r.method === 'terminal.open')).toHaveLength(1);
  expect(direct.filter(r => r.method === 'terminal.close')).toHaveLength(0);
  expect(app.pageErrors).toEqual([]);
});
