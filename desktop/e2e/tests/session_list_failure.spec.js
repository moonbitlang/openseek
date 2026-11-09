import { test, expect } from './support/test.js';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';

for (const failure of ['reply', 'transport']) {
  test(`a workspace list ${failure} failure on startup displays the cause`, async ({ page }) => {
    const app = new DesktopBrowserHarness(page);
    const message = 'the workspace list is malformed: expected a JSON object';
    if (failure === 'reply') {
      const replyFor = app.replyFor.bind(app);
      app.replyFor = request => request.method === 'workspace.list'
        ? { error: message }
        : replyFor(request);
    } else {
      app.rpcErrors.set('workspace.list', message);
    }
    await app.install();
    await app.goto();
    await expect(page.getByText(`Workspace error: ${message}`, { exact: true }).first()).toBeVisible();
    expect(app.pageErrors).toEqual([]);
  });
}
