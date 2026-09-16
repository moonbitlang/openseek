import { test, expect } from '@playwright/test';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';

class ExternalFileHarness extends DesktopBrowserHarness {
  externalSignature = 'external:1';

  replyFor(request) {
    switch (request.method) {
      case 'host.open_path':
        return { opened: false, editor_target: { path: request.params.path } };
      case 'fs.stat_files':
        return { stats: request.params.paths.map(path => ({
          path,
          signature: {
            kind: 'present',
            sig: path === '/outside/notes.txt'
              ? this.externalSignature : `working:${path.slice('/workspace/'.length)}`,
          },
        })) };
      case 'lsp.open':
        return { diagnostics: [] };
      default:
        return super.replyFor(request);
    }
  }

  readWorkingFile(params) {
    const reply = super.readWorkingFile(params);
    return params.path === '/outside/notes.txt'
      ? { ...reply, sig: this.externalSignature } : reply;
  }

  count(method, path) {
    return this.requests.filter(request => request.method === method &&
      (path === undefined || request.params?.path === path)).length;
  }
}

test('external polls reload changed files without checking workspace diagnostics', async ({ page }) => {
  const app = new ExternalFileHarness(page);
  app.workingFiles['/outside/notes.txt'] = 'Original external content';
  app.sessionEvents[1].item.payload.content =
    '[External](/outside/notes.txt) [Source](/workspace/src/main.mbt)';
  await app.install();
  await app.goto();
  await app.openSession();
  const transcript = page.locator('.transcript');
  const external = transcript.getByRole('button', { name: 'External', exact: true });
  const source = transcript.getByRole('button', { name: 'Source', exact: true });
  await external.click();
  await expect.poll(() => app.count('fs.read_file', '/outside/notes.txt')).toBe(1);
  await source.click();
  await expect.poll(() => app.count('lsp.open')).toBeGreaterThan(0);

  // Complete multiple real polling rounds with the workspace file active.
  // They must neither reload unchanged external content nor recheck the module.
  const diagnostics = app.count('lsp.open');
  const polls = app.count('fs.stat_files');
  await expect.poll(() => app.count('fs.stat_files'), { timeout: 8_000 })
    .toBeGreaterThanOrEqual(polls + 2);
  await page.waitForTimeout(150);
  expect(app.count('lsp.open')).toBe(diagnostics);
  expect(app.count('fs.read_file', '/outside/notes.txt')).toBe(1);

  // An actual workspace watcher notification still refreshes diagnostics,
  // even when the active file's own signature is unchanged.
  const watch = app.requests.filter(request => request.method === 'fs.watch').at(-1);
  app.notify('fs.changed', {
    root: '/workspace', generation: watch.params.generation, baseline: false,
    events: [{ kind: 'modify', path: 'src/main.mbt' }],
  });
  await expect.poll(() => app.count('lsp.open')).toBeGreaterThan(diagnostics);

  // A background external change becomes stale and reloads when selected.
  const afterWorkspaceChange = app.count('lsp.open');
  app.externalSignature = 'external:2';
  app.workingFiles['/outside/notes.txt'] = 'Changed external content';
  const beforeChange = app.count('fs.stat_files');
  await expect.poll(() => app.count('fs.stat_files'), { timeout: 5_000 })
    .toBeGreaterThan(beforeChange);
  await page.waitForTimeout(150);
  expect(app.count('lsp.open')).toBe(afterWorkspaceChange);
  expect(app.count('fs.read_file', '/outside/notes.txt')).toBe(1);
  await external.click();
  await expect.poll(() => app.count('fs.read_file', '/outside/notes.txt')).toBe(2);

  // The active external tab still reloads on change without a workspace check.
  app.externalSignature = 'external:3';
  app.workingFiles['/outside/notes.txt'] = 'Changed again';
  await expect.poll(() => app.count('fs.read_file', '/outside/notes.txt'), { timeout: 5_000 })
    .toBe(3);
  expect(app.count('lsp.open')).toBe(afterWorkspaceChange);
  expect(app.pageErrors).toEqual([]);
});
