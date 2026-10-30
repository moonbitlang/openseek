// Build standalone components and check their behavior in a headless browser.
// Run from the repository root: node --test desktop/e2e/artifact-component.test.mjs
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { mkdtemp, mkdir, copyFile, readFile, writeFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { after, before, test } from 'node:test';
import { chromium, expect } from '@playwright/test';

const repo = fileURLToPath(new URL('../../', import.meta.url));
const csp = "default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; img-src data: blob:; font-src data:; connect-src 'none'; frame-src 'none'; base-uri 'none'; form-action 'none'";
let temporary, browser, html, specialHtml;

before(async () => {
  temporary = await mkdtemp(join(tmpdir(), 'openseek-rabbita-answer-'));
  const project = join(temporary, 'scratch/project');
  const output = join(temporary, 'scratch/artifact');
  await mkdir(project, { recursive: true });
  for (const name of ['moon.mod', 'moon.pkg', 'main.mbt', 'model.mbt', 'model_wbtest.mbt', 'bridge.mbt', 'index.html']) {
    await copyFile(join(repo, 'share/artifact/rabbita', name), join(project, name));
  }
  execFileSync('moon', ['test', '--target', 'js'], { cwd: project, timeout: 120_000 });
  execFileSync('moon', [
    'run', '--target-dir', join(temporary, 'recipe-build'),
    join(repo, 'share/artifact/build.mbtx'), project, output, 'answer-v1.html',
  ], { cwd: repo, timeout: 120_000 });
  html = await readFile(join(output, 'answer-v1.html'), 'utf8');
  const main = join(project, 'main.mbt');
  await writeFile(main, (await readFile(main, 'utf8')).replace(
    'How much faster can more workers make this task?',
    'Literal <!-- <ScRiPt> </sCrIpT> 你好',
  ));
  execFileSync('moon', [
    'run', '--target-dir', join(temporary, 'recipe-build'),
    join(repo, 'share/artifact/build.mbtx'), project, output, 'answer-v2.html',
  ], { cwd: repo, timeout: 120_000 });
  specialHtml = await readFile(join(output, 'answer-v2.html'), 'utf8');
  browser = await chromium.launch({ headless: true });
}, { timeout: 150_000 });

after(async () => {
  await browser?.close();
  if (temporary) await rm(temporary, { recursive: true, force: true });
});

async function openComponent(options = {}, count = 1, content = html) {
  const page = await browser.newPage(options);
  const errors = [], requests = [];
  page.on('pageerror', error => errors.push(error.message));
  page.on('request', request => requests.push(request.url()));
  await page.setContent('<textarea id="host">Conversation</textarea>' + '<iframe sandbox="allow-scripts" style="width:100%;border:0;height:500px"></iframe>'.repeat(count));
  await page.locator('iframe').evaluateAll((frames, { html, csp }) => {
    for (const frame of frames) {
      frame.srcdoc = `<meta http-equiv="Content-Security-Policy" content="${csp}">` + html;
    }
  }, { html: content, csp });
  const frame = page.frameLocator('iframe').nth(0);
  await expect(frame.getByRole('status')).toHaveText('3.33× faster');
  return { page, frame, errors, requests };
}

test('compiled Rabbita inputs update the answer locally and reset together', async () => {
  const { page, frame, errors, requests } = await openComponent();
  try {
    const serial = frame.getByRole('slider', { name: 'Work that must run in sequence: 20%' });
    await serial.fill('50');
    await expect(frame.getByRole('status')).toHaveText('1.78× faster');
    await frame.getByRole('slider', { name: 'Workers: 8', exact: true }).fill('1');
    await expect(frame.getByRole('status')).toHaveText('1.00× faster');
    await frame.getByRole('button', { name: 'Reset', exact: true }).click();
    await expect(frame.getByRole('status')).toHaveText('3.33× faster');
    await expect(frame.locator('#serial')).toHaveValue('20');
    await expect(frame.locator('#workers')).toHaveValue('8');
    assert.deepEqual(errors, []);
    assert.deepEqual(requests, []);
  } finally { await page.close(); }
});

test('repeated instances are independent and reopening restores the authored state', async () => {
  const { page, frame, errors } = await openComponent({}, 2);
  try {
    const other = page.frameLocator('iframe').nth(1);
    await frame.locator('#serial').fill('100');
    await expect(frame.getByRole('status')).toHaveText('1.00× faster');
    await expect(other.getByRole('status')).toHaveText('3.33× faster');
    await page.locator('#host').fill('Follow-up');
    await expect(frame.getByRole('status')).toHaveText('1.00× faster');
    await page.locator('iframe').nth(0).evaluate(node => { node.srcdoc = node.srcdoc; });
    await expect(frame.getByRole('status')).toHaveText('3.33× faster');
    assert.deepEqual(errors, []);
  } finally { await page.close(); }
});

test('the packaged page fits a narrow dark frame and respects preview isolation', async () => {
  const { page, frame, errors } = await openComponent({ viewport: { width: 390, height: 844 }, colorScheme: 'dark' });
  try {
    assert.equal(await frame.locator('body').evaluate(() => document.documentElement.scrollWidth <= innerWidth), true);
    assert.equal(await frame.locator('body').evaluate(() => matchMedia('(prefers-color-scheme: dark)').matches), true);
    assert.equal(await frame.locator('body').evaluate(() => {
      try { return Boolean(parent.document); } catch { return false; }
    }), false);
    assert.equal(await frame.locator('body').evaluate(async () => {
      try { await fetch('https://example.com/'); return true; } catch { return false; }
    }), false);
    await frame.locator('#serial').focus();
    await page.keyboard.press('ArrowRight');
    await expect(frame.locator('#serial')).toHaveValue('21');
    await expect(frame.getByRole('status')).not.toHaveText('3.33× faster');
    assert.deepEqual(errors, []);
  } finally { await page.close(); }
});

test('HTML-like text in compiled source stays literal and does not swallow the executable', async () => {
  const { page, frame, errors } = await openComponent({}, 1, specialHtml);
  try {
    await expect(frame.getByRole('heading')).toHaveText('Literal <!-- <ScRiPt> </sCrIpT> 你好');
    await frame.locator('#serial').fill('100');
    await expect(frame.getByRole('status')).toHaveText('1.00× faster');
    assert.deepEqual(errors, []);
  } finally { await page.close(); }
});
