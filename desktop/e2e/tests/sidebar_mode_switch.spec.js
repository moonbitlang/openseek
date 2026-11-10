import { test, expect } from './support/test.js';
import { CloudHarness, authOrigin, sessionA } from './support/cloud_harness.js';

const sidebarMode = (page, name) => page.getByRole('group', { name: 'Sidebar list' }).getByRole('button', { name, exact: true });

test('the Chat/Work switch moves the main column and restores each mode’s conversation', async ({ page }) => {
  const cloud = new CloudHarness(page);
  cloud.meStatus = 200;
  await cloud.install();
  await cloud.goto();
  await cloud.open();
  const title = page.locator('main .topbar-title');
  const task = page.locator('#task');
  const cloudURL = page.url();
  await task.fill('Cloud draft');
  // Picking the mode already on screen keeps the column.
  await sidebarMode(page, 'Chat').click();
  await expect(page).toHaveURL(cloudURL);

  await sidebarMode(page, 'Work').click();
  await expect(page).toHaveURL(/\/device\/device-a\/chat\/new$/);
  await expect(title).not.toHaveText(cloud.titles.get(sessionA));
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

test('a blank device start page reopens in Chat when Chat was the last mode', async ({ page }) => {
  const cloud = new CloudHarness(page);
  cloud.meStatus = 200;
  await cloud.install();
  await page.addInitScript(() => localStorage.setItem('openseek.sidebar_mode', 'chat'));
  await page.goto(`${authOrigin}/console/index.html?device=device-a`);
  await expect(page).toHaveURL(/\/cloud$/);
  await expect(sidebarMode(page, 'Chat')).toHaveAttribute('aria-pressed', 'true');
  await expect(cloud.row(sessionA)).toBeVisible();

  // A start page that names a conversation keeps it.
  await page.goto(`${authOrigin}/device/device-a/chat/session/session-1`);
  await expect(page.getByRole('button', { name: 'Rabbita browser fixture', exact: true })).toHaveAttribute('aria-current', 'true');
  await expect(page).toHaveURL(/\/device\/device-a\/chat\/session\/session-1$/);
  expect(cloud.device.pageErrors).toEqual([]);
});

test('the phone drawer stays open on the list the switch picked', async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  const cloud = new CloudHarness(page);
  cloud.meStatus = 200;
  await cloud.install();
  await page.goto(`${authOrigin}/console/index.html?device=device-a`);
  await page.locator('.sidebar-toggle').click();
  await expect(page.locator('.sidebar-backdrop')).toHaveClass(/open/);
  await sidebarMode(page, 'Chat').click();
  await expect(page).toHaveURL(/\/cloud$/);
  await expect(cloud.row(sessionA)).toBeVisible();
  await sidebarMode(page, 'Work').click();
  await expect(page).toHaveURL(/\/device\/device-a\/chat\/new$/);
  await expect(page.getByRole('button', { name: 'Rabbita browser fixture', exact: true })).toBeVisible();
  await expect(page.locator('.sidebar-backdrop')).toHaveClass(/open/);
  expect(cloud.device.pageErrors).toEqual([]);
});
