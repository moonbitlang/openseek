import { test, expect } from './support/test.js';
import { readFileSync, mkdirSync } from 'node:fs';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';

// Use a small HTML fixture by default. OPENSEEK_ARTIFACT_HTML supplies a compiled
// application for the same preview checks.
const sample = process.env.OPENSEEK_ARTIFACT_HTML
  ? readFileSync(process.env.OPENSEEK_ARTIFACT_HTML, 'utf8')
  : `<!doctype html><html><head><style>body{margin:0;font:14px system-ui}svg{width:100%;height:auto}button{padding:8px}[role=tooltip]{position:absolute;top:20px;left:100px;background:white}</style></head><body>
    <svg viewBox="0 0 760 400"><text x="280" y="30">Weekly revenue</text><polyline stroke="#2563eb" fill="none" points="60,300 200,220 340,250 480,160 620,100"/></svg>
    <button aria-pressed="true">Actual</button><div role="tooltip" hidden>19</div>
    <script>const svg=document.querySelector('svg'),tip=document.querySelector('[role=tooltip]'),button=document.querySelector('button');svg.onpointermove=()=>tip.hidden=false;svg.onpointerleave=()=>tip.hidden=true;button.onclick=()=>{const show=button.getAttribute('aria-pressed')!=='true';button.setAttribute('aria-pressed',String(show));svg.querySelector('polyline').style.display=show?'':'none';tip.hidden=true;};</script></body></html>`;

const fence = (name, inline = true) => '```openseek-file' + (inline ? ' artifact' : '') + '\nscratch/artifact/' + name + '\n```';
function history(answer, finished = true) {
  return [
    { sequence: 1, item: { kind: 'user', payload: { content: 'Show the browser fixture: compare the weekly revenue.' } } },
    { sequence: 2, item: { kind: 'assistant', payload: { content: answer } } },
    ...(finished ? [{ sequence: 3, item: { kind: 'terminal', payload: { kind: 'finished', message: answer } } }] : []),
  ];
}

function fixture(page, answer, finished = true) {
  const app = new DesktopBrowserHarness(page);
  app.sessionEvents = history(answer, finished);
  const ordinary = app.replyFor.bind(app);
  app.replyFor = request => request.method === 'fs.read_file'
    ? { kind: 'content', absolute: request.params.root + '/' + request.params.path, content: request.params.path.endsWith('.html') ? sample : 'week,revenue\n1,19', sig: 'fixture' }
    : ordinary(request);
  return app;
}

async function hoverSample(page, frameElement, frame) {
  const point = await frame.locator('svg').evaluate(svg => {
    const line = svg.querySelector('polyline[stroke="#2563eb"]');
    const [x, y] = line.getAttribute('points').trim().split(/\s+/)[1].split(',').map(Number);
    const point = svg.createSVGPoint(); point.x = x; point.y = y;
    const client = point.matrixTransform(svg.getScreenCTM());
    return { x: client.x, y: client.y };
  });
  const box = await frameElement.boundingBox();
  await page.mouse.move(box.x + point.x, box.y + point.y);
  await expect(frame.getByRole('tooltip')).toContainText('19');
}

for (const minimal of [true, false]) {
  test(`file artifacts preserve their interactive application in ${minimal ? 'minimal' : 'detailed'} answers`, async ({ page }) => {
    await page.addInitScript(value => {
      if (window === window.top) localStorage.setItem('openseek.minimal_transcript', String(value));
    }, minimal);
    const app = fixture(page, 'Revenue exceeded the forecast.\n\n' + fence('chart.html') + '\n\nWeek 5 was highest.');
    await app.install(); await app.goto(); await app.openSession();
    const element = page.locator('#transcript .chat-artifact-frame');
    const frame = page.frameLocator('#transcript .chat-artifact-frame');
    await expect(frame.locator('svg')).toBeVisible();
    await element.scrollIntoViewIfNeeded();
    await hoverSample(page, element, frame);
    await frame.getByRole('button', { name: 'Actual', exact: true }).click();
    await expect(frame.getByRole('button', { name: 'Actual', exact: true })).toHaveAttribute('aria-pressed', 'false');
    await frame.getByRole('button', { name: 'Actual', exact: true }).click();
    await page.locator('#task').fill('Keep the chart while I type.');
    await expect(frame.getByRole('button', { name: 'Actual', exact: true })).toHaveAttribute('aria-pressed', 'true');
    const request = app.requests.find(request => request.method === 'fs.read_file');
    expect(request.params).toEqual({ root: '/workspace', path: '.openseek/sessions/session-1/scratch/artifact/chart.html', max_bytes: 8 * 1024 * 1024 });
    expect(await frame.locator('body').evaluate(() => {
      try { void parent.document.body; return false; } catch { return true; }
    })).toBe(true);
    expect(await frame.locator('body').evaluate(async () => {
      try { await fetch('https://example.com/'); return false; } catch { return true; }
    })).toBe(true);
    if (minimal && process.env.OPENSEEK_UI_CAPTURE_DIR) {
      mkdirSync(process.env.OPENSEEK_UI_CAPTURE_DIR, { recursive: true });
      await page.locator('#task').fill('');
      await hoverSample(page, element, frame);
      await page.screenshot({ path: `${process.env.OPENSEEK_UI_CAPTURE_DIR}/artifact-file-chart.png` });
    }
    if (minimal) {
      await page.setViewportSize({ width: 390, height: 844 });
      await element.scrollIntoViewIfNeeded();
      const fits = await frame.locator('svg').evaluate(svg => svg.getBoundingClientRect().width <= innerWidth + 1);
      expect(fits).toBe(true);
      await page.emulateMedia({ colorScheme: 'dark' });
      await expect(page.locator('html')).toHaveAttribute('data-theme', 'dark');
      expect(await frame.locator('body').evaluate(() => matchMedia('(prefers-color-scheme: dark)').matches)).toBe(true);
      await expect(frame.getByRole('button', { name: 'Actual', exact: true })).toHaveAttribute('aria-pressed', 'true');
      if (process.env.OPENSEEK_UI_CAPTURE_DIR) {
        await page.screenshot({ path: `${process.env.OPENSEEK_UI_CAPTURE_DIR}/artifact-file-chart-dark-narrow.png` });
      }
    }
    expect(app.pageErrors).toEqual([]);
  });
}

