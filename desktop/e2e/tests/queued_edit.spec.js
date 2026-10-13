import { test, expect } from '@playwright/test';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';

for (const outcome of ['accepted', 'rpc-error', 'rejected']) {
  test(`queued edit serializes saves and recovers after ${outcome}`, async ({ page }, testInfo) => {
    const app = new DesktopBrowserHarness(page);
    app.hostSettings.followup_behavior = 'queue';
    await app.install();
    await app.goto();
    await app.openSession();
    const composer = page.locator('#task');
    await composer.fill('Start a turn');
    await page.locator('#send').click();
    await composer.fill('Original queued message');
    await composer.press('Enter');
    const queued = page.locator('.queued-input-row');
    await expect(queued).toContainText('Original queued message');
    await queued.getByTitle('Edit', { exact: true }).click();
    await composer.fill('Edited queued message');

    // Hold the host response so the real composer can receive repeated input
    // events, including events already queued before its DOM became disabled.
    const replyFor = app.replyFor.bind(app);
    let heldRequest;
    app.replyFor = request => {
      if (request.method === 'agent.queue' && request.params.action === 'edit') {
        heldRequest = request;
        return new Promise(() => {});
      }
      return replyFor(request);
    };
    const save = page.getByTitle('Save queued message', { exact: true });
    await save.click();
    await expect.poll(() => heldRequest?.id).toBeDefined();
    await expect(composer).toBeDisabled();
    await expect(save).toBeDisabled();
    for (const button of await queued.getByRole('button').all()) {
      await expect(button).toBeDisabled();
    }
    await save.dispatchEvent('click');
    await composer.dispatchEvent('keydown', { key: 'Enter', code: 'Enter', bubbles: true });
    await expect(composer).toHaveValue('Edited queued message');
    if (outcome === 'accepted') {
      const path = testInfo.outputPath('queued-edit-saving.png');
      await page.locator('.composer').screenshot({ path });
      await testInfo.attach('Saving queued edit', { path, contentType: 'image/png' });
    }
    const edits = () => app.requests.filter(r => r.method === 'agent.queue' && r.params.action === 'edit');
    expect(edits()).toHaveLength(1);
    const response = outcome === 'rpc-error'
      ? { error: { code: -32000, message: 'Save rejected' } }
      : { result: { accepted: outcome === 'accepted' } };
    app.socket.send(JSON.stringify({ jsonrpc: '2.0', id: heldRequest.id, ...response }));
    await expect(composer).toBeEnabled();
    if (outcome === 'accepted') {
      await expect(composer).toHaveValue('');
      await expect(queued).toContainText('Edited queued message');
    } else {
      await expect(composer).toHaveValue('Edited queued message');
      await expect(queued).toContainText('Original queued message');
      await expect(save).toBeEnabled();
      app.replyFor = replyFor;
      await composer.fill('Retry this edit');
      await save.click();
      await expect(composer).toHaveValue('');
      await expect(queued).toContainText('Retry this edit');
      expect(edits()).toHaveLength(2);
    }
    expect(app.pageErrors).toEqual([]);
  });
}
