import { test, expect } from './support/test.js';
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

test('account preferences load on opening Settings and save only the confirmed server value', async ({ page }) => {
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
