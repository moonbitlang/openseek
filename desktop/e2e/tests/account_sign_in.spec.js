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
    const openAccount = async () => {
      await page.getByRole('button', { name: 'Settings', exact: true }).click();
      await page.getByRole('tab', { name: 'Account', exact: true }).click();
    };
    const account = page.getByRole('region', { name: 'Account', exact: true });
    if (entry === 'Settings') await openAccount();
    else await page.locator('.console-account').click();
    const scope = account;
    const start = () => scope.getByRole('button', { name: 'Sign in', exact: true }).click();

    await start();
    await expect(scope).toContainText('Finish signing in in your browser…');
    const cancel = scope.getByRole('button', { name: 'Cancel', exact: true });
    await expect(cancel).toBeEnabled();
    expect(cloud.hostRequests.filter(request => request.method === 'auth.connect')).toHaveLength(1);
    await cancel.click();
    await expect(scope).toContainText('Cancelling');
    await expect(cancel).toBeDisabled();
    expect(cloud.hostRequests.filter(request => request.method === 'auth.connect')).toHaveLength(1);
    cancellation.resolve();
    await expect(scope.getByRole('button', { name: 'Sign in', exact: true })).toBeEnabled();
    await expect(page.getByText('the sign-in was cancelled', { exact: true })).toHaveCount(0);

    cloud.authorization = Promise.withResolvers();
    await start();
    await expect(scope).toContainText('Finish signing in in your browser…');
    expect(cloud.hostRequests.filter(request => request.method === 'auth.connect')).toHaveLength(2);
    cloud.authorization.resolve();
    await expect(account.getByRole('button', { name: 'Sign out', exact: true })).toBeVisible();
    expect(cloud.device.pageErrors).toEqual([]);
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
    expect(cloud.device.pageErrors).toEqual([]);
  });
}
