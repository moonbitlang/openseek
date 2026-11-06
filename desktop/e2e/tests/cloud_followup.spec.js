import { test, expect } from '@playwright/test';
import { CloudHarness, authOrigin, sessionA } from './support/cloud_harness.js';

const cloudFollowupKey = 'openseek.cloud_followup_behavior';
const followup = page => page.getByRole('dialog', { name: 'Settings', exact: true })
  .getByRole('button', { name: 'Follow-up messages', exact: true });

async function chooseQueue(page) {
  await page.getByRole('button', { name: 'Settings', exact: true }).click();
  await followup(page).click();
  await page.getByRole('option', { name: 'Queue', exact: true }).click();
}

test('browser Cloud restores its follow-up preference after reload', async ({ page }) => {
  const cloud = new CloudHarness(page);
  cloud.manualTasks = true;
  await cloud.install();
  await page.goto(`${authOrigin}/cloud`);
  await expect(cloud.row(sessionA)).toBeVisible();
  await chooseQueue(page);
  await page.reload();
  await cloud.open();
  await page.locator('#task').fill('Start a turn');
  await page.locator('#send').click();
  await expect(page.locator('#stop')).toBeEnabled();
  await expect(page.getByRole('button', { name: 'Follow-up action', exact: true })).toContainText('Queue next');
  expect(cloud.device.requests.filter(request => request.method === 'settings.set')).toHaveLength(0);
});

test('a device-targeted browser keeps the Cloud preference separate from host settings', async ({ page }) => {
  const cloud = new CloudHarness(page);
  await page.addInitScript(key => localStorage.setItem(key, 'steer'), cloudFollowupKey);
  await cloud.install();
  await cloud.goto();
  await chooseQueue(page);
  await expect.poll(() => cloud.device.hostSettings.followup_behavior).toBe('queue');
  expect(await page.evaluate(key => localStorage.getItem(key), cloudFollowupKey)).toBe('steer');
});
