import { test, expect, sidebarMode } from './support/test.js';
import { CloudHarness, sessionA } from './support/cloud_harness.js';

// The model tests cover where each switch lands; this covers what only the
// browser shows: history entries and composer drafts back in the DOM.
test('the Chat/Work switch restores each mode’s conversation and draft', async ({ page }) => {
  const cloud = new CloudHarness(page);
  cloud.meStatus = 200;
  await cloud.install();
  await cloud.goto();
  await cloud.open();
  const title = page.locator('main .topbar-title');
  const task = page.locator('#task');
  const cloudURL = page.url();
  await task.fill('Cloud draft');

  await sidebarMode(page, 'Work').click();
  await expect(page).toHaveURL(/\/device\/device-a\/chat\/new$/);
  const local = page.getByRole('button', { name: 'Rabbita browser fixture', exact: true });
  await local.click();
  await expect(page.locator('#transcript').getByText('Browser result', { exact: true })).toBeVisible();
  const workURL = page.url();
  await task.fill('Local draft');

  await sidebarMode(page, 'Chat').click();
  await expect(page).toHaveURL(cloudURL);
  await expect(title).toHaveText(cloud.titles.get(sessionA));
  await expect(task).toHaveValue('Cloud draft');

  await sidebarMode(page, 'Work').click();
  await expect(page).toHaveURL(workURL);
  await expect(local).toHaveAttribute('aria-current', 'true');
  await expect(task).toHaveValue('Local draft');

  // Each switch is a visit, and the list follows the page Back returns to.
  await page.goBack();
  await expect(page).toHaveURL(cloudURL);
  await expect(sidebarMode(page, 'Chat')).toHaveAttribute('aria-pressed', 'true');
  await expect(task).toHaveValue('Cloud draft');
  expect(cloud.postCount).toBe(0);
  expect(cloud.device.pageErrors).toEqual([]);
});
