import { test, expect } from '@playwright/test';
import { mkdir } from 'node:fs/promises';
import { join } from 'node:path';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';

const answer = [
  '营收增长主要来自产品订阅，年度报告披露的同比增幅为 **12%**。[^1]',
  '这与收入明细表中的汇总一致；Excel 数据也可以作为独立来源引用。[^2]',
  '公开计算方法说明了同比增长率的计算方式。[^3] 年报中的口径说明适用于以上结论。[^1]',
  '[^1]: [年度报告.pdf](/workspace/reports/annual.pdf) — 第 12 页，营业收入。',
  '[^2]: [收入明细.xlsx](/workspace/reports/revenue.xlsx) — 收入表，B2:D8。',
  '[^3]: [增长率计算说明](https://example.test/growth) — 计算方法。',
].join('\n\n');

for (const minimal of [false, true]) {
  test(`${minimal ? 'minimal' : 'detailed'} answers render reusable citation numbers and open their sources`, async ({ page, context }) => {
    const app = new DesktopBrowserHarness(page);
    app.liveSessions[0].title = '文档分析与来源引用';
    app.sessionEvents = [
      { sequence: 1, item: { kind: 'user', payload: { content: '请对照年报和收入明细，说明今年的营收变化，并标注来源。' } } },
      { sequence: 2, item: { kind: 'assistant', payload: { content: answer } } },
    ];
    await page.addInitScript(minimal => {
      localStorage.setItem('openseek.minimal_transcript', String(minimal));
      localStorage.setItem('openseek.language', 'zh-Hans');
    }, minimal);
    await context.route('https://example.test/growth', route => route.fulfill({
      contentType: 'text/html', body: '<title>Growth calculation</title>',
    }));
    await app.install();
    await page.emulateMedia({ colorScheme: 'light' });
    await app.goto();
    await page.getByText('文档分析与来源引用', { exact: true }).first().click();
    const markdown = page.locator('#transcript .msg-content.markdown');
    await expect(markdown.locator('.citation')).toHaveText(['1', '2', '3', '1']);
    const sources = markdown.getByRole('group', { name: '来源', exact: true });
    await expect(sources).not.toHaveAttribute('open');
    await expect(sources.locator('.citation-source')).toHaveCount(3);
    await expect(sources.locator('.citation-source-list')).toBeHidden();
    await expect(sources.locator('.citation-source-number')).toHaveText(['1', '2', '3']);
    await expect(sources.locator('.citation-source-origin')).toHaveText(['PDF 文档', '电子表格', 'example.test']);
    await expect(sources).toContainText('第 12 页');
    await expect(sources).toContainText('B2:D8');
    expect(await markdown.evaluate(element => element.lastElementChild.className)).toBe('citation-sources');
    await expect(markdown.locator('.citation').first().locator('button')).toHaveAttribute('title', /来源 1: 年度报告.pdf/);

    // Capture the real packaged browser frontend with only demo conversation data.
    if (!minimal && process.env.OPENSEEK_UI_CAPTURE_DIR) {
      await mkdir(process.env.OPENSEEK_UI_CAPTURE_DIR, { recursive: true });
      await page.screenshot({ path: join(process.env.OPENSEEK_UI_CAPTURE_DIR, 'answer-citations-light.png') });
      await page.emulateMedia({ colorScheme: 'dark' });
      await expect(page.locator('#transcript')).toHaveAttribute('data-transcript-theme', 'dark');
      await page.screenshot({ path: join(process.env.OPENSEEK_UI_CAPTURE_DIR, 'answer-citations-dark.png') });
      await page.emulateMedia({ colorScheme: 'light' });
      await sources.locator('summary').click();
      await page.screenshot({ path: join(process.env.OPENSEEK_UI_CAPTURE_DIR, 'answer-citations-expanded.png') });
      await sources.locator('summary').click();
    }

    await markdown.locator('.citation').first().locator('button').click();
    await expect.poll(() => app.requests.filter(r => r.method === 'host.open_path').map(r => r.params.path))
      .toContain('/workspace/reports/annual.pdf');
    await expect(sources).not.toHaveAttribute('open');
    await sources.locator('summary').click();
    await expect(sources.locator('.citation-source-list')).toBeVisible();
    await page.locator('#task').fill('继续分析');
    await expect(sources).toHaveAttribute('open', '');
    await sources.locator('.citation-source[data-source="2"]').click();
    await expect.poll(() => app.requests.filter(r => r.method === 'host.open_path').map(r => r.params.path))
      .toContain('/workspace/reports/revenue.xlsx');
    const popupPromise = context.waitForEvent('page');
    await markdown.locator('.citation[data-citation="3"] a').click();
    const popup = await popupPromise;
    await expect(popup).toHaveURL('https://example.test/growth');
    await popup.close();

    await page.setViewportSize({ width: 760, height: 850 });
    const sizes = await sources.evaluate(element => ({ scroll: element.scrollWidth, client: element.clientWidth }));
    expect(sizes.scroll).toBeLessThanOrEqual(sizes.client + 1);
    expect(app.pageErrors).toEqual([]);
  });
}

