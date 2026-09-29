import { test, expect } from '@playwright/test';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';

for (const viewing of ['openseek', 'other-codex', 'target', 'settings']) {
  test(`Codex archive confirmation keeps its target while viewing ${viewing}`, async ({ page }) => {
    const app = new DesktopBrowserHarness(page);
    const threads = [
      { id: 'codex-target', preview: 'Codex target', cwd: '/workspace', projectRoot: '/workspace', updatedAt: 3, turns: [] },
      { id: 'codex-other', preview: 'Codex other', cwd: '/workspace', projectRoot: '/workspace', updatedAt: 2, turns: [] },
    ];
    let archived = false;
    const replyFor = app.replyFor.bind(app);
    app.replyFor = request => {
      if (request.method === 'codex.thread.list') {
        return { data: request.params?.archived
          ? (archived ? [threads[0]] : [])
          : threads.filter(thread => !archived || thread.id !== 'codex-target') };
      }
      if (request.method === 'codex.thread.history.read') {
        return { thread: threads.find(thread => thread.id === request.params.threadId) };
      }
      if (request.method === 'codex.thread.archive') {
        if (request.params.force) {
          archived = true;
          return {};
        }
        return {
          kind: 'needs_force', worktree: '/workspace/worktrees/dirty',
          dirty_paths: ['README.md'], dirty_path_count: 1,
        };
      }
      return replyFor(request);
    };
    await app.install();
    await app.goto();
    const row = name => page.locator('.conversation-row').filter({
      has: page.getByRole('button', { name, exact: true }),
    });
    const target = row('Codex target');
    let current;
    if (viewing === 'settings') {
      await page.getByRole('button', { name: 'Settings', exact: true }).click();
    } else {
      current = row(viewing === 'openseek' ? 'Rabbita browser fixture'
        : viewing === 'target' ? 'Codex target' : 'Codex other');
      await current.locator('.conversation-open').click();
      await expect(current).toHaveClass(/active/);
    }
    const main = page.getByRole('main');
    const content = await main.innerText();
    const archiveRequests = () => app.requests.filter(request => request.method === 'codex.thread.archive');
    const dialog = page.locator('.modal-backdrop');
    const archive = async () => {
      await target.hover();
      await target.getByRole('button', { name: 'Archive Codex conversation', exact: true }).click();
      await expect(dialog).toHaveCount(1);
      await expect(dialog).toBeVisible();
      await expect(dialog).toContainText('/workspace/worktrees/dirty');
      await expect(dialog).toContainText('README.md');
    };

    await archive();
    await dialog.getByRole('button', { name: 'Keep working', exact: true }).click();
    await expect(dialog).toHaveCount(0);
    expect(archiveRequests().map(request => request.params)).toEqual([
      { threadId: 'codex-target', force: false },
    ]);
    await expect(main).toHaveText(content, { useInnerText: true });
    if (current) await expect(current).toHaveClass(/active/);

    await archive();
    await dialog.getByRole('button', { name: 'Discard local changes and archive', exact: true }).click();
    await expect(dialog).toHaveCount(0);
    await expect.poll(() => archiveRequests().map(request => request.params)).toEqual([
      { threadId: 'codex-target', force: false },
      { threadId: 'codex-target', force: false },
      { threadId: 'codex-target', force: true },
    ]);
    await expect(target).toHaveCount(0);
    if (viewing !== 'target') {
      await expect(main).toHaveText(content, { useInnerText: true });
      if (current) await expect(current).toHaveClass(/active/);
    }
    expect(app.pageErrors).toEqual([]);
  });
}
