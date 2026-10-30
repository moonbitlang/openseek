import { test, expect } from '@playwright/test';
import { mkdirSync } from 'node:fs';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';

const spec = {
  version: 1, title: 'Weekly revenue', x_label: 'Week', y_label: 'Revenue / 收入（$k）', grid: true,
  series: [
    { label: 'Actual', x: [1, 2, 3, 4, 5], y: [12, 19, 16, 25, 31] },
    { label: 'Forecast', color: '#ea580c', x: [1, 2, 3, 4, 5], y: [10, 15, 20, 25, 30] },
  ],
};
const fence = value => '```mathplotlib\n' + JSON.stringify(value) + '\n```';
const evidence = process.env.OPENSEEK_PLOT_SCREENSHOTS;

const embed = (id, alt = 'Chart') => `![${alt}](artifact://${id})`;
const artifact = (id, spec) => ({ id, kind: 'mathplotlib', version: 1, spec });
function history(charts, answer = charts.map((_, i) => embed(`chart_${i}`)).join('\n\n')) {
  const events = [
    { sequence: 1, item: { kind: 'user', payload: { content: 'Show the browser fixture charts.' } } },
    { sequence: 2, item: { kind: 'assistant', payload: { content: '', tool_calls: charts.map((spec, i) => ({
      id: `plot_${i}`, name: 'mbtx', arguments: JSON.stringify({ filename: '@builtin/plot.mbtx', description: 'Plot data', args: [JSON.stringify(spec)] }),
    })) } } },
    ...charts.map((spec, i) => ({ sequence: i + 3, item: { kind: 'tool_result', payload: {
      tool_call_id: `plot_${i}`, tool_name: 'mbtx', is_error: false,
      content: JSON.stringify({ artifact_id: `chart_${i}`, embed: embed(`chart_${i}`) }),
      data: { artifacts: [artifact(`chart_${i}`, spec)] },
    } } })),
    { sequence: charts.length + 3, item: { kind: 'assistant', payload: { content: answer } } },
    { sequence: charts.length + 4, item: { kind: 'terminal', payload: { kind: 'finished', message: answer } } },
  ];
  return events;
}
function append(app, kind, payload) {
  const sequence = (app.sessionEvents.at(-1)?.sequence || 0) + 1;
  const event = { sequence, item: { kind, payload } };
  app.sessionEvents.push(event);
  app.notify('session.event', { session: 'session-1', session_root: '/workspace/.openseek', sequence, event });
}

async function dataPoint(chart) {
  return chart.locator('svg[data-moonplot-root]').evaluate(svg => {
    const points = svg.querySelector('polyline[stroke="#2563eb"]').getAttribute('points').trim().split(/\s+/);
    const [x, y] = points[1].split(',').map(Number);
    const point = svg.createSVGPoint(); point.x = x; point.y = y;
    const client = point.matrixTransform(svg.getScreenCTM());
    return { x: client.x, y: client.y };
  });
}

