import { test, expect } from '@playwright/test';
import { CloudHarness, authOrigin, sessionA } from './support/cloud_harness.js';

const cloudFollowupKey = 'openseek.cloud_followup_behavior';

function settingsDialog(page) {
  return page.getByRole('dialog', { name: 'Settings', exact: true });
}

async function openSettings(page) {
  await page.getByRole('button', { name: 'Settings', exact: true }).click();
  await expect(settingsDialog(page)).toBeVisible();
}

async function closeSettings(page) {
  await page.keyboard.press('Escape');
  await expect(settingsDialog(page)).not.toBeVisible();
}

async function chooseFollowup(page, label) {
  const control = settingsDialog(page).getByRole('button', { name: 'Follow-up messages', exact: true });
  await expect(control).toBeEnabled();
  await control.click();
  await page.getByRole('option', { name: label, exact: true }).click();
  await expect(control).toContainText(label);
}

for (const [mode, label] of [['queue', 'Queue'], ['steer', 'Steer']]) {
  test(`device-less Cloud persists its ${label} default and sends the matching follow-up after reload`, async ({ page }) => {
    const cloud = new CloudHarness(page);
    cloud.manualTasks = true;
    await cloud.install();
    await page.goto(`${authOrigin}/cloud`);
    await expect(cloud.row(sessionA)).toBeVisible();
    await openSettings(page);
    if (mode === 'steer') await chooseFollowup(page, 'Queue');
    await chooseFollowup(page, label);
    await expect.poll(() => page.evaluate(key => localStorage.getItem(key), cloudFollowupKey)).toBe(mode);
    await page.reload();
    await expect(cloud.row(sessionA)).toBeVisible();
    await openSettings(page);
    await expect(settingsDialog(page).getByRole('button', { name: 'Follow-up messages', exact: true })).toContainText(label);
    await closeSettings(page);
    await cloud.open();
    await page.locator('#task').fill('Start the Cloud turn');
    await page.locator('#send').click();
    await expect(page.locator('#stop')).toBeEnabled();
    await page.locator('#task').fill(`Follow up using ${mode}`);
    await expect(page.getByRole('button', { name: 'Follow-up action', exact: true })).toContainText(mode === 'queue' ? 'Queue next' : 'Steer now');
    await page.locator('#send').click();
    await expect.poll(() => cloud.requests.filter(request => {
      if (request.method !== 'POST') return false;
      const body = JSON.parse(request.body || '{}');
      return mode === 'queue' ? request.path.endsWith('/queue') && body.content === 'Follow up using queue'
        : request.path.endsWith('/commands') && body.command?.command === 'steer' && body.command.content === 'Follow up using steer';
    }).length).toBe(1);
    await expect(page.locator(mode === 'queue' ? '.queued-input-row' : '.pending-steer-row')).toContainText(`Follow up using ${mode}`);
    expect(cloud.postCount).toBe(1);
    expect(cloud.device.ticketRequests).toHaveLength(0);
    expect(cloud.device.pageErrors).toEqual([]);
  });
}

test('a device-targeted browser saves follow-ups to the host and leaves the Cloud preference alone', async ({ page }) => {
  const cloud = new CloudHarness(page);
  await page.addInitScript(key => localStorage.setItem(key, 'queue'), cloudFollowupKey);
  await cloud.install();
  await cloud.goto();
  await openSettings(page);
  await expect(settingsDialog(page).getByRole('button', { name: 'Follow-up messages', exact: true })).toContainText('Steer');
  await chooseFollowup(page, 'Queue');
  await expect.poll(() => cloud.device.hostSettings.followup_behavior).toBe('queue');
  await chooseFollowup(page, 'Steer');
  await expect.poll(() => cloud.device.hostSettings.followup_behavior).toBe('steer');
  expect(await page.evaluate(key => localStorage.getItem(key), cloudFollowupKey)).toBe('queue');
  expect(cloud.device.requests.some(request => request.method === 'settings.set')).toBe(true);
  expect(cloud.device.pageErrors).toEqual([]);
});
