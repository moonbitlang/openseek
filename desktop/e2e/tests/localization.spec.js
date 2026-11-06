import { test, expect } from './support/test.js';
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
  await page.locator('#task').fill('检查工作区');
  await expect(page.locator('#send')).toBeVisible();
  await expect(page.locator('#send')).toHaveAccessibleName('发送');
  await page.locator('#task').fill('');
  await page.locator('#right-panel-toggle').click();
  await expect(page.locator('.dock-launcher-menu [data-dock-action="search"]')).toBeVisible();
  await expect(page.locator('.dock-launcher-menu [data-dock-action="search"]')).toHaveAccessibleName(/搜索 在工作区中搜索文本/);
  await page.locator('#sidebar-skills').click();
  await expect(page.locator('#management-dialog-title')).toBeVisible();
  await expect(page.locator('#management-dialog-title')).toHaveText('技能');
  const skills = page.locator('#management-dialog');
  const dismiss = skills.locator('[data-slot="dialog-close"]');
  await expect(dismiss).toBeVisible();
  await expect(dismiss).toHaveAccessibleName('关闭');
  await expect(dismiss).toHaveText('');
  await expect(page.locator('#skills-search')).toBeVisible();
  await expect(page.locator('#skills-search')).toHaveAttribute('placeholder', '搜索技能…');
  await dismiss.click();
  await page.locator('#sidebar-schedules').click();
  await expect(page.locator('#management-dialog-title')).toBeVisible();
  await expect(page.locator('#management-dialog-title')).toHaveText('定时任务');
  await page.getByTestId('schedule-new').click();
  await expect(page.locator('#schedule-timeout')).toBeVisible();
  await expect(page.locator('#schedule-timeout')).toHaveAccessibleName('超时时间（分钟）');
  await expect(page.getByTestId('schedule-save')).toBeVisible();
  await expect(page.getByTestId('schedule-save')).toHaveAccessibleName('保存计划');
  expect(app.pageErrors).toEqual([]);
});

test('language selection updates Settings and sidebar and persists across reload', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  await app.install();
  await app.goto();
  await page.locator('#sidebar-settings').click();
  await page.locator('#language-select').click();
  await page.locator('#language-select-menu [data-value="zh-Hans"]').click();
  await expect(page.locator('html')).toHaveAttribute('lang', 'zh-Hans');
  await expect(page.locator('#management-dialog-title')).toBeVisible();
  await expect(page.locator('#management-dialog-title')).toHaveText('设置');
  await expect(page.locator('#sidebar-skills')).toBeVisible();
  await expect(page.locator('#sidebar-skills')).toHaveAccessibleName('技能');
  await expect(page.locator('#sidebar-chat-mode')).toBeVisible();
  await expect(page.locator('#sidebar-chat-mode')).toHaveAccessibleName('对话');
  await expect(page.locator('[id="section:openseek.projects:remote.device-a:label"]')).toHaveText('项目');
  await expect(page.locator('#theme-select')).toBeVisible();
  await expect(page.locator('#theme-select')).toHaveAccessibleName('主题');
  await expect(page.locator('#settings-api-provider-select')).toBeVisible();
  await expect(page.locator('#settings-api-provider-select')).toHaveAccessibleName('API 端点');
  await expect(page.locator('#settings-api-save-key')).toBeVisible();
  await expect(page.locator('#settings-api-save-key')).toHaveAccessibleName('保存 API 密钥');
  await expect(page.locator('#codex-open-config')).toBeVisible();
  await expect(page.locator('#codex-open-config')).toHaveAccessibleName('打开 config.toml');
  await expect(page.locator('.setting-row').filter({ has: page.locator('#settings-api-save-key') }).locator('.setting-desc')).toHaveText('保存在此设备上，仅随 API 请求发送。SeekMoon 不会读取它。');
  await expect.poll(() => page.evaluate(() => localStorage.getItem('openseek.language'))).toBe('zh-Hans');
  await page.reload();
  await expect(page.locator('#sidebar-settings')).toBeVisible();
  await expect(page.locator('#sidebar-settings')).toHaveAccessibleName('设置');
  await page.locator('#sidebar-settings').click();
  await page.locator('#language-select').click();
  await page.locator('#language-select-menu [data-value="en"]').click();
  await expect(page.locator('#management-dialog-title')).toBeVisible();
  await expect(page.locator('#management-dialog-title')).toHaveText('Settings');
  await expect(page.locator('html')).toHaveAttribute('lang', 'en');
  expect(app.pageErrors).toEqual([]);
});

