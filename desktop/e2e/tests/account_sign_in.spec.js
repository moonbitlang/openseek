import { test, expect } from './support/test.js';
import { CloudHarness } from './support/cloud_harness.js';

for (const entry of ['sidebar', 'Settings']) {
  test(`desktop sign-in from ${entry} stays cancellable and permits a fresh attempt`, async ({ page }) => {
    const cloud = new CloudHarness(page, { desktop: true, cached: false });
    cloud.authorization = Promise.withResolvers();
    const cancellation = Promise.withResolvers();
    cloud.pauseAuthorizationCancel = cancellation.promise;
    await cloud.install();
    await cloud.goto();
    const sidebar = page.locator('.console-account');
    const settings = page.getByRole('dialog', { name: 'Settings', exact: true });
    const account = page.getByRole('region', { name: 'Account', exact: true });
    if (entry === 'Settings') {
      await page.getByRole('button', { name: 'Settings', exact: true }).click();
      await page.getByRole('tab', { name: 'Account', exact: true }).click();
    }
    const signIn = entry === 'sidebar'
      ? sidebar.and(page.getByRole('button', { name: 'Sign in', exact: true }))
      : account.getByRole('button', { name: 'Sign in', exact: true });
    const cancel = entry === 'sidebar'
      ? sidebar.and(page.getByRole('button', { name: 'Cancel sign-in', exact: true }))
      : account.getByRole('button', { name: 'Cancel', exact: true });

    await signIn.click();
    await expect(cancel).toBeEnabled();
    if (entry === 'sidebar') await expect(settings).not.toBeVisible();
    expect(cloud.hostRequests.filter(request => request.method === 'auth.connect')).toHaveLength(1);

    await cancel.click();
    await expect(cancel).toBeDisabled();
    await expect.poll(() => cloud.hostRequests.filter(request => request.method === 'auth.cancel').length).toBe(1);
    cancellation.resolve();
    await expect(signIn).toBeEnabled();
    await expect(page.getByText('the sign-in was cancelled', { exact: true })).toHaveCount(0);

    cloud.authorization = Promise.withResolvers();
    await signIn.click();
    await expect(cancel).toBeEnabled();
    expect(cloud.hostRequests.filter(request => request.method === 'auth.connect')).toHaveLength(2);
    cloud.authorization.resolve();
    await expect(sidebar).toHaveText('octocat');
    if (entry === 'sidebar') await sidebar.click();
    await expect(account.getByRole('button', { name: 'Sign out', exact: true })).toBeVisible();
    expect(await page.evaluate(() => window.cloudUnhandledRejections)).toEqual([]);
  });
}

for (const locale of ['en', 'zh-Hans']) {
  test(`desktop sign-in timeout is actionable in ${locale}`, async ({ page }) => {
    const chinese = locale === 'zh-Hans';
    const cloud = new CloudHarness(page, { desktop: true, cached: false });
    cloud.authorizationError = 'sign-in timed out waiting for the browser';
    await cloud.install();
    await cloud.goto();
    await page.getByRole('button', { name: 'Settings', exact: true }).click();
    if (chinese) {
      await page.locator('#language-select').click();
      await page.getByRole('option', { name: '简体中文', exact: true }).click();
    }
    const accountName = chinese ? '账户' : 'Account';
    await page.getByRole('tab', { name: accountName, exact: true }).click();
    const home = page.getByRole('region', { name: accountName, exact: true });
    const signIn = home.getByRole('button', { name: chinese ? '登录' : 'Sign in', exact: true });
    await signIn.click();
    await expect(home).toContainText(chinese ? '登录未完成，请重试。' : "Sign-in wasn't completed. Try again.");
    await expect(signIn).toBeEnabled();
    cloud.authorizationError = null;
    await signIn.click();
    await expect(home.getByRole('button', { name: chinese ? '退出登录' : 'Sign out', exact: true })).toBeVisible();
    expect(cloud.hostRequests.filter(request => request.method === 'auth.connect')).toHaveLength(2);
  });
}
