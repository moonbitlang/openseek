import { test, expect } from '@playwright/test';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';

async function open(page, workspaces = ['/workspace']) {
  const app = new DesktopBrowserHarness(page);
  app.workspaces = workspaces;
  app.codexModels = [{ id: 'gpt-test', displayName: 'Codex test', isDefault: true }];
  app.searchFiles = ['src/main.mbt'];
  await app.install();
  await app.goto();
  await expect(page.getByRole('button', { name: 'Rabbita browser fixture', exact: true })).toBeVisible();
  return app;
}

async function choose(page, name) {
  await page.getByRole('button', { name: 'Model', exact: true }).click();
  await page.getByRole('option', { name, exact: true }).click();
  await expect(page.getByRole('button', { name: 'Model', exact: true })).toContainText(name);
}

test('both agents share the first screen and Codex can choose its project in the title', async ({ page }, testInfo) => {
  const app = await open(page, ['/workspace', '/other']);
  const title = page.locator('.empty-title');
  const badge = page.locator('.empty-badge');
  const transcript = page.locator('#transcript');
  await expect(title).toHaveText('What should we build in workspace?');
  const logo = await badge.innerHTML();
  await expect(page.locator('.empty-sub')).toHaveCount(0);
  await choose(page, 'Codex test');
  const trigger = page.getByRole('button', {
    name: 'Choose project, current project workspace', exact: true,
  });
  await expect(trigger).toBeVisible();
  expect(await badge.innerHTML()).toBe(logo);
  await expect(page.getByText(/Codex inspects, edits/)).toHaveCount(0);
  const session = await transcript.getAttribute('data-transcript-session');
  const openCount = app.requests.filter(r => r.method === 'codex.draft.open').length;
  const task = page.locator('#task');
  await task.fill('@main');
  await page.locator('.completion-item').filter({ hasText: 'src/main.mbt' }).click();
  await task.press('End');
  await task.pressSequentially(' Keep this draft when changing projects');
  const draftText = await task.inputValue();
  const png = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aCfoAAAAASUVORK5CYII=';
  const imageURL = `data:image/png;base64,${png}`;
  const chooser = page.waitForEvent('filechooser');
  await page.getByRole('button', { name: 'Attach files', exact: true }).click();
  await (await chooser).setFiles({ name: 'screen.png', mimeType: 'image/png', buffer: Buffer.from(png, 'base64') });
  await expect(page.locator('.composer-image img')).toHaveAttribute('src', imageURL);

  await trigger.click();
  const picker = page.getByRole('dialog', { name: 'Choose a project' });
  const search = picker.getByRole('textbox', { name: 'Search projects' });
  await expect(search).toBeFocused();
  await search.fill('oth');
  await expect(picker.getByRole('button', { name: /^workspace/ })).toHaveCount(0);
  await expect(picker.getByRole('button', { name: /^other —/ })).toBeVisible();
  await search.press('Escape');
  await expect(picker).toBeHidden();
  await expect(trigger).toBeFocused();
  await trigger.click();
  await picker.getByRole('button', { name: /^workspace, current project/ }).click();
  await expect(picker).toBeHidden();
  await expect(transcript).toHaveAttribute('data-transcript-session', session);
  expect(app.requests.filter(r => r.method === 'codex.draft.open')).toHaveLength(openCount);
  await trigger.click();
  await picker.getByRole('button', { name: /^other —/ }).click();
  await expect(title).toHaveText('What should we build in other?');
  await expect(page.locator('.workspace-row[title="/other"]')).toHaveClass(/\bactive\b/);
  await expect(transcript).toHaveAttribute('data-transcript-session', session);
  await expect(page.getByRole('button', { name: 'Model', exact: true })).toContainText('Codex test');
  await expect.poll(() => app.requests.filter(r => r.method === 'codex.draft.open').at(-1)?.params.cwd).toBe('/other');
  await expect(task).toHaveValue(draftText);
  await expect(page.locator('.composer-image img')).toHaveAttribute('src', imageURL);
  await expect(page.locator('.mention-chip').filter({ hasText: 'src/main.mbt' })).toContainText('src/main.mbt');
  expect(app.requests.filter(r => r.method === 'codex.draft.close')).toHaveLength(0);
  await page.screenshot({ path: testInfo.outputPath('codex-unified-first-screen.png') });
  const otherTrigger = page.getByRole('button', {
    name: 'Choose project, current project other', exact: true,
  });
  await otherTrigger.click();
  await picker.getByRole('button', { name: 'New project', exact: true }).click();
  const addProject = page.getByRole('dialog', { name: 'Add a project' });
  await expect(addProject).toBeVisible();
  await addProject.getByRole('button', { name: 'Add project', exact: true }).click();
  await expect.poll(() => app.requests.some(r => r.method === 'workspace.add')).toBe(true);
  app.notify('workspace.changed', { workspaces: app.workspaces });
  await expect(title).toHaveText('What should we build in test?');
  await expect(transcript).toHaveAttribute('data-transcript-session', session);
  await expect(task).toHaveValue(draftText);
  await expect(page.locator('.composer-image img')).toHaveAttribute('src', imageURL);
  await expect(page.locator('.mention-chip')).toContainText('src/main.mbt');
  await expect(addProject).toBeHidden();
  await page.locator('#send').click();
  await expect.poll(() => app.requests.find(r => r.method === 'codex.thread.start')?.params.cwd).toBe('/Users/test');
  await expect(page.getByRole('button', { name: /^Choose project, current project/ })).toHaveCount(0);
  await expect.poll(() => app.requests.find(r => r.method === 'codex.turn.start')?.params.input).toEqual([
    { type: 'text', text: expect.stringContaining('Keep this draft when changing projects') },
    { type: 'mention', name: 'main.mbt', path: 'src/main.mbt' },
    { type: 'image', url: imageURL },
  ]);
  expect(app.pageErrors).toEqual([]);
});