test('Chinese system preference resolves at startup and a failed save keeps the selected language', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  await app.install();
  await page.addInitScript(() => {
    Object.defineProperty(navigator, 'languages', { configurable: true, value: ['zh-Hans-CN'] });
  });
  await app.goto();
  await expect(page.locator('#sidebar-settings')).toBeVisible();
  await expect(page.locator('#sidebar-settings')).toHaveAccessibleName('设置');
  await page.locator('#sidebar-settings').click();
  await page.evaluate(() => {
    const original = Storage.prototype.setItem;
    Storage.prototype.setItem = function (key, value) {
      if (key === 'openseek.language') throw new DOMException('Storage denied', 'SecurityError');
      return original.call(this, key, value);
    };
  });
  await page.locator('#language-select').click();
  await page.locator('#language-select-menu [data-value="en"]').click();
  await expect(page.locator('#management-dialog-title')).toBeVisible();
  await expect(page.locator('#management-dialog-title')).toHaveText('Settings');
  await expect(page.locator('.notifications > .notification:visible')).toContainText([/Could not access the language preference:/]);
  await expect(page.locator('html')).toHaveAttribute('lang', 'en');
  expect(app.pageErrors).toEqual([]);
});

// Locale matching is covered by i18n/locale_test.mbt. One mounted flow covers
// IME, focus, selection and editor preservation; selection tests above/below
// still check the individual languages' visible labels.
test('system language switching preserves palette IME, focus and editor contents', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  await app.install();
  await app.goto();
  await app.openSession();
  await app.openQuickOpen();
  const input = page.locator('#quick-open-input');
  await input.fill('main');
  const result = page.locator('#quick-open-list [data-path="src/main.mbt"]');
  await expect(result).toHaveAttribute('aria-selected', 'true');
  await page.evaluate(() => {
    Object.defineProperty(navigator, 'languages', { configurable: true, value: ['fr', 'zh-HK', 'en'] });
    window.dispatchEvent(new Event('languagechange'));
  });
  await expect(page.locator('#quick-open-dialog')).toBeVisible();
  await expect(page.locator('#quick-open-dialog')).toHaveAccessibleName('搜尋工作區檔案');
  await expect(input).toHaveValue('main');
  await expect(input).toBeFocused();
  await expect(result).toHaveAttribute('aria-selected', 'true');
  await input.dispatchEvent('compositionstart', { data: '中' });
  await input.dispatchEvent('keydown', { key: 'Enter', code: 'Enter', isComposing: true, bubbles: true });
  await expect(input).toBeVisible();
  await input.dispatchEvent('compositionend', { data: '中' });
  await input.fill('不存在的檔案');
  await expect(page.locator('#quick-open-dialog').getByRole('status')).toBeVisible();
  await expect(page.locator('#quick-open-dialog').getByRole('status')).toHaveText('未找到檔案');
  await input.fill('main');
  await expect(result).toBeVisible();
  await input.press('Enter');
  await expect(input).toBeHidden();
  await expect.poll(() => app.requests.some(request => request.method === 'fs.read_file' && request.params?.path === '/workspace/src/main.mbt')).toBe(true);
  await expect(page.locator('#viewer-host').getByRole('region')).toBeVisible();
  await expect(page.locator('#viewer-host').getByRole('region')).toHaveAccessibleName('唯讀程式碼檢視器');
  const source = await page.locator('.view-lines').first().innerText();
  await page.evaluate(() => {
    Object.defineProperty(navigator, 'languages', { configurable: true, value: ['en'] });
    window.dispatchEvent(new Event('languagechange'));
  });
  await expect(page.locator('#viewer-host').getByRole('region')).toBeVisible();
  await expect(page.locator('#viewer-host').getByRole('region')).toHaveAccessibleName('Readonly code viewer');
  expect(await page.locator('.view-lines').first().innerText()).toBe(source);
  expect(app.pageErrors).toEqual([]);
});

test('Traditional Chinese system startup yields to an explicit saved choice', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  await app.install();
  await page.addInitScript(() => {
    Object.defineProperty(navigator, 'languages', { configurable: true, value: ['zh-Hant', 'en'] });
  });
  await app.goto();
  await expect(page.locator('html')).toHaveAttribute('lang', 'zh-Hant');
  await page.locator('#sidebar-settings').click();
  await page.locator('#language-select').click();
  await page.locator('#language-select-menu [data-value="zh-Hans"]').click();
  await expect(page.locator('html')).toHaveAttribute('lang', 'zh-Hans');
  await expect.poll(() => page.evaluate(() => localStorage.getItem('openseek.language'))).toBe('zh-Hans');
  await page.reload();
  await expect(page.locator('html')).toHaveAttribute('lang', 'zh-Hans');
  expect(app.pageErrors).toEqual([]);
});
