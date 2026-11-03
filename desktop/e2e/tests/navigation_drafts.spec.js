import { test, expect } from '@playwright/test';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';

test('returning to a Codex draft reloads skills and preserves structured mentions', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  app.codexModels = [{ id: 'gpt-test', displayName: 'Navigation Codex', isDefault: true }];
  const fallback = app.replyFor.bind(app);
  app.replyFor = request => request.method === 'codex.skills.list'
    ? { data: [{ cwd: '/workspace', skills: [{ name: 'review-pr', description: 'Review a pull request', path: '/skills/review-pr/SKILL.md', enabled: true }] }] }
    : fallback(request);
  await app.install(); await app.goto();
  await page.getByRole('button', { name: 'Model', exact: true }).click();
  await page.getByRole('option', { name: 'Navigation Codex', exact: true }).click();
  await expect(page).toHaveURL(/\/codex\/new$/);
  const composer = page.getByRole('textbox', { name: 'Ask Codex to inspect, edit, or explain this workspace.', exact: true });
  await composer.fill('$review');
  await page.getByText('Review a pull request', { exact: true }).click();
  await composer.fill('Review this change');
  await expect(page).toHaveURL(/\/codex\/draft\/[^/]+$/);
  const draft = page.url();
  await page.locator('.workspace-row').hover();
  await page.getByRole('button', { name: 'New conversation in this project', exact: true }).click();
  await expect(page).toHaveURL(/\/codex\/new$/);
  await expect(composer).toHaveValue('');
  await expect.poll(() => app.requests.filter(r => r.method === 'codex.skills.list').length).toBe(2);
  await page.goBack(); await expect(page).toHaveURL(draft);
  await expect(composer).toHaveValue('Review this change');
  await expect.poll(() => app.requests.filter(r => r.method === 'codex.skills.list').length).toBe(3);
  await composer.fill('$review');
  await expect(page.getByText('Review a pull request', { exact: true })).toBeVisible();
  await composer.fill('Review this change');
  await page.locator('#send').click();
  await expect.poll(() => app.requests.filter(r => r.method === 'codex.turn.start').length).toBe(1);
  expect(app.requests.find(r => r.method === 'codex.turn.start').params.input).toContainEqual({ type: 'skill', name: 'review-pr', path: '/skills/review-pr/SKILL.md' });
  expect(app.pageErrors).toEqual([]);
});

test('returning to a Codex draft restores its project for the next New chat', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  app.workspaces = ['/project-a', '/project-b'];
  app.codexModels = [{ id: 'gpt-test', displayName: 'Navigation Codex', isDefault: true }];
  await app.install(); await app.goto();
  await page.getByRole('button', { name: 'Model', exact: true }).click();
  await page.getByRole('option', { name: 'Navigation Codex', exact: true }).click();
  await expect(page).toHaveURL(/\/codex\/new$/);
  await page.getByRole('textbox', { name: 'Ask Codex to inspect, edit, or explain this workspace.', exact: true }).fill('Draft in project A');
  await expect(page).toHaveURL(/\/codex\/draft\/[^/]+$/);
  await expect(page.getByRole('button', { name: 'Send', exact: true })).toBeEnabled();
  const draft = page.url();
  const projectB = page.locator('.workspace-row', { hasText: 'project-b' });
  await projectB.hover();
  await projectB.getByRole('button', { name: 'New conversation in this project', exact: true }).click();
  await expect(page).toHaveURL(/\/codex\/new$/);
  await expect.poll(() => app.requests.filter(r => r.method === 'codex.draft.open').at(-1)?.params.cwd).toBe('/project-b');
  await page.goBack(); await expect(page).toHaveURL(draft);
  const shortcut = await page.evaluate(() => navigator.platform.includes('Mac') ? 'Meta+N' : 'Control+N');
  await page.keyboard.press(shortcut);
  await expect(page).toHaveURL(/\/codex\/new$/);
  await expect.poll(() => app.requests.filter(r => r.method === 'codex.draft.open').at(-1)?.params.cwd).toBe('/project-a');
  expect(app.pageErrors).toEqual([]);
});
