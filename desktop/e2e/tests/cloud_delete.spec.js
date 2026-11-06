import { test, expect } from './support/test.js';
import { CloudHarness, authOrigin, cloudOrigin, sessionA, sessionB, sessionC } from './support/cloud_harness.js';

async function menu(page, cloud, id) {
  await cloud.rowContainer(id).hover();
  await cloud.rowContainer(id).locator('[id$=":actions-trigger"]').click();
}

async function askDelete(page, cloud, id) {
  await menu(page, cloud, id);
  await page.locator('[role=menuitem][data-action=delete]:visible').click();
  await expect(page.locator('#delete-chat-confirm')).toBeVisible();
}

const deletes = cloud => cloud.requests.filter(request => request.method === 'DELETE');

{
  const desktop = false;

  test(`${desktop ? 'desktop' : 'browser'} deletes Cloud through the shared confirmation and stays in Chat`, async ({ page }) => {
    const cloud = new CloudHarness(page, { desktop });
    await cloud.install();
    await cloud.goto();
    await cloud.open();
    await page.locator('#task').fill('Draft that belongs to deleted A');
    await menu(page, cloud, sessionA);
    await expect(page.locator('[role=menuitem][data-action=rename]:visible')).toBeEnabled();
    await expect(page.locator('[role=menuitem][data-action=archive]:visible')).toBeEnabled();
    await page.locator('[role=menuitem][data-action=delete]:visible').click();
    await expect(page.locator('#delete-chat-dialog')).toContainText('Cloud fixture A');
    await expect(page.locator('#delete-chat-dialog')).not.toContainText('worktree');
    await page.locator('#delete-chat-cancel').click();
    expect(deletes(cloud)).toHaveLength(0);
    await expect(cloud.row(sessionA)).toBeVisible();
    await askDelete(page, cloud, sessionA);
    await page.locator('#delete-chat-confirm').click();
    await expect(cloud.row(sessionA)).toHaveCount(0);
    await expect(cloud.row(sessionC)).toHaveCount(0);
    await expect(page.locator('#task')).toHaveValue('');
    await expect(page.locator('main h1')).toHaveText('New chat');
    expect(deletes(cloud)).toHaveLength(1);
    expect(deletes(cloud)[0].path).toBe(`/v1/sessions/${sessionA}`);
    expect(deletes(cloud)[0].headers.authorization).toBe('Bearer ts_fixture-123');
    expect(cloud.device.requests.filter(request => request.method === 'session.delete')).toHaveLength(0);
    expect(cloud.device.pageErrors).toEqual([]);
  });
}

{
  const failure = 503;

  test(`delete ${failure} preserves the account, conversation and normal delete action`, async ({ page }) => {
    const cloud = new CloudHarness(page);
    cloud.deleteStatus = failure === 'network' ? 204 : failure;
    cloud.deleteOffline = failure === 'network';
    await cloud.install();
    await cloud.goto();
    await cloud.open();
    await page.locator('#task').fill('Preserve this draft');
    await askDelete(page, cloud, sessionA);
    await page.locator('#delete-chat-confirm').click();
    await expect(page.locator('aside')).toContainText(failure === 409 ? 'after it finishes' : failure === 503 ? 'HTTP 503' : 'unreachable');
    await expect(cloud.row(sessionA)).toHaveAttribute('aria-current', 'true');
    await expect(page.locator('#task')).toHaveValue('Preserve this draft');
    expect(await page.evaluate(() => localStorage.getItem('seekmoon.account.v1'))).toContain('ts_fixture-123');
    cloud.deleteStatus = 204;
    cloud.deleteOffline = false;
    await askDelete(page, cloud, sessionA);
    await page.locator('#delete-chat-confirm').click();
    await expect(cloud.row(sessionA)).toHaveCount(0);
    await expect(cloud.row(sessionC)).toHaveCount(0);
  });
}

test('delete 404 converges as already removed without signing out', async ({ page }) => {
  const cloud = new CloudHarness(page);
  cloud.deleteStatus = 404;
  await cloud.install();
  await cloud.goto();
  await cloud.open();
  await askDelete(page, cloud, sessionA);
  await page.locator('#delete-chat-confirm').click();
  await expect(cloud.row(sessionA)).toHaveCount(0);
  await expect(cloud.row(sessionC)).toHaveCount(0);
  expect(await page.evaluate(() => localStorage.getItem('seekmoon.account.v1'))).toContain('ts_fixture-123');
});

test('history 404 retires an externally removed conversation without creating a replacement', async ({ page }) => {
  const cloud = new CloudHarness(page);
  await cloud.install();
  await cloud.goto();
  await page.route(url => url.origin === cloudOrigin && url.pathname === `/v1/sessions/${sessionB}/messages`, route => route.fulfill({ status: 404, headers: { 'Access-Control-Allow-Origin': authOrigin } }));
  await cloud.row(sessionB).click();
  await expect(cloud.row(sessionB)).toHaveCount(0);
  await expect(cloud.row(sessionC)).toHaveCount(0);
  await expect(page.locator('.navigation-notice')).toContainText('no longer exists');
  await expect(page).toHaveURL(`${authOrigin}/cloud/session/${sessionB}`);
  expect(cloud.requests.filter(request => request.path === '/v1/sessions' && request.method === 'POST')).toHaveLength(0);
});

test('a history response captured before deletion cannot restore its row or content', async ({ page }) => {
  const cloud = new CloudHarness(page);
  cloud.histories.set(sessionA, { messages: [{ task_id: 'old', kind: 'assistant_message', data: { content: 'Deleted old content' }, created_at: 1 }], generating: false });
  let finish;
  cloud.pauseHistory = new Promise(resolve => { finish = resolve; });
  await cloud.install();
  await cloud.goto();
  await cloud.row(sessionA).click();
  await expect.poll(() => cloud.requests.filter(request => request.path.endsWith(`/${sessionA}/messages`)).length).toBe(1);
  await askDelete(page, cloud, sessionA);
  cloud.pauseHistory = null;
  await page.locator('#delete-chat-confirm').click();
  await expect(cloud.row(sessionC)).toHaveCount(0);
  finish();
  await expect(cloud.row(sessionA)).toHaveCount(0);
  await expect(page.locator('main')).not.toContainText('Deleted old content');
  await expect(cloud.row(sessionC)).toHaveCount(0);
});

test('device browser traversal reports deleted Cloud destinations as missing', async ({ page }) => {
  const cloud = new CloudHarness(page);
  await cloud.install(); await cloud.goto();
  const heading = page.locator('main > .topbar h1');
  const notice = page.locator('.navigation-notice');
  await cloud.open(sessionA); await cloud.open(sessionB);
  await askDelete(page, cloud, sessionA);
  await page.locator('#delete-chat-confirm').click();
  await expect(cloud.row(sessionA)).toHaveCount(0);
  await page.goBack();
  await expect(page).toHaveURL(`${authOrigin}/cloud/session/${sessionA}`);
  await expect(notice).toContainText('no longer exists');
  await page.goForward();
  await expect(notice).toHaveCount(0);
  await expect(heading).toHaveText('Cloud fixture B');
  expect(cloud.requests.filter(request => request.method === 'POST' && request.path === '/v1/sessions')).toHaveLength(0);
  expect(cloud.device.pageErrors).toEqual([]);
});
