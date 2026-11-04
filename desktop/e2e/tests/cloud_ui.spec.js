import { test, expect } from '@playwright/test';
import { CloudHarness, authOrigin, sessionA } from './support/cloud_harness.js';

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
    await expect(page.locator('.settings-subtitle')).toHaveCount(0);
    for (const name of ['Engine', 'API', 'Codex']) {
      await expect(page.locator('.settings-group').getByRole('heading', { name, exact: true })).toHaveCount(0);
    }
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

test('a device-targeted browser keeps its Work list and host settings', async ({ page }) => {
  const cloud = new CloudHarness(page);
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
  expect(cloud.device.pageErrors).toEqual([]);
});