for (const minimal of [true, false]) {
  test(`builtin chart stays visible and interactive in ${minimal ? 'minimal' : 'detailed'} history`, async ({ page }) => {
    await page.addInitScript(value => localStorage.setItem('openseek.minimal_transcript', String(value)), minimal);
    const app = new DesktopBrowserHarness(page);
    app.sessionEvents = history([spec], 'Actual revenue exceeded the forecast in three weeks.\n\n' + embed('chart_0', 'Revenue comparison') + '\n\nWeek 5 had the highest revenue.');
    await app.install(); await app.goto(); await app.openSession();
    const chart = page.locator('#transcript .chat-plot');
    await expect(chart).toBeVisible();
    await expect(chart.locator('svg[data-moonplot-root]')).toHaveCount(1);
    await expect(chart.locator('canvas, img, iframe')).toHaveCount(0);
    await expect(chart.getByText('Interactive chart', { exact: true })).toHaveCount(0);
    await expect(chart.getByRole('button', { name: 'Clear selection', exact: true })).toHaveCount(0);
    await expect(chart.getByRole('status')).toHaveCount(0);
    await chart.scrollIntoViewIfNeeded();
    const point = await dataPoint(chart);
    await page.mouse.move(point.x, point.y);
    await expect(chart.getByRole('tooltip')).toContainText('19');
    await page.mouse.click(point.x, point.y);
    await expect(chart.locator('[data-moonplot-selected]')).toHaveCount(1);
    await page.mouse.move(0, 0);
    await expect(chart.getByRole('tooltip')).toHaveCount(0);
    await page.locator('#task').fill('Keep this chart while I type.');
    await expect(chart.locator('[data-moonplot-selected]')).toHaveCount(1);
    await chart.locator('svg[data-moonplot-root]').click({ position: { x: 5, y: 5 } });
    await expect(chart.locator('[data-moonplot-selected]')).toHaveCount(0);
    await chart.scrollIntoViewIfNeeded();
    const repin = await dataPoint(chart);
    await page.mouse.click(repin.x, repin.y);
    await expect(chart.locator('[data-moonplot-selected]')).toHaveCount(1);
    const actual = chart.getByRole('button', { name: 'Actual', exact: true });
    await actual.click();
    await expect(actual).toHaveAttribute('aria-pressed', 'false');
    await expect(chart.locator('[data-moonplot-selected]')).toHaveCount(0);
    await expect(chart.locator('polyline[stroke="#2563eb"]')).toHaveCount(0);
    await actual.click();
    await expect(actual).toHaveAttribute('aria-pressed', 'true');
    if (minimal && evidence) {
      mkdirSync(evidence, { recursive: true });
      await page.setViewportSize({ width: 1440, height: 1200 });
      await page.locator('#task').fill('');
      await chart.scrollIntoViewIfNeeded();
      const hover = await dataPoint(chart);
      await page.mouse.click(hover.x, hover.y);
      await expect(chart.getByRole('tooltip')).toContainText('19');
      await chart.screenshot({ path: `${evidence}/interactive-chart-light.png`, animations: 'disabled' });
      await page.screenshot({ path: `${evidence}/openseek-chat-chart-light.png`, animations: 'disabled' });
      await page.emulateMedia({ colorScheme: 'dark' });
      await expect(page.locator('html')).toHaveAttribute('data-theme', 'dark');
      await chart.screenshot({ path: `${evidence}/interactive-chart-dark.png`, animations: 'disabled' });
      await page.screenshot({ path: `${evidence}/openseek-chat-chart-dark.png`, animations: 'disabled' });
    }
    expect(app.pageErrors).toEqual([]);
  });
}

test('assistant charts have independent resources and series state across narrow layouts', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  app.sessionEvents = history([spec, spec, ...['scatter', 'bar', 'barh', 'hist', 'pie', 'area'].map(kind => ({ title: kind, series: [{ kind, label: kind, y: [2, 5, 3] }] }))]);
  await app.install(); await app.goto(); await app.openSession();
  const charts = page.locator('#transcript .chat-plot');
  await expect(charts).toHaveCount(8);
  await expect(page.locator('.chat-plot-error')).toHaveCount(0);
  await charts.first().getByRole('button', { name: 'Actual', exact: true }).click();
  await expect(charts.nth(1).getByRole('button', { name: 'Actual', exact: true })).toHaveAttribute('aria-pressed', 'true');
  const ids = await page.locator('.chat-plot [id]').evaluateAll(nodes => nodes.map(node => node.id));
  expect(new Set(ids).size).toBe(ids.length);
  await page.setViewportSize({ width: 390, height: 844 });
  await charts.nth(1).scrollIntoViewIfNeeded();
  const point = await dataPoint(charts.nth(1));
  await page.mouse.click(point.x, point.y);
  await expect(charts.nth(1).locator('[data-moonplot-selected]')).toHaveCount(1);
  const overflowing = await charts.evaluateAll(nodes => nodes.some(node => node.scrollWidth > node.clientWidth + 1));
  expect(overflowing).toBe(false);
  expect(app.pageErrors).toEqual([]);
});