test('intermediate artifact fences do not read or execute the page', async ({ page }) => {
  const app = fixture(page, fence('chart.html'), false);
  await app.install(); await app.goto(); await app.openSession();
  await expect(page.locator('#transcript .chat-artifact-frame')).toHaveCount(0);
  expect(app.requests.filter(request => request.method === 'fs.read_file')).toHaveLength(0);
});

test('repeated references share a file read but keep independent application state', async ({ page }) => {
  const app = fixture(page, fence('chart.html') + '\n\n' + fence('chart.html'));
  await app.install(); await app.goto(); await app.openSession();
  const first = page.frameLocator('.chat-artifact-frame').nth(0);
  const second = page.frameLocator('.chat-artifact-frame').nth(1);
  await expect(first.locator('svg')).toBeVisible();
  await expect(second.locator('svg')).toBeVisible();
  await first.getByRole('button', { name: 'Actual', exact: true }).click();
  await expect(first.getByRole('button', { name: 'Actual', exact: true })).toHaveAttribute('aria-pressed', 'false');
  await expect(second.getByRole('button', { name: 'Actual', exact: true })).toHaveAttribute('aria-pressed', 'true');
  expect(app.requests.filter(request => request.method === 'fs.read_file')).toHaveLength(1);
});

test('non-HTML artifact cards resolve their owning file before opening it', async ({ page }) => {
  const app = fixture(page, fence('revenue.csv'));
  await app.install(); await app.goto(); await app.openSession();
  await page.getByRole('button', { name: 'Open revenue.csv', exact: true }).click();
  await expect.poll(() => app.requests.filter(request => request.method === 'host.open_path' || request.method === 'host.open_path_preview').length).toBeGreaterThan(0);
  const open = app.requests.find(request => request.method === 'host.open_path' || request.method === 'host.open_path_preview');
  expect(open.params.path).toBe('.openseek/sessions/session-1/scratch/artifact/revenue.csv');
  expect(open.params.cwd).toBe('/workspace');
});

test('ordinary HTML references remain file cards until explicitly marked for inline display', async ({ page }) => {
  const app = fixture(page, fence('page.html', false));
  await app.install(); await app.goto(); await app.openSession();
  await expect(page.getByRole('button', { name: 'Open scratch/artifact/page.html', exact: true })).toBeVisible();
  await expect(page.locator('.chat-artifact-frame')).toHaveCount(0);
  expect(app.requests.filter(request => request.method === 'fs.read_file')).toHaveLength(0);
  await page.getByRole('button', { name: 'Open scratch/artifact/page.html', exact: true }).click();
  await expect.poll(() => app.requests.filter(request => request.method === 'host.open_path').length).toBeGreaterThan(0);
  const open = app.requests.find(request => request.method === 'host.open_path');
  expect(open.params).toMatchObject({ cwd: '/workspace', path: '.openseek/sessions/session-1/scratch/artifact/page.html' });
});

test('an explicit artifact marker can preview an ordinary workspace HTML path', async ({ page }) => {
  const app = fixture(page, '```openseek-file artifact\nreports/page.html\n```');
  await app.install(); await app.goto(); await app.openSession();
  await expect(page.frameLocator('.chat-artifact-frame').locator('svg')).toBeVisible();
  const read = app.requests.find(request => request.method === 'fs.read_file');
  expect(read.params).toEqual({ root: '/workspace', path: 'reports/page.html', max_bytes: 8 * 1024 * 1024 });
});

test('an oversized file keeps its open card without executing partial HTML', async ({ page }) => {
  const app = fixture(page, fence('large.html'));
  const ordinary = app.replyFor.bind(app);
  app.replyFor = request => request.method === 'fs.read_file' ? { kind: 'oversized' } : ordinary(request);
  await app.install(); await app.goto(); await app.openSession();
  await expect(page.getByRole('button', { name: 'Open large.html', exact: true })).toBeVisible();
  await expect(page.locator('.chat-artifact-frame')).toBeHidden();
  expect(app.pageErrors).toEqual([]);
});

test('an explicitly marked HTML page larger than the editor default remains interactive', async ({ page }) => {
  const app = fixture(page, fence('larger.html'));
  const ordinary = app.replyFor.bind(app);
  app.replyFor = request => request.method === 'fs.read_file'
    ? { kind: 'content', absolute: '/workspace/larger.html', sig: 'fixture', content: sample + '<!--' + 'x'.repeat(1024 * 1024) + '-->' }
    : ordinary(request);
  await app.install(); await app.goto(); await app.openSession();
  const frame = page.frameLocator('.chat-artifact-frame');
  await expect(frame.locator('svg')).toBeVisible();
  await frame.getByRole('button', { name: 'Actual', exact: true }).click();
  await expect(frame.getByRole('button', { name: 'Actual', exact: true })).toHaveAttribute('aria-pressed', 'false');
  expect(app.requests.find(request => request.method === 'fs.read_file').params.max_bytes).toBe(8 * 1024 * 1024);
  expect(app.pageErrors).toEqual([]);
});
