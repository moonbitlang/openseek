import { test, expect } from '@playwright/test';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';

test('Chinese covers feature pages, composer and dock after live switching', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  await app.install();
  await app.goto();
  await app.openSession();
  await page.evaluate(() => {
    Object.defineProperty(navigator, 'languages', { configurable: true, value: ['zh-CN'] });
    window.dispatchEvent(new Event('languagechange'));
  });
  await expect(page.locator('#task')).toHaveAttribute('placeholder', '让 SeekMoon 检查、编辑或解释此工作区。');
  await expect(page.getByRole('button', { name: '发送', exact: true })).toBeVisible();
  await page.getByRole('button', { name: '显示面板', exact: true }).click();
  await expect(page.getByRole('button', { name: /搜索 在工作区中搜索文本/ })).toBeVisible();
  await page.getByRole('button', { name: '技能', exact: true }).click();
  await expect(page.getByRole('heading', { name: '技能', exact: true })).toBeVisible();
  await expect(page.getByPlaceholder('搜索技能…')).toBeVisible();
  await page.getByRole('button', { name: '定时任务', exact: true }).click();
  await expect(page.getByRole('heading', { name: '定时任务', exact: true })).toBeVisible();
  await page.getByRole('button', { name: '新建计划', exact: true }).click();
  await expect(page.getByText('超时时间（分钟）', { exact: true })).toBeVisible();
  await expect(page.getByRole('button', { name: '保存计划', exact: true })).toBeVisible();
  expect(app.pageErrors).toEqual([]);
});

test('language selection updates Settings and sidebar and persists across reload', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  await app.install();
  await app.goto();
  await page.getByRole('button', { name: 'Settings', exact: true }).click();
  await page.locator('#language-select').click();
  await page.getByRole('option', { name: '简体中文', exact: true }).click();
  await expect(page.locator('html')).toHaveAttribute('lang', 'zh-Hans');
  await expect(page.getByRole('heading', { name: '设置', exact: true })).toBeVisible();
  await expect(page.getByRole('button', { name: '技能', exact: true })).toBeVisible();
  await expect(page.getByRole('button', { name: '对话', exact: true })).toBeVisible();
  await expect(page.getByRole('button', { name: '项目', exact: true })).toBeVisible();
  await expect(page.getByRole('button', { name: '主题', exact: true })).toBeVisible();
  await expect(page.getByRole('button', { name: 'API 端点', exact: true })).toBeVisible();
  await expect(page.getByRole('button', { name: '保存 API 密钥', exact: true })).toBeVisible();
  await expect(page.getByRole('button', { name: '打开 config.toml', exact: true })).toBeVisible();
  await expect(page.getByText('保存在此设备上，仅随 API 请求发送。SeekMoon 不会读取它。')).toBeVisible();
  await expect.poll(() => page.evaluate(() => localStorage.getItem('openseek.language'))).toBe('zh-Hans');
  await page.reload();
  await expect(page.getByRole('button', { name: '设置', exact: true })).toBeVisible();
  await page.getByRole('button', { name: '设置', exact: true }).click();
  await page.locator('#language-select').click();
  await page.getByRole('option', { name: 'English', exact: true }).click();
  await expect(page.getByRole('heading', { name: 'Settings', exact: true })).toBeVisible();
  await expect(page.locator('html')).toHaveAttribute('lang', 'en');
  expect(app.pageErrors).toEqual([]);
});

test('system language updates an open palette without losing query, focus or selection', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  await app.install();
  await app.goto();
  await app.openSession();
  await app.openQuickOpen();
  const input = page.locator('#quick-open-input');
  await input.fill('main');
  const result = page.getByRole('option', { name: /main\.mbt/ });
  await expect(result).toHaveAttribute('aria-selected', 'true');
  await page.evaluate(() => {
    Object.defineProperty(navigator, 'languages', { configurable: true, value: ['zh-CN', 'en'] });
    window.dispatchEvent(new Event('languagechange'));
  });
  await expect(page.getByRole('dialog', { name: '搜索工作区文件' })).toBeVisible();
  await expect(input).toHaveValue('main');
  await expect(input).toBeFocused();
  await expect(result).toHaveAttribute('aria-selected', 'true');
  await input.dispatchEvent('compositionstart', { data: '中' });
  await input.dispatchEvent('keydown', { key: 'Enter', code: 'Enter', isComposing: true, bubbles: true });
  await expect(input).toBeVisible();
  await input.dispatchEvent('compositionend', { data: '中' });
  await input.fill('不存在的文件');
  await expect(page.getByRole('status').filter({ hasText: '未找到文件' })).toBeVisible();
  await input.fill('main');
  await expect(result).toBeVisible();
  await input.press('Enter');
  await expect(input).toBeHidden();
  await expect.poll(() => app.requests.some(request => request.method === 'fs.read_file' && request.params?.path === '/workspace/src/main.mbt')).toBe(true);
  await expect(page.getByLabel('只读代码查看器', { exact: true })).toBeVisible();
  await page.evaluate(() => {
    Object.defineProperty(navigator, 'languages', { configurable: true, value: ['en'] });
    window.dispatchEvent(new Event('languagechange'));
  });
  await expect(page.getByLabel('Readonly code viewer', { exact: true })).toBeVisible();
  expect(app.pageErrors).toEqual([]);
});

test('Chinese system preference resolves at startup and a failed save keeps the selected language', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  await app.install();
  await page.addInitScript(() => {
    Object.defineProperty(navigator, 'languages', { configurable: true, value: ['zh-Hans-CN'] });
  });
  await app.goto();
  await expect(page.getByRole('button', { name: '设置', exact: true })).toBeVisible();
  await page.getByRole('button', { name: '设置', exact: true }).click();
  await page.evaluate(() => {
    const original = Storage.prototype.setItem;
    Storage.prototype.setItem = function (key, value) {
      if (key === 'openseek.language') throw new DOMException('Storage denied', 'SecurityError');
      return original.call(this, key, value);
    };
  });
  await page.locator('#language-select').click();
  await page.getByRole('option', { name: 'English', exact: true }).click();
  await expect(page.getByRole('heading', { name: 'Settings', exact: true })).toBeVisible();
  await expect(page.getByText(/Could not access the language preference:/)).toBeVisible();
  await expect(page.locator('html')).toHaveAttribute('lang', 'en');
  expect(app.pageErrors).toEqual([]);
});
