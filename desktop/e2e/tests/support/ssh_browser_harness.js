import { DesktopBrowserHarness } from './desktop_browser_harness.js';

// Replace only the native request/event transport; use the production views
// and existing host replies for the SSH project's browser presentation tests.
export class SshBrowserHarness extends DesktopBrowserHarness {
  async install() {
    await super.install();
    this.attempt = 0;
    this.mockRpc({
      'ssh.profiles': () => ({
        hosts: [{
          id: 'ssh-demo',
          command: 'ssh demo@example.test',
          display_name: 'Demonstration SSH workstation with a long name',
          projects: ['openseek://remote.ssh-demo/workspace'],
        }],
      }),
      'ssh.connect': request => {
        this.attempt = request.params.attempt;
        return {};
      },
      'ssh.request': async request => ({
        outcome: 'success',
        value: await this.dispatchRpc({ method: request.params.method, params: request.params.params }),
      }),
    });
    await this.installNative();
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
    await this.emitNative('openseek.ssh.event', {
      host_id: 'ssh-demo',
      attempt: this.attempt,
      epoch: this.attempt,
      event,
    });
  }
}
