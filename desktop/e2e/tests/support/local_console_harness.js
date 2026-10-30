import { readFile } from 'node:fs/promises';
import { CloudHarness } from './cloud_harness.js';

const bundle = new URL('../../../dist/browser/', import.meta.url);

export function localAccount(id = 'desktop-alice') {
  return {
    token: `ts_local-fixture-${id}`,
    user: { user_id: id, login: id, avatar_url: '' },
  };
}

// The local console changes only its account and host transports. The shared
// Cloud fixture still exercises the real direct authenticated Cloud client.
export class LocalConsoleHarness extends CloudHarness {
  constructor(page, origin, account = localAccount()) {
    super(page, { cached: false });
    this.origin = new URL(origin).origin;
    this.desktopAccount = account;
    this.sessionStatus = 200;
    this.userId = account?.user.user_id || 'signed-out';
    this.localRequests = [];
    this.unexpectedRequests = [];
    this.localSockets = [];
    this.hostNotifications = [];
    this.document = '';
    this.cookieName = `seekmoon_session_${new URL(this.origin).port}`;
  }

  setAccount(account) {
    this.desktopAccount = account;
    this.userId = account?.user.user_id || 'signed-out';
  }

  accountChanged(account) {
    this.setAccount(account);
    // Match the host hub's presentation-only JSON-RPC event. Credentials are
    // obtained by the frontend's subsequent launch-authorized session read.
    const notification = { jsonrpc: '2.0', method: 'auth.changed', params: { connected: account !== null } };
    this.hostNotifications.push(notification);
    this.device.socket.send(JSON.stringify(notification));
  }

  async install({ staleAccount } = {}) {
    await super.install();
    if (staleAccount) {
      await this.page.addInitScript(account => {
        if (!sessionStorage.getItem('fixture-local-stale-account')) {
          sessionStorage.setItem('fixture-local-stale-account', 'true');
          localStorage.setItem('seekmoon.account.v1', JSON.stringify(account));
        }
      }, staleAccount);
    }
    await this.page.context().addCookies([{
      name: this.cookieName, value: 'fixture-launch-session', url: this.origin,
      httpOnly: true, sameSite: 'Strict',
    }]);
    await this.page.route(url => url.origin === this.origin &&
      (url.pathname === '/index.html' || url.pathname.startsWith('/device/') ||
       url.pathname === '/cloud' || url.pathname.startsWith('/cloud/')), async route => {
      if (!route.request().isNavigationRequest()) return route.fallback();
      const html = await readFile(new URL('index.html', bundle), 'utf8');
      this.document = html.replace('<head>', '<head>\n<meta name="seekmoon-local-console" />');
      return route.fulfill({ contentType: 'text/html', body: this.document });
    });
    await this.page.route(url => url.origin === this.origin && /^\/v[12]\//.test(url.pathname), async route => {
      const request = route.request();
      const path = new URL(request.url()).pathname;
      const recorded = { path, method: request.method(), headers: await request.allHeaders() };
      this.localRequests.push(recorded);
      if (!recorded.headers.cookie?.includes(`${this.cookieName}=fixture-launch-session`)) {
        return route.fulfill({ status: 401 });
      }
      const json = body => route.fulfill({ contentType: 'application/json', body: JSON.stringify(body) });
      if (path === '/v1/auth/session' && request.method() === 'GET') {
        if (this.sessionStatus !== 200) return route.fulfill({ status: this.sessionStatus, body: 'Fixture Desktop account read unavailable' });
        return json(this.desktopAccount ? { session: this.desktopAccount } : {});
      }
      // Launch authorization remains valid even if Desktop has no account.
      if (path === '/v1/auth/me') return json({ login: 'local' });
      if (path === '/v1/devices') return json({ devices: [{ id: 'host', name: 'Local fixture computer', online: true }] });
      this.unexpectedRequests.push(recorded);
      return route.fulfill({ status: 500, body: `Unexpected local console request: ${path}` });
    });
    await this.page.routeWebSocket(url => url.origin === this.origin.replace(/^http/, 'ws') &&
      url.pathname === '/v1/devices/host/ws', socket => {
      this.localSockets.push(socket.url());
      this.device.socketURLs.push(socket.url());
      this.device.socket = socket;
      socket.onMessage(async message => {
        const request = JSON.parse(message.toString());
        this.device.requests.push(request);
        if (request.id === undefined) return;
        const result = await this.device.replyFor(request);
        socket.send(JSON.stringify({ jsonrpc: '2.0', id: request.id, result }));
      });
      socket.send(JSON.stringify({ jsonrpc: '2.0', method: 'agent.connected', params: { protocol: this.device.hostProtocol } }));
    });
  }

  cloudRequest(route) {
    // Existing Cloud fixtures use the public console's origin. This console
    // is loopback, so preserve its real CORS boundary in the mocked response.
    return super.cloudRequest({
      request: () => route.request(),
      abort: (...args) => route.abort(...args),
      fulfill: options => route.fulfill({
        ...options,
        headers: { ...options.headers, 'Access-Control-Allow-Origin': this.origin },
      }),
    });
  }

  async goto(path = '/cloud') {
    await this.page.goto(this.origin + path);
  }
}