test('streaming citations resolve when definitions arrive and survive message completion', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  app.sessionEvents = [
    { sequence: 1, item: { kind: 'user', payload: { content: 'Show the browser fixture citations' } } },
  ];
  await app.install();
  await app.goto();
  await app.openSession();
  const run = { run_id: 'citation-run', session: 'session-1' };
  app.notify('agent.started', {
    ...run, session_root: '/workspace/.openseek', model: 'deepseek-v4-pro', max_steps: 1000,
  });
  const live = page.locator('#transcript .msg.streaming');
  let content = 'The report supports this conclusion.[^1]';
  app.notify('agent.event', { ...run, event: { event: 'assistant_delta', content } });
  await expect(live).toContainText('conclusion');
  await expect(live.locator('.citation-sources')).toHaveCount(0);
  for (const delta of [
    '\n\n[^1]: [Report](https://example.test',
    '/report)',
    ' — p. 12.\n\nThe assumptions are consistent.[^1]',
  ]) {
    content += delta;
    app.notify('agent.event', { ...run, event: { event: 'assistant_delta', content: delta } });
    await expect(live).toContainText(delta.includes('assumptions') ? 'assumptions' : 'Report');
  }
  await expect(live.locator('.citation')).toHaveText(['1', '1']);
  await expect(live.locator('.citation-source')).toHaveCount(1);
  await expect(live.locator('.citation a').first()).toHaveAttribute('href', 'https://example.test/report');
  const sequence = 2;
  app.notify('session.event', {
    session: 'session-1', session_root: '/workspace/.openseek', sequence,
    event: { sequence, item: { kind: 'assistant', payload: { content } } },
  });
  app.notify('agent.event', { ...run, event: { event: 'assistant_message', content } });
  await expect(live).toHaveCount(0);
  await expect(page.locator('#transcript .citation')).toHaveText(['1', '1']);
  await expect(page.locator('#transcript .citation-source')).toHaveCount(1);
  expect(app.pageErrors).toEqual([]);
});

test('citation actions stay message-local and code, unused definitions, and unsafe URLs stay inert', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  app.sessionEvents = [
    { sequence: 1, item: { kind: 'user', payload: { content: 'Show the browser fixture citations' } } },
    { sequence: 2, item: { kind: 'assistant', payload: { content: 'First[^1]\n\n[^1]: [First file](/workspace/first.docx) — Results.' } } },
    { sequence: 3, item: { kind: 'assistant', payload: { content: [
      'Second[^1], a plain note[^2], and an unsafe link[^3]. `[^4]`',
      '```text\n[^4]\n```',
      '[^1]: [Second file](/workspace/second.mbt:42) — Calculation.',
      '[^2]: Context without a link.',
      '[^3]: [Blocked](javascript:alert%281%29)',
      '[^4]: [Unused](https://example.test/unused)',
    ].join('\n\n') } } },
  ];
  await app.install();
  await app.goto();
  await app.openSession();
  const messages = page.locator('#transcript .msg-content.markdown');
  await expect(messages).toHaveCount(2);
  await expect(messages.nth(0).locator('.citation-source')).toHaveCount(1);
  await expect(messages.nth(1).locator('.citation-source')).toHaveCount(3);
  await expect(messages.nth(1).locator('.citation[data-citation="2"] :is(a, button)')).toHaveCount(0);
  await expect(messages.nth(1).locator('.citation[data-citation="3"] :is(a, button)')).toHaveCount(0);
  await expect(messages.nth(1).locator('a[href^="javascript:"]')).toHaveCount(0);
  await expect(messages.nth(1).getByRole('link', { name: 'Unused', exact: true })).toHaveCount(0);
  await expect(messages.nth(1).locator('code').last()).toHaveText('[^4]');
  for (const [index, path] of [[0, '/workspace/first.docx'], [1, '/workspace/second.mbt:42']]) {
    await messages.nth(index).locator('.citation[data-citation="1"] button').click();
    await expect.poll(() => app.requests.filter(r => r.method === 'host.open_path').map(r => r.params.path)).toContain(path);
  }
  expect(app.pageErrors).toEqual([]);
});
