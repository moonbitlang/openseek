import { DesktopBrowserHarness } from './desktop_browser_harness.js';

// Replace only the native request/event transport; use the production views
// and existing host replies for the SSH project's browser presentation tests.
export class SshBrowserHarness extends DesktopBrowserHarness {
  async install() {
    await super.install();
    this.attempt = 0;
    await this.page.exposeFunction('sshFixtureRpc', async (method, params) => {
      this.requests.push({ method, params });
      if (method === 'app.system_appearance') return { dark: false };
      if (method === 'ssh.profiles') return { hosts: [{
        id: 'ssh-demo', command: 'ssh demo@example.test',
        display_name: 'Demonstration SSH workstation with a long name',
        projects: ['openseek://remote.ssh-demo/workspace'],
      }] };
      if (method === 'ssh.connect') {
        this.attempt = params.attempt;
        return {};
      }
      if (method === 'ssh.request') return {
        outcome: 'success',
        value: await this.replyFor({ method: params.method, params: params.params }),
      };
      return this.replyFor({ method, params });
    });
    await this.page.addInitScript(() => {
      const handlers = new Map();
      window.sshFixtureEmit = (name, payload) => {
        for (const fn of handlers.get(name) || []) fn({ payload });
      };
      const events = { on(name, fn) {
        const listeners = handlers.get(name) || [];
        listeners.push(fn);
        handlers.set(name, listeners);
        return () => handlers.set(name, listeners.filter(item => item !== fn));
      } };
      window.__MoonBit__ = { events, app: events, openseek: new Proxy({}, {
        get: (_, method) => async params => {
          if (method === 'host.connect') {
            window.sshFixtureEmit('openseek.agent.connected', { protocol: 5 });
          }
          return window.sshFixtureRpc(method, params);
        },
      }) };
    });
  }

  async goto() {
    await this.page.goto('/index.html');
    await this.page.getByRole('main').waitFor();
  }

  async openRemoteProject() {
    const row = this.projectRow('/workspace', 'remote.ssh-demo');
    await row.hover();
    await row.getByRole('button', { name: 'New conversation in this project' }).click();
  }

  async sshEvent(event) {
    await this.page.evaluate(payload => window.sshFixtureEmit('openseek.ssh.event', payload), {
      host_id: 'ssh-demo', attempt: this.attempt, epoch: this.attempt, event,
    });
  }
}
