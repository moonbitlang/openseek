import { test, expect } from '@playwright/test';
import { CloudHarness, authOrigin, sessionA } from './support/cloud_harness.js';

const cloudFollowupKey = 'openseek.cloud_followup_behavior';

async function showSidebar(page) {
  if (!await page.getByRole('button', { name: 'Settings', exact: true }).isVisible()) {
    await page.locator('.sidebar-toggle').click();
  }
}

async function settings(page) {
  await showSidebar(page);
  await page.getByRole('button', { name: 'Settings', exact: true }).click();
  await expect(page.locator('main > .topbar h1')).toHaveText('Settings');
}

async function chooseFollowup(page, label) {
  const control = page.getByRole('button', { name: 'Follow-up messages', exact: true });
  await expect(control).toBeEnabled();
  await control.click();
  await page.getByRole('option', { name: label, exact: true }).click();
  await expect(control).toContainText(label);
}

for (const width of [1440, 393]) {
  test(`device-less Cloud keeps useful browser settings and a sidebar after loading saved Work mode at ${width}px`, async ({ page }, testInfo) => {
    await page.setViewportSize({ width, height: 900 });
    const cloud = new CloudHarness(page);
    await page.addInitScript(() => localStorage.setItem('openseek.sidebar_mode', 'work'));
    await cloud.install();
    await page.goto(`${authOrigin}/cloud`);
    await showSidebar(page);
    await expect(cloud.row(sessionA)).toBeVisible();
    await expect(page.getByRole('button', { name: 'Chat', exact: true })).toHaveAttribute('aria-pressed', 'true');
    for (const name of ['Work', 'Skills', 'Scheduled']) {
      await expect(page.getByRole('button', { name, exact: true })).toHaveCount(0);
    }
    await expect(page.locator('aside').getByText('Local', { exact: true })).toHaveCount(0);
    await settings(page);
    await expect(page.locator('.settings-subtitle')).toHaveText('Preferences for this browser and your Cloud conversations.');
    for (const name of ['Engine', 'API', 'Codex']) {
      await expect(page.locator('.settings-group').getByRole('heading', { name, exact: true })).toHaveCount(0);
    }
    await expect(page.getByRole('button', { name: 'Follow-up messages', exact: true })).toBeEnabled();
    await expect(page.locator('.settings-group').getByRole('heading', { name: 'Account · Remote access', exact: true })).toBeVisible();
    await page.getByRole('button', { name: 'Theme', exact: true }).click();
    await page.getByRole('option', { name: 'Dark', exact: true }).click();
    await expect(page.locator('html')).toHaveAttribute('data-theme', 'dark');
    await page.reload();
    await showSidebar(page);
    await expect(cloud.row(sessionA)).toBeVisible();
    await expect(page.locator('html')).toHaveAttribute('data-theme', 'dark');
    await settings(page);
    await expect(page.getByRole('button', { name: 'Theme', exact: true })).toContainText('Dark');
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);
    const followup = await page.getByRole('button', { name: 'Follow-up messages', exact: true }).boundingBox();
    expect(followup.x).toBeGreaterThanOrEqual(0);
    expect(followup.x + followup.width).toBeLessThanOrEqual(width);
    await page.screenshot({ animations: 'disabled', path: testInfo.outputPath(`cloud-settings-${width}.png`) });
    expect(cloud.device.ticketRequests).toHaveLength(0);
    expect(cloud.device.pageErrors).toEqual([]);
  });
}

for (const [mode, label] of [['queue', 'Queue'], ['steer', 'Steer']]) {
  test(`device-less Cloud persists its ${label} default and sends the matching follow-up after reload`, async ({ page }) => {
    const cloud = new CloudHarness(page);
    cloud.manualTasks = true;
    await cloud.install();
    await page.goto(`${authOrigin}/cloud`);
    await expect(cloud.row(sessionA)).toBeVisible();
    await settings(page);
    if (mode === 'steer') await chooseFollowup(page, 'Queue');
    await chooseFollowup(page, label);
    await expect.poll(() => page.evaluate(key => localStorage.getItem(key), cloudFollowupKey)).toBe(mode);
    await page.reload();
    await expect(cloud.row(sessionA)).toBeVisible();
    await settings(page);
    await expect(page.getByRole('button', { name: 'Follow-up messages', exact: true })).toContainText(label);
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

test('a device-targeted browser keeps host settings and does not load or replace its Cloud follow-up preference', async ({ page }) => {
  const cloud = new CloudHarness(page);
  await page.addInitScript(key => localStorage.setItem(key, 'queue'), cloudFollowupKey);
  await cloud.install();
  await cloud.goto();
  for (const name of ['Work', 'Skills', 'Scheduled']) {
    await expect(page.getByRole('button', { name, exact: true })).toBeVisible();
  }
  await settings(page);
  for (const name of ['Engine', 'API', 'Codex']) {
    await expect(page.locator('.settings-group').getByRole('heading', { name, exact: true })).toBeVisible();
  }
  await expect(page.getByRole('button', { name: 'API endpoint', exact: true })).toBeEnabled();
  await expect(page.getByRole('button', { name: 'Follow-up messages', exact: true })).toContainText('Steer');
  await chooseFollowup(page, 'Queue');
  await expect.poll(() => cloud.device.hostSettings.followup_behavior).toBe('queue');
  await chooseFollowup(page, 'Steer');
  await expect.poll(() => cloud.device.hostSettings.followup_behavior).toBe('steer');
  expect(await page.evaluate(key => localStorage.getItem(key), cloudFollowupKey)).toBe('queue');
  expect(cloud.device.requests.some(request => request.method === 'settings.set')).toBe(true);
  expect(cloud.device.pageErrors).toEqual([]);
});