test('chart accessible names follow live language changes without losing a selected point', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  app.sessionEvents = history([{ ...spec, title: '' }]);
  await app.install(); await app.goto(); await app.openSession();
  const chart = page.locator('#transcript .chat-plot');
  await chart.scrollIntoViewIfNeeded();
  const point = await dataPoint(chart);
  await page.mouse.click(point.x, point.y);
  for (const [tag, name] of [
    ['zh-Hans', '图表'],
    ['zh-Hant', '圖表'],
    ['ja', 'グラフ'],
    ['es', 'Gráfico'],
    ['en', 'Chart'],
  ]) {
    await page.evaluate(tag => {
      Object.defineProperty(navigator, 'languages', { configurable: true, value: [tag] });
      window.dispatchEvent(new Event('languagechange'));
    }, tag);
    await expect(page.getByRole('group', { name, exact: true })).toBeVisible();
    await expect(chart.locator('[data-moonplot-selected]')).toHaveCount(1);
  }
  expect(app.pageErrors).toEqual([]);
});

test('hover shows semantic values for lines, points, bars, histogram bins and pie slices', async ({ page }) => {
  await page.addInitScript(() => localStorage.setItem('openseek.language', 'zh-Hans'));
  await page.setViewportSize({ width: 1440, height: 1200 });
  const dates = ['2026-10-01', '2026-10-02', '2026-10-03'];
  const cases = [
    {
      title: '折线悬停', kind: 'line', x_label: '日期', y_label: '人数',
      series: [{ kind: 'line', label: '新增用户', x: [1, 2, 3], y: [10, 20, 30], labels: dates }],
      expected: ['新增用户', '日期', '2026-10-02', '人数', '20'],
    },
    {
      title: '散点悬停', kind: 'scatter', x_label: '样本', y_label: '测量值',
      series: [{ kind: 'scatter', label: '测量', y: [10, 20, 30], labels: ['A', 'B', 'C'] }],
      expected: ['测量', '样本', 'B', '测量值', '20'],
    },
    {
      title: '柱状悬停', kind: 'bar', x_label: '日期', y_label: '收入（万元）',
      series: [
        { kind: 'bar', label: '参考', y: [2, 3, 4], labels: dates },
        { kind: 'bar', label: '销售额', color: '#ea580c', y: [10, 20, 30], labels: dates },
      ],
      expected: ['销售额', '日期', '2026-10-02', '收入（万元）', '20'],
    },
    {
      title: '横向柱状悬停', kind: 'barh', x_label: '支出（万元）', y_label: '部门',
      series: [{ kind: 'barh', label: '支出', y: [-10, -20, -30], labels: ['研发', '运营', '市场'] }],
      expected: ['支出', '部门', '运营', '支出（万元）', '-20'],
    },
    {
      title: '直方图悬停', kind: 'hist',
      series: [{ kind: 'hist', label: '分布', y: [0, 0, 1, 2, 3, 3], bins: 2 }],
      expected: ['分布', '区间', '0 – 1.5', '频数', '3'],
    },
    {
      title: '饼图悬停', kind: 'pie',
      series: [{ kind: 'pie', label: '构成', y: [2, 3, 5], labels: ['甲', '乙', '丙'] }],
      expected: ['构成', '类别', '甲', '数值', '2', '占比', '20%'],
    },
  ];
  const app = new DesktopBrowserHarness(page);
  app.sessionEvents = history(cases.map(({ expected, kind, ...chart }) => chart));
  await app.install(); await app.goto(); await app.openSession();
  for (const example of cases) {
    const chart = page.getByRole('group', { name: example.title, exact: true });
    await chart.scrollIntoViewIfNeeded();
    if (example.kind === 'bar') {
      const reference = chart.getByRole('button', { name: '参考', exact: true });
      await reference.click();
      await expect(reference).toHaveAttribute('aria-pressed', 'false');
      await chart.scrollIntoViewIfNeeded();
    }
    const hit = await chart.locator('svg[data-moonplot-root]').evaluate((svg, kind) => {
      const point = svg.createSVGPoint();
      let anchor = null;
      if (kind === 'line') {
        const line = svg.querySelector('polyline[stroke="#2563eb"]');
        const points = line.getAttribute('points').trim().split(/\s+/).map(p => p.split(',').map(Number));
        const bounds = line.getBBox();
        point.x = points[1][0]; point.y = bounds.y + bounds.height * .95;
        anchor = svg.createSVGPoint(); anchor.x = points[1][0]; anchor.y = points[1][1];
      } else if (kind === 'scatter') {
        const circle = svg.querySelectorAll('circle[fill="#2563eb"]')[1];
        point.x = Number(circle.getAttribute('cx')); point.y = Number(circle.getAttribute('cy'));
      } else if (kind === 'pie') {
        const sector = svg.querySelector('path[stroke="white"]');
        const [, cx, cy, edgeX, edgeY] = sector.getAttribute('d').match(/^M\s+([-\d.]+),([-\d.]+)\s+L\s+([-\d.]+),([-\d.]+)/).map(Number);
        const radius = Math.hypot(edgeX - cx, edgeY - cy);
        point.x = cx + radius * .45; point.y = cy - radius * .3;
      } else {
        const color = kind === 'bar' ? '#ea580c' : '#2563eb';
        const rect = svg.querySelectorAll(`rect[fill="${color}"]`)[kind === 'hist' ? 0 : 1];
        const bounds = rect.getBBox();
        point.x = bounds.x + bounds.width * .2; point.y = bounds.y + bounds.height * .2;
      }
      const client = point.matrixTransform(svg.getScreenCTM());
      const original = anchor?.matrixTransform(svg.getScreenCTM());
      return { x: client.x, y: client.y, sampleDistance: original ? Math.hypot(original.x - client.x, original.y - client.y) : null };
    }, example.kind);
    if (example.kind === 'line') expect(hit.sampleDistance).toBeGreaterThan(50);
    await page.mouse.move(hit.x, hit.y);
    const tooltip = chart.getByRole('tooltip');
    await expect(tooltip).toBeVisible();
    for (const value of example.expected) {
      await expect(tooltip.getByText(value, { exact: true })).toBeVisible();
    }
    await expect(chart.getByRole('status')).toHaveCount(0);
    if (evidence) {
      mkdirSync(evidence, { recursive: true });
      await chart.screenshot({ path: `${evidence}/hover-${example.kind}.png`, animations: 'disabled' });
      if (example.kind === 'bar') {
        await page.screenshot({ path: `${evidence}/openseek-hover-bar-light.png`, animations: 'disabled' });
        await page.emulateMedia({ colorScheme: 'dark' });
        await expect(page.locator('html')).toHaveAttribute('data-theme', 'dark');
        await page.screenshot({ path: `${evidence}/openseek-hover-bar-dark.png`, animations: 'disabled' });
        await page.emulateMedia({ colorScheme: 'light' });
        await expect(page.locator('html')).toHaveAttribute('data-theme', 'light');
      }
    }
    await page.mouse.move(0, 0);
    await expect(tooltip).toHaveCount(0);
  }
  expect(app.pageErrors).toEqual([]);
});

