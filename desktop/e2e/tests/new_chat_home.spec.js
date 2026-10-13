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
  await expect(transcript).not.toHaveAttribute('data-transcript-session', session);
  await expect(page.getByRole('button', { name: 'Model', exact: true })).toContainText('Codex test');
  await expect.poll(() => app.requests.filter(r => r.method === 'codex.draft.open').at(-1)?.params.cwd).toBe('/other');
  await page.screenshot({ path: testInfo.outputPath('codex-unified-first-screen.png') });
  const otherTrigger = page.getByRole('button', {
    name: 'Choose project, current project other', exact: true,
  });
  await otherTrigger.click();
  await picker.getByRole('button', { name: 'New project', exact: true }).click();
  const addProject = page.getByRole('dialog', { name: 'Add a project' });
  await expect(addProject).toBeVisible();
  await addProject.getByRole('button', { name: 'Close project picker' }).click();
  await expect(addProject).toBeHidden();
  await page.locator('#task').fill('Check the selected project');
  await page.locator('#send').click();
  await expect.poll(() => app.requests.find(r => r.method === 'codex.thread.start')?.params.cwd).toBe('/other');
  await expect(page.getByRole('button', { name: /^Choose project, current project/ })).toHaveCount(0);
  expect(app.pageErrors).toEqual([]);
});
