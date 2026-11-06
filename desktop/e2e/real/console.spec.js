import path from 'node:path';
import { test, expect } from './support/test.js';

// Flows against the real headless app-server and engine. Assert only what a
// user sees; the server, engine and model behind the page are real or
// scripted at the HTTP boundary.

// Only a rendered message counts: closed dialogs stay in the DOM, and the
// closed Skills page keeps the error from its startup fetch until it opens.
const connectionDown = page => page.getByText(/connection is down/i).filter({ visible: true });

test('startup connects and shows the project', async ({ page, workspace }) => {
  await page.goto('/device/host/chat');
  const name = path.basename(workspace);
  await expect(page.getByRole('button', { name: `Choose project, current project ${name}` })).toBeVisible();
  await expect(page.getByRole('complementary').getByRole('button', { name, exact: true })).toBeVisible();
  await expect(connectionDown(page)).toHaveCount(0);
});

test('a sent message shows the model reply', async ({ page, workspace, model }) => {
  model.reply('Scripted reply from the fixture model.');
  await page.goto('/device/host/chat');
  await expect(page.getByRole('button', { name: /^Choose project, current project / }))
    .toContainText(path.basename(workspace));
  const composer = page.getByRole('textbox', { name: /^Ask SeekMoon/ });
  await composer.fill('Say hello');
  await composer.press('Enter');
  const main = page.getByRole('main');
  await expect(main.getByText('Scripted reply from the fixture model.')).toBeVisible();
  await expect(main.getByText('Completed', { exact: true })).toBeVisible();
});

test('Skills opened right after load shows the library and catalog', async ({ page, workspace }) => {
  await page.goto('/device/host/chat');
  await page.getByRole('button', { name: 'Skills', exact: true }).click();
  const skills = page.getByRole('dialog', { name: 'Skills' });
  await expect(skills.getByRole('heading', { name: 'Installed' })).toBeVisible();
  // Checked once, not retried: the library is showing, so an error now is
  // one the user reads.
  expect(await connectionDown(page).count()).toBe(0);
  // The catalog comes from the real registry (mooncakes.io).
  await expect(skills.getByRole('heading', { name: 'Available' })).toBeVisible();
  await expect(skills.getByRole('button', { name: 'Install' }).first()).toBeVisible();
  expect(await connectionDown(page).count()).toBe(0);
});

test('a changed setting survives a reload', async ({ page, workspace, server }) => {
  // Host settings are shared by every test on this worker's server.
  await server.request('settings.set', { followup_behavior: 'steer' });
  await page.goto('/device/host/chat');
  await page.getByRole('button', { name: 'Settings', exact: true }).click();
  const followup = page.getByRole('button', { name: 'Follow-up messages' });
  await expect(followup).toHaveText('Steer');
  await followup.click();
  await page.getByRole('option', { name: 'Queue' }).click();
  await expect(followup).toHaveText('Queue');
  await page.reload();
  await page.getByRole('button', { name: 'Settings', exact: true }).click();
  await expect(page.getByRole('button', { name: 'Follow-up messages' })).toHaveText('Queue');
});
