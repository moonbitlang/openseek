// Acceptance checks for a page authored by the live model.
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { cp, mkdtemp, mkdir, readFile, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { test } from 'node:test';
import { chromium, expect } from '@playwright/test';

test('live-authored linear answer has correct controls, results, reset and offered state', {
  skip: !process.env.OPENSEEK_LIVE_COMPONENT_HTML,
  timeout: 150_000,
}, async () => {
  const source = process.env.OPENSEEK_LIVE_COMPONENT_HTML;
  const temporary = await mkdtemp(join(tmpdir(), 'openseek-live-validation-'));
  let browser;
  try {
    const project = join(temporary, 'source');
    await cp(source + '.source', project, { recursive: true });
    execFileSync('moon', ['test', '--target', 'js', '--deny-warn'], { cwd: project, timeout: 120_000 });
    const html = await readFile(source, 'utf8');
    browser = await chromium.launch({ headless: true });
    const page = await browser.newPage({ viewport: { width: 800, height: 740 } });
    const errors = [], requests = [];
    page.on('pageerror', error => errors.push(error.message));
    page.on('request', request => requests.push(request.url()));
    await page.setContent('<iframe sandbox="allow-scripts" style="width:100%;height:650px;border:0"></iframe>');
    await page.locator('iframe').evaluate((frame, html) => {
      const policy = "default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; img-src data: blob:; font-src data:; connect-src 'none'; frame-src 'none'; base-uri 'none'; form-action 'none'";
      const bridge = '<script>window.openseekArtifact={setState:(title,state)=>window.__offeredState={title,state}};<\/script>';
      frame.srcdoc = `<meta http-equiv="Content-Security-Policy" content="${policy}">` + bridge + html;
    }, html);
    const frame = page.frameLocator('iframe');
    const a = frame.locator('input[type=range]#a');
    const b = frame.locator('input[type=range]#b');
    const output = frame.locator('output#y2');
    await expect(a).toHaveValue('1');
    await expect(b).toHaveValue('0');
    await expect.poll(async () => Number(await output.textContent())).toBe(2);
    for (const [av, bv, y] of [[2, -1, 3], [-3, 4, -2], [5, 5, 15]]) {
      await a.fill(String(av));
      await b.fill(String(bv));
      await expect.poll(async () => Number(await output.textContent())).toBe(y);
      await expect.poll(() => frame.locator('body').evaluate(() => window.__offeredState?.state))
        .toMatchObject({ a: av, b: bv, y_at_2: y });
      if (av === 2 && bv === -1 && process.env.OPENSEEK_LIVE_SELECTION_OUT) {
        const offered = await frame.locator('body').evaluate(() => window.__offeredState);
        await writeFile(process.env.OPENSEEK_LIVE_SELECTION_OUT, JSON.stringify({ reference: 'artifact://linear-v1.html', ...offered }));
      }
    }
    await frame.getByRole('button', { name: /重置|Reset/ }).click();
    await expect(a).toHaveValue('1');
    await expect(b).toHaveValue('0');
    await expect.poll(async () => Number(await output.textContent())).toBe(2);
    await page.setViewportSize({ width: 390, height: 844 });
    await page.emulateMedia({ colorScheme: 'dark' });
    assert.equal(await frame.locator('body').evaluate(() => document.documentElement.scrollWidth <= innerWidth + 1), true);
    if (process.env.OPENSEEK_UI_CAPTURE_DIR) {
      await mkdir(process.env.OPENSEEK_UI_CAPTURE_DIR, { recursive: true });
      await page.screenshot({ path: join(process.env.OPENSEEK_UI_CAPTURE_DIR, 'live-linear-answer.png') });
    }
    assert.deepEqual(errors, []);
    assert.deepEqual(requests, []);
  } finally {
    await browser?.close();
    await rm(temporary, { recursive: true, force: true });
  }
});
