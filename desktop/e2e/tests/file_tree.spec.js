import { test, expect } from '@playwright/test';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';

test('file tree keeps compact aligned rows and continuous ancestor guides', async ({ page }, testInfo) => {
  const app = new DesktopBrowserHarness(page);
  app.directoryEntries['/workspace'] = [
    { name: 'production', is_dir: true },
    { name: 'staging', is_dir: true },
    { name: 'README.md', is_dir: false },
  ];
  app.directoryEntries['/workspace/production'] = [{ name: '.env', is_dir: false }];
  app.directoryEntries['/workspace/staging'] = [
    { name: 'deploy', is_dir: true },
    { name: '.env', is_dir: false },
    { name: 'docker-compose.yml', is_dir: false },
  ];
  const longName = 'a_very_long_deployment_configuration_name_that_does_not_fit.mbt';
  app.directoryEntries['/workspace/staging/deploy'] = [{ name: longName, is_dir: false }];
  app.workingFiles['staging/.env'] = 'ENV=staging\n';
  await app.install();
  await app.goto();
  await app.openSession();
  await page.getByRole('button', { name: 'Hide sidebar', exact: true }).click();
  await app.openReview();
  await page.getByRole('tab', { name: 'Files', exact: true }).click();
  const tree = page.locator('.workspace-file-list');
  const production = tree.locator('[data-path="production"]');
  const staging = tree.locator('[data-path="staging"]');
  await production.click();
  await staging.click();
  const deploy = tree.locator('[data-path="staging/deploy"]');
  await deploy.click();
  const env = tree.locator('[data-path="staging/.env"]');
  const nested = tree.locator(`[data-path="staging/deploy/${longName}"]`);
  const readme = tree.locator('[data-path="README.md"]');
  await expect(nested).toBeVisible();
  for (const row of [production, staging, deploy, env, nested, readme]) {
    expect((await row.boundingBox()).height).toBe(24);
  }
  expect((await production.boundingBox()).x - (await tree.boundingBox()).x).toBe(4);
  // Files reserve the same icon slot as directories, so peers align.
  expect((await readme.locator('.tree-name').boundingBox()).x)
    .toBe((await production.locator('.tree-name').boundingBox()).x);
  expect((await env.locator('.tree-name').boundingBox()).x)
    .toBe((await deploy.locator('.tree-name').boundingBox()).x);
  expect((await nested.locator('.tree-name').boundingBox()).x - (await env.locator('.tree-name').boundingBox()).x)
    .toBe(14);
  await expect(env.locator('.tree-twistie svg')).toHaveCount(0);
  await expect(deploy.locator('.tree-twistie svg')).toBeVisible();
  expect((await env.locator('.tree-indent-guides').boundingBox()).width).toBe(14);
  expect((await nested.locator('.tree-indent-guides').boundingBox()).width).toBe(28);
  expect((await readme.locator('.tree-indent-guides').boundingBox()).width).toBe(0);
  const parentGuide = await deploy.locator('.tree-indent-guides').boundingBox();
  const nestedGuide = await nested.locator('.tree-indent-guides').boundingBox();
  expect(parentGuide.y + parentGuide.height).toBe(nestedGuide.y);
  expect(parentGuide.x).toBe(nestedGuide.x);
  const rootChevron = await production.locator('.tree-twistie').boundingBox();
  expect(parentGuide.x).toBe(rootChevron.x + rootChevron.width / 2);
  for (const colorScheme of ['light', 'dark']) {
    await page.emulateMedia({ colorScheme });
    const textColor = await page.locator('body')
      .evaluate(element => getComputedStyle(element).color);
    await expect(env).toHaveCSS('color', textColor);
    expect(await env.locator('.tree-indent-guides').evaluate(element => getComputedStyle(element).backgroundImage))
      .not.toBe('none');
    await page.locator('.file-tree-pane').screenshot({ path: testInfo.outputPath(`files-${colorScheme}.png`) });
  }
  await env.click();
  await expect(env).toHaveClass(/selected/);
  await expect(page.locator('.editor-tabs .editor-tab.active')).toContainText('.env');
  // Resizing preserves directory expansion and the selected file.
  await page.getByRole('button', { name: 'Expand panel', exact: true }).click();
  await expect(nested).toBeVisible();
  await expect(env).toHaveClass(/selected/);
  await expect(staging).toHaveAttribute('aria-expanded', 'true');
  await staging.click();
  await expect(nested).toBeHidden();
  await expect(staging).toHaveAttribute('aria-expanded', 'false');
  await staging.click();
  await expect(nested).toBeVisible();
  // Open Editors and the header migration are deliberately absent from this PR.
  await expect(page.locator('.open-editors')).toHaveCount(0);
  expect(app.pageErrors).toEqual([]);
});

test('Files scrolls below the view tabs and keeps narrow-screen touch targets', async ({ page }, testInfo) => {
  const app = new DesktopBrowserHarness(page);
  app.directoryEntries['/workspace'] = Array.from({ length: 80 }, (_, index) => ({
    name: `file_${String(index).padStart(2, '0')}_with_a_very_long_deployment_configuration_name_for_truncation.mbt`,
    is_dir: false,
  }));
  await app.install();
  await app.goto();
  await app.openSession();
  await page.getByRole('button', { name: 'Hide sidebar', exact: true }).click();
  await app.openReview();
  const tabs = page.getByRole('tablist', { name: 'Explorer views' });
  await tabs.getByRole('tab', { name: 'Files', exact: true }).click();
  const tree = page.locator('.workspace-file-list');
  // The first row starts directly below the view tabs, without a second title.
  expect((await tree.locator('.tree-file').first().boundingBox()).y - (await tree.boundingBox()).y).toBe(4);
  const tabsBefore = await tabs.boundingBox();
  await tree.locator('.tree-file').last().scrollIntoViewIfNeeded();
  expect(await tree.evaluate(element => element.scrollTop)).toBeGreaterThan(0);
  expect(await tabs.boundingBox()).toEqual(tabsBefore);
  await tabs.getByRole('tab', { name: 'Search', exact: true }).click();
  await expect(page.getByRole('textbox', { name: 'Search', exact: true })).toBeVisible();
  await expect(tree).toHaveCount(0);
  await tabs.getByRole('tab', { name: 'Files', exact: true }).click();
  await page.setViewportSize({ width: 390, height: 760 });
  await expect(tree).toBeVisible();
  expect((await tree.locator('.tree-file').first().boundingBox()).height).toBe(44);
  expect(await tree.evaluate(element => element.scrollWidth <= element.clientWidth)).toBe(true);
  await expect.poll(() => tree.locator('.tree-name').first().evaluate(element => element.scrollWidth > element.clientWidth)).toBe(true);
  await page.locator('.file-tree-pane').screenshot({ path: testInfo.outputPath('files-narrow.png') });
  expect(app.pageErrors).toEqual([]);
});
