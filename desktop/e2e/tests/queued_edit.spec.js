import { test, expect } from './support/test.js';
import { readFileSync } from 'node:fs';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';

for (const outcome of ['accepted', 'rpc-error']) {
  test(`queued edit serializes saves and recovers after ${outcome}`, async ({ page }) => {
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
    await expect(composer).toHaveValue('Original queued message');
    await composer.fill('Edited queued message');
    const chooser = page.waitForEvent('filechooser');
    await page.getByRole('button', { name: 'Attach files', exact: true }).click();
    await (await chooser).setFiles({ name: 'notes.pdf', mimeType: 'application/pdf', buffer: readFileSync(new URL('../fixtures/office/two-pages.pdf', import.meta.url)) });
    await page.getByRole('button', { name: 'Upload to workspace', exact: true }).click();
    const mention = page.locator('.mention-chip').filter({ hasText: 'notes.pdf', hasNotText: 'Context added during save' });
    await expect(mention).toBeVisible();

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
    await expect(mention.locator('.mention-remove')).toBeDisabled();
    await mention.locator('.mention-remove').dispatchEvent('click');
    for (const button of await queued.getByRole('button').all()) {
      await expect(button).toBeDisabled();
    }
    await save.dispatchEvent('click');
    await composer.dispatchEvent('keydown', { key: 'Enter', code: 'Enter', bubbles: true });
    await expect(composer).toHaveValue('Edited queued message');
    const edits = () => app.requests.filter(r => r.method === 'agent.queue' && r.params.action === 'edit');
    expect(edits()).toHaveLength(1);
    // The editor is still usable while the composer waits for the save.
    // Context added here belongs to the next draft, not the held request.
    await mention.locator('.mention-jump').click();
    await expect(page.locator('#openseek-office-surface')).toHaveAttribute('data-pdf-painted', 'true');
    const text = page.locator('.page[data-page-number="1"] [data-pdf-item]').filter({ hasText: 'OpenSeek PDF preview' }).first();
    await text.evaluate(element => {
      const range = document.createRange();
      range.setStart(element.firstChild, 0);
      range.setEnd(element.firstChild, 8);
      const selection = window.getSelection();
      selection.removeAllRanges();
      selection.addRange(range);
      document.dispatchEvent(new Event('selectionchange'));
    });
    const preview = page.locator('.office-selection-preview');
    await expect(preview).toBeVisible();
    await preview.locator('textarea').fill('Context added during save');
    await preview.getByRole('checkbox').check();
    await preview.getByRole('button', { name: 'Add feedback', exact: true }).click();
    const added = page.locator('.mention-chip').filter({ hasText: 'Context added during save' });
    await expect(added).toBeVisible();
    expect(heldRequest.params.text).not.toContain('Context added during save');
    const response = outcome === 'rpc-error'
      ? { error: { code: -32000, message: 'Save rejected' } }
      : { result: { accepted: true } };
    app.socket.send(JSON.stringify({ jsonrpc: '2.0', id: heldRequest.id, ...response }));
    await expect(composer).toBeEnabled();
    await expect(added).toBeVisible();
    await expect(added.locator('.mention-remove')).toBeEnabled();
    if (outcome === 'accepted') {
      await expect(composer).toHaveValue('');
      await expect(queued).toContainText('Edited queued message');
      await expect(mention).toHaveCount(0);
      await added.locator('.mention-remove').click();
      await expect(added).toHaveCount(0);
    } else {
      await expect(composer).toHaveValue('Edited queued message');
      await expect(queued).toContainText('Original queued message');
      await expect(save).toBeEnabled();
      await expect(mention.locator('.mention-remove')).toBeEnabled();
      await mention.locator('.mention-remove').click();
      await expect(mention).toHaveCount(0);
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
