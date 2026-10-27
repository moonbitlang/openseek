import { test, expect } from '@playwright/test';
import { CloudHarness, cloudOrigin } from './support/cloud_harness.js';

const label = 'Help improve SeekMoon';
const endpoint = `${cloudOrigin}/v1/me/preferences`;
const toggle = page => page.getByRole('switch', { name: label, exact: true });
const accountPanel = page => page.locator('.settings-group', {
  has: page.getByRole('heading', { name: 'Account · Remote access', exact: true }),
});
async function openSettings(page) {
  await page.getByRole('button', { name: 'Settings', exact: true }).click();
}

test('account preferences load on opening Settings and save only the confirmed server value', async ({ page }, testInfo) => {
  const cloud = new CloudHarness(page);
  await cloud.install();
  const requests = [];
  let release;
  let response = true;
  await page.route(endpoint, async route => {
    const request = route.request();
    requests.push({ method: request.method(), body: request.postDataJSON(), token: request.headers().authorization });
    if (request.method() === 'PATCH') await new Promise(resolve => { release = resolve; });
    await route.fulfill({ json: { allow_content_improvement: response } });
  });
  await cloud.goto();
  expect(requests).toEqual([]);
  await openSettings(page);
  await expect(toggle(page)).toBeChecked();
  expect(requests).toEqual([{ method: 'GET', body: null, token: 'Bearer ts_fixture-123' }]);
  await expect(accountPanel(page)).toContainText('including existing history');
  await page.screenshot({ path: testInfo.outputPath('account-preferences.png') });
  await toggle(page).click();
  await expect(toggle(page)).toBeDisabled();
  await expect(toggle(page)).toBeChecked();
  await expect.poll(() => requests.length).toBe(2);
  expect(requests[1]).toEqual({ method: 'PATCH', body: { allow_content_improvement: false }, token: 'Bearer ts_fixture-123' });
  // The response is authoritative, even when it differs from the requested value.
  release();
  await expect(toggle(page)).toBeEnabled();
  await expect(toggle(page)).toBeChecked();
  await toggle(page).click();
  await expect.poll(() => requests.length).toBe(3);
  response = false;
  release();
  await expect(toggle(page)).not.toBeChecked();
  await expect(toggle(page)).toBeEnabled();
  await page.reload();
  await openSettings(page);
  await expect(toggle(page)).not.toBeChecked();
  expect(requests.filter(r => r.method === 'PATCH')).toHaveLength(2);
  expect(cloud.device.pageErrors).toEqual([]);
});

test('read failures and malformed responses never imply consent', async ({ page }) => {
  const cloud = new CloudHarness(page);
  await cloud.install();
  let result = { status: 500, json: {} };
  await page.route(endpoint, route => route.fulfill(result));
  await cloud.goto();
  for (const failure of [{ status: 500, json: {} }, { json: {} }, { json: { allow_content_improvement: 'false' } }]) {
    result = failure;
    await openSettings(page);
    await expect(accountPanel(page).getByRole('alert')).toContainText('Could not load account preferences');
    await expect(toggle(page)).toHaveCount(0);
    await page.getByRole('button', { name: 'Back', exact: true }).click();
  }
  result = { json: { allow_content_improvement: false } };
  await openSettings(page);
  await expect(toggle(page)).not.toBeChecked();
});

test('failed saves keep the confirmed value and do not retry automatically', async ({ page }) => {
  const cloud = new CloudHarness(page);
  await cloud.install();
  let writes = 0;
  let failure = 'http';
  await page.route(endpoint, async route => {
    if (route.request().method() === 'GET') return route.fulfill({ json: { allow_content_improvement: false } });
    writes++;
    if (failure === 'network') return route.abort('failed');
    if (failure === 'malformed') return route.fulfill({ json: {} });
    return route.fulfill({ status: 400, json: { error: 'Invalid preference' } });
  });
  await cloud.goto();
  await openSettings(page);
  for (const kind of ['http', 'network', 'malformed']) {
    failure = kind;
    await expect(toggle(page)).toBeEnabled();
    await toggle(page).click();
    await expect(accountPanel(page).getByRole('alert')).toContainText('Could not save account preferences');
    await expect(toggle(page)).not.toBeChecked();
    await expect(toggle(page)).toBeEnabled();
  }
  expect(writes).toBe(3);
  expect(cloud.device.pageErrors).toEqual([]);
});

for (const delayed of ['GET', 'PATCH']) {
  test(`account changes discard a delayed ${delayed} response, including returning to the original account`, async ({ page }) => {
    const cloud = new CloudHarness(page, { desktop: true });
    await cloud.install();
    let release;
    let pause = delayed === 'GET';
    await page.route(endpoint, async route => {
      if (pause && route.request().method() === delayed) {
        pause = false;
        await new Promise(resolve => { release = resolve; });
        return route.fulfill({ json: { allow_content_improvement: true } });
      }
      return route.fulfill({ json: { allow_content_improvement: false } });
    });
    await cloud.goto();
    await openSettings(page);
    if (delayed === 'PATCH') {
      await expect(toggle(page)).toBeEnabled();
      pause = true;
      await toggle(page).click();
    }
    await expect.poll(() => typeof release).toBe('function');
    const panel = accountPanel(page);
    for (const userId of ['456', '123']) {
      await panel.getByRole('button', { name: 'Sign out', exact: true }).click();
      await expect(toggle(page)).toHaveCount(0);
      cloud.userId = userId;
      await panel.getByRole('button', { name: 'Sign in', exact: true }).click();
      await expect(toggle(page)).toBeEnabled();
      await expect(toggle(page)).not.toBeChecked();
    }
    const finished = page.waitForResponse(response => response.url() === endpoint && response.request().method() === delayed);
    release();
    await (await finished).finished();
    await page.evaluate(() => new Promise(requestAnimationFrame));
    await expect(toggle(page)).not.toBeChecked();
    await expect(toggle(page)).toBeEnabled();
    expect(cloud.device.pageErrors).toEqual([]);
  });
}
