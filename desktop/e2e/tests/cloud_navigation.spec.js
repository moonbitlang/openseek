import { test, expect } from './support/test.js';
import { CloudHarness, authOrigin, sessionA } from './support/cloud_harness.js';

const sessionURL = id => `${authOrigin}/cloud/session/${id}`;
const creations = cloud => cloud.requests.filter(r => r.side === 'cloud' && r.path === '/v1/sessions' && r.method === 'POST');

test('Cloud session direct access and refresh do not depend on catalog membership or a device', async ({ page }) => {
  const cloud = new CloudHarness(page);
  cloud.sessionIds = [];
  cloud.histories.set(sessionA, { messages: [{ id: 1, task_id: 'old-task', kind: 'assistant_message', data: { content: 'Deep linked history' }, created_at: 1000 }], generating: false, outcome: null });
  await cloud.install();
  await page.goto(sessionURL(sessionA));
  await expect(page.locator('#transcript')).toContainText('Deep linked history');
  await expect(page.locator('#task')).toBeDisabled();
  cloud.sessionIds = [sessionA];
  await page.reload();
  await expect(page.locator('#task')).toBeEnabled();
  await page.locator('#task').fill('Temporary draft');
  await page.reload();
  await expect(page.locator('#transcript')).toContainText('Deep linked history');
  await expect(page.locator('#task')).toHaveValue('');
  expect(creations(cloud)).toEqual([]);
  expect(cloud.device.ticketRequests).toHaveLength(0);
  expect(cloud.device.pageErrors).toEqual([]);
});

test('Cloud login returns to the exact deep link without creating a session', async ({ page }) => {
  const cloud = new CloudHarness(page, { cached: false });
  await cloud.install();
  const destination = `${sessionURL(sessionA)}?source=shared`;
  await page.goto(destination);
  const login = page.locator('.cloud-home').getByRole('button', { name: 'Sign in', exact: true });
  await expect(login).toBeVisible();
  const request = page.waitForRequest(request => new URL(request.url()).pathname === '/v2/auth/login');
  await login.click();
  expect(new URL((await request).url()).searchParams.get('return_to')).toBe(`/cloud/session/${sessionA}?source=shared`);
  await expect(page).toHaveURL(destination);
  await expect(page.locator('#task')).toBeVisible();
  expect(creations(cloud)).toEqual([]);
  expect(cloud.device.pageErrors).toEqual([]);
});