for (const minimal of [true, false]) {
  test(`chart generation stays hidden until a final answer embeds its reference (${minimal ? 'minimal' : 'detailed'})`, async ({ page }) => {
    await page.addInitScript(value => localStorage.setItem('openseek.minimal_transcript', String(value)), minimal);
    const app = new DesktopBrowserHarness(page);
    app.sessionEvents = history([spec]).slice(0, 2);
    await app.install(); await app.goto(); await app.openSession();
    const run = { run_id: 'plot-run', session: 'session-1' };
    app.notify('agent.started', { ...run, session_root: '/workspace/.openseek', model: 'deepseek-v4-pro', max_steps: 1000 });
    append(app, 'tool_result', history([spec])[2].item.payload);
    await expect(page.locator('#transcript .chat-plot')).toHaveCount(0);
    // Even legacy fences in tool output must not auto-promote a chart.
    append(app, 'assistant', { content: 'Still checking the data.', tool_calls: [{ id: 'legacy', name: 'mbtx', arguments: '{}' }] });
    append(app, 'tool_result', { tool_call_id: 'legacy', tool_name: 'mbtx', content: fence(spec), is_error: false });
    append(app, 'assistant', { content: 'Provisional ' + embed('chart_0') });
    await expect(page.locator('#transcript .chat-plot')).toHaveCount(0);
    const answer = 'The data is complete.\n\n' + embed('chart_0', 'Revenue') + '\n\nThe fifth week was strongest.';
    const partial = 'The data is complete.\n\n![Revenue](artifact://chart_';
    app.notify('agent.event', { ...run, event: { event: 'assistant_delta', content: partial } });
    await expect(page.locator('#transcript .msg.streaming')).toContainText('The data is complete.');
    await expect(page.locator('#transcript .msg.streaming')).not.toContainText('artifact://');
    app.notify('agent.event', { ...run, event: { event: 'assistant_delta', content: answer.slice(partial.length) } });
    await expect(page.locator('#transcript .msg.streaming .chat-plot')).toHaveCount(0);
    await expect(page.locator('#transcript img[src^="artifact:"]')).toHaveCount(0);
    append(app, 'assistant', { content: answer });
    await expect(page.locator('#transcript .chat-plot')).toHaveCount(0);
    append(app, 'terminal', { kind: 'finished', message: answer });
    app.notify('agent.event', { ...run, event: { event: 'agent_finished', answer } });
    const chart = page.locator('#transcript .chat-plot');
    await expect(chart).toHaveCount(1);
    await expect(chart).toBeVisible();
    const prose = chart.locator('..');
    await expect(prose).toContainText('The data is complete.');
    await expect(prose).toContainText('The fifth week was strongest.');
    expect(await prose.evaluate(node => Array.from(node.children).map(child => child.classList.contains('chat-plot') ? 'chart' : child.textContent).filter(Boolean)))
      .toEqual(['The data is complete.', 'chart', 'The fifth week was strongest.']);
    await expect(page.locator('#transcript p .chat-plot')).toHaveCount(0);
    await page.reload(); await app.openSession();
    await expect(page.locator('#transcript .chat-plot')).toHaveCount(1);
    expect(app.pageErrors).toEqual([]);
  });
}