for (const failure of ['rpc', 'malformed']) {
  test(`Codex project selection recovers after a ${failure} draft-open failure`, async ({ page }) => {
    await page.addInitScript(minimal => {
      localStorage.setItem('openseek.minimal_transcript', String(minimal));
    }, failure === 'malformed');
    const app = await open(page, ['/workspace', '/other']);
    await choose(page, 'Codex test');
    const task = page.locator('#task');
    await task.fill('Keep this input after an open failure');
    const session = await page.locator('#transcript').getAttribute('data-transcript-session');
    const reply = app.replyFor.bind(app);
    if (failure === 'rpc') {
      app.rpcErrors.set('codex.draft.open', 'Project unavailable');
    } else {
      app.replyFor = request => request.method === 'codex.draft.open' ? {} : reply(request);
    }
    await page.getByRole('button', { name: 'Choose project, current project workspace', exact: true }).click();
    const picker = page.getByRole('dialog', { name: 'Choose a project' });
    await picker.getByRole('button', { name: /^other —/ }).click();
    const other = page.getByRole('button', { name: 'Choose project, current project other', exact: true });
    await expect(other).toBeVisible();
    await expect(page.locator('#send')).toBeDisabled();
    // Wait for the error result to settle before retrying the same project.
    await expect(page.getByText(failure === 'rpc' ? /Project unavailable/ : /Malformed reply from codex.draft.open/)).toBeVisible();
    app.rpcErrors.delete('codex.draft.open');
    app.replyFor = reply;
    await other.click();
    if (failure === 'rpc') {
      await picker.getByRole('button', { name: /^other, current project/ }).click();
    } else {
      await picker.getByRole('button', { name: /^workspace —/ }).click();
    }
    await expect(page.locator('#send')).toBeEnabled();
    await expect(page.locator('#transcript')).toHaveAttribute('data-transcript-session', session);
    await expect(task).toHaveValue('Keep this input after an open failure');
    await page.locator('#send').click();
    await expect.poll(() => app.requests.find(r => r.method === 'codex.thread.start')?.params.cwd)
      .toBe(failure === 'rpc' ? '/other' : '/workspace');
    expect(app.pageErrors).toEqual([]);
  });
}
