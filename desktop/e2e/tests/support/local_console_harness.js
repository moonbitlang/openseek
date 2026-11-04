import { readFile } from 'node:fs/promises';
import { CloudHarness } from './cloud_harness.js';

const bundle = new URL('../../../dist/browser/', import.meta.url);
export const browserAccount = {
  token: 'ts_browser-fixture',
  user: { user_id: 'browser-user', login: 'browser-user', avatar_url: '' },
};

export class LocalConsoleHarness extends CloudHarness {
  constructor(page, origin) {
    super(page, { cached: false });
    this.origin = new URL(origin).origin;
    this.userId = browserAccount.user.user_id;
    this.localRequests = [];
    this.localSockets = [];
  }

  async install() {
    await super.install();
    await this.page.route(url => url.origin === this.origin &&
      (url.pathname === '/index.html' || url.pathname.startsWith('/device/') ||
       url.pathname === '/cloud' || url.pathname.startsWith('/cloud/')), async route => {
      if (!route.request().isNavigationRequest()) return route.fallback();
      const html = await readFile(new URL('index.html', bundle), 'utf8');
      return route.fulfill({ contentType: 'text/html', body: html.replace('<head>', '<head>\n<meta name="seekmoon-local-console" />') });
    });
    await this.page.route(url => url.origin === this.origin &&
      (/^\/v[12]\//.test(url.pathname) || url.pathname === '/cb'), async route => {
      const request = route.request();
      const url = new URL(request.url());
      const recorded = { path: url.pathname, method: request.method(), headers: await request.allHeaders() };
      this.localRequests.push(recorded);
      // OAuth/PKCE is exercised by the native server tests. Here the callback
      // hands the real frontend its own browser account through the same store.
      if (url.pathname === '/cb') {
        return route.fulfill({ contentType: 'text/html', body: `<script>localStorage.setItem('seekmoon.account.v1', ${JSON.stringify(JSON.stringify(browserAccount))});location.replace('/cloud');</script>` });
      }
      const json = body => route.fulfill({ contentType: 'application/json', body: JSON.stringify(body) });
      if (url.pathname === '/v2/auth/login') {
        return route.fulfill({ contentType: 'text/html', body: `<script>location.replace('/cb?code=fixture&state=fixture');</script>` });
      }
      if (url.pathname === '/v2/auth/logout' && request.method() === 'POST') {
        return route.fulfill({ status: this.logoutStatus });
      }
      if (url.pathname === '/v1/auth/me') return json({ login: 'local' });
      if (url.pathname === '/v1/devices') return json({ devices: [{ id: 'host', name: 'Local fixture computer', online: true }] });
      throw new Error(`Unexpected local console request: ${url.pathname}`);
    });
    await this.page.routeWebSocket(url => url.origin === this.origin.replace(/^http/, 'ws') &&
      url.pathname === '/v1/devices/host/ws', socket => {
      this.localSockets.push(socket.url());
      this.device.socket = socket;
      socket.onMessage(async message => {
        const request = JSON.parse(message.toString());
        this.device.requests.push(request);
        if (request.id === undefined) return;
        socket.send(JSON.stringify({ jsonrpc: '2.0', id: request.id, result: await this.device.replyFor(request) }));
      });
      socket.send(JSON.stringify({ jsonrpc: '2.0', method: 'agent.connected', params: { protocol: this.device.hostProtocol } }));
    });
  }

  cloudRequest(route) {
    return super.cloudRequest({
      request: () => route.request(), abort: (...args) => route.abort(...args),
      fulfill: options => route.fulfill({ ...options,
        headers: { ...options.headers, 'Access-Control-Allow-Origin': this.origin },
      }),
    });
  }

  async goto(path = '/cloud') { await this.page.goto(this.origin + path); }
}
