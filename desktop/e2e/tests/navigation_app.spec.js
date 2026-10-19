import { test, expect } from '@playwright/test';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';

const back = page => page.getByRole('button', { name: 'Back', exact: true });
const forward = page => page.getByRole('button', { name: 'Forward', exact: true });
const heading = page => page.locator('main > .topbar h1');

test('application history restores draft content and drops the forward branch on a new visit', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  await app.install(); await app.goto();
  await expect(back(page)).toBeDisabled();
  await page.locator('#task').fill('Keep this unsent draft');
  await page.getByRole('button', { name: 'Settings', exact: true }).click();
  await page.getByRole('button', { name: 'Skills', exact: true }).click();
  await back(page).click(); await expect(heading(page)).toHaveText('Settings');
  await back(page).click(); await expect(page.locator('#task')).toHaveValue('Keep this unsent draft');
  await expect(back(page)).toBeDisabled();
  await forward(page).click(); await expect(heading(page)).toHaveText('Settings');
  await page.getByRole('button', { name: 'Scheduled', exact: true }).click();
  await expect(forward(page)).toBeDisabled();
  expect(app.pageErrors).toEqual([]);
});

test('application history keeps a submitted draft reachable without an extra predecessor', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  await app.install(); await app.goto();
  await page.locator('#task').fill('Send this retained draft');
  await page.getByRole('button', { name: 'Settings', exact: true }).click();
  await back(page).click();
  await expect(page.locator('#task')).toHaveValue('Send this retained draft');
  await page.locator('#send').click();
  await expect(page.locator('#task')).toHaveValue('');
  await expect.poll(() => app.requests.find(request => request.method === 'agent.start')?.params.task).toBe('Send this retained draft');
  const session = await page.locator('#transcript').getAttribute('data-transcript-session');
  await expect(back(page)).toBeDisabled();
  await forward(page).click(); await expect(heading(page)).toHaveText('Settings');
  await back(page).click();
  await expect(page.locator('#transcript')).toHaveAttribute('data-transcript-session', session);
  await expect(page.getByText('Browser result', { exact: true })).toBeVisible();
  await expect(back(page)).toBeDisabled();
  expect(app.pageErrors).toEqual([]);
});

test('navigation remains reachable in narrow and native titlebars', async ({ page }, testInfo) => {
  const app = new DesktopBrowserHarness(page);
  await app.install(); await app.goto();
  await page.getByRole('button', { name: 'Settings', exact: true }).click();
  for (const width of [1440, 390]) {
    await page.setViewportSize({ width, height: 844 });
    await expect(back(page)).toBeInViewport(); await expect(forward(page)).toBeInViewport();
    const bounds = await Promise.all([page.locator('.sidebar-toggle'), back(page), forward(page)].map(el => el.boundingBox()));
    expect(bounds[0].x + bounds[0].width).toBeLessThanOrEqual(bounds[1].x);
    expect(bounds[1].x + bounds[1].width).toBeLessThanOrEqual(bounds[2].x);
    await page.screenshot({ path: testInfo.outputPath(`navigation-${width}.png`) });
  }
  await page.setViewportSize({ width: 1440, height: 844 });
  // Returning from mobile reopens the sidebar. Measure the native inset
  // only after the wide shell has rendered and its opening motion settles.
  await expect(page.locator('.sidebar-backdrop')).toHaveCount(0);
  await expect.poll(() => page.locator('.app').evaluate(node => node.getAnimations().length)).toBe(0);
  await page.evaluate(() => {
    document.documentElement.style.setProperty('--native-titlebar-left', '84px');
    document.documentElement.style.setProperty('--native-titlebar-height', '28px');
    document.querySelector('.app').style.setProperty('--sidebar-width', '220px');
  });
  const toggle = await page.locator('.sidebar-toggle').boundingBox();
  const backBounds = await back(page).boundingBox();
  const forwardBounds = await forward(page).boundingBox();
  const mode = await page.locator('.sidebar-mode').boundingBox();
  expect(toggle.x).toBeGreaterThanOrEqual(84);
  expect(toggle.x + toggle.width).toBeLessThanOrEqual(backBounds.x);
  expect(backBounds.x + backBounds.width).toBeLessThanOrEqual(forwardBounds.x);
  expect(mode.x).toBeGreaterThanOrEqual(forwardBounds.x + forwardBounds.width);
  const sidebar = await page.locator('aside').boundingBox();
  expect(mode.x + mode.width).toBeLessThanOrEqual(sidebar.x + sidebar.width);
  await page.screenshot({ path: testInfo.outputPath('navigation-native-geometry.png') });
  expect(app.pageErrors).toEqual([]);
});