test('references preserve chosen versions and order; missing or damaged artifacts never substitute a chart', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  const first = { title: 'Original version', series: [{ y: [1, 2] }] };
  const second = { title: 'Revised version', series: [{ y: [10, 20] }] };
  const damaged = { title: 'Damaged version', series: [{ x: [1], y: [1, 2] }] };
  const answer = [
    'Revised result:', embed('chart_1'), 'Original result:', embed('chart_0'),
    embed('chart_missing', 'Missing revenue chart'), embed('chart_2'), 'The rest of this answer still works.',
  ].join('\n\n');
  app.sessionEvents = history([first, second, damaged, { ...spec, title: 'Unused generation' }], answer);
  await app.install(); await app.goto(); await app.openSession();
  await expect(page.locator('#transcript .chat-plot')).toHaveCount(2);
  await expect(page.locator('#transcript .chat-plot').nth(0)).toHaveAccessibleName('Revised version');
  await expect(page.locator('#transcript .chat-plot').nth(1)).toHaveAccessibleName('Original version');
  await expect(page.locator('.chat-plot-unavailable')).toContainText('Missing revenue chart');
  await expect(page.locator('.chat-plot-unavailable')).toContainText('Chart unavailable');
  await expect(page.locator('#transcript .chat-plot-error')).toContainText('equal lengths');
  await expect(page.locator('#transcript')).toContainText('The rest of this answer still works.');
  await expect(page.getByRole('group', { name: 'Unused generation', exact: true })).toHaveCount(0);
  await expect(page.locator('img[src^="artifact:"]')).toHaveCount(0);
  await page.reload(); await app.openSession();
  await expect(page.locator('#transcript .chat-plot').nth(0)).toHaveAccessibleName('Revised version');
  await expect(page.locator('#transcript .chat-plot').nth(1)).toHaveAccessibleName('Original version');
  expect(app.pageErrors).toEqual([]);
});
