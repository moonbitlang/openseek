#!/usr/bin/env node
// Run only against the Connect debug app on a test emulator. Preserves app
// data and credentials; all conversation traffic uses the in-memory fixture.
import { execFileSync } from 'node:child_process';
import { mkdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { _android } from '../desktop/e2e/node_modules/playwright/index.mjs';
import { DesktopBrowserHarness } from '../desktop/e2e/tests/support/desktop_browser_harness.js';

const serial = process.env.ANDROID_SERIAL;
if (!serial) throw new Error('Set ANDROID_SERIAL to the test emulator');
const adb = `${process.env.ANDROID_HOME}/platform-tools/adb`;
const run = (...args) => execFileSync(adb, ['-s', serial, ...args], { encoding: 'utf8' }).trim();
const pkg = 'com.moonbit.openseek.connect.debug';
const home = 'https://seekmoon.moonbitlang.com/console/android/index.html';
const device = (await _android.devices()).find(candidate => candidate.serial() === serial);
if (!device) throw new Error('Test emulator is not connected');
const page = await (await device.webView({ pkg })).page();
page.setDefaultTimeout(15000);
const output = fileURLToPath(new URL('./app/build/smoke/', import.meta.url));
mkdirSync(output, { recursive: true });
const check = (ok, label) => { if (!ok) throw new Error(label); };
try {
  // A saved frontend preference may open Cloud before device selection. Keep
  // unmocked requests off the network; the harness below owns every API reply.
  const assets = new URL('.', home);
  await page.route('**/*', route => {
    const url = new URL(route.request().url());
    return url.origin === assets.origin && url.pathname.startsWith(assets.pathname)
      ? route.continue() : route.abort();
  });
  const app = new DesktopBrowserHarness(page);
  await app.install();
  // Follow the frontend's own device entry without constructing a route.
  await page.goto(home);
  const chooseDevice = page.getByRole('link', { name: 'Choose a device', exact: true });
  const onlineDevice = page.getByRole('link', { name: 'Test Mac Online' });
  await onlineDevice.or(chooseDevice).first().waitFor();
  if (!await onlineDevice.isVisible()) await chooseDevice.click();
  await onlineDevice.click();
  await page.getByRole('main').waitFor();
  await page.locator('.sidebar-toggle').click();
  await app.openSession();
  const fullHeight = await page.evaluate(() => innerHeight);
  await page.locator('#task').click();
  await page.waitForFunction(h => innerHeight < h - 100, fullHeight);
  await page.locator('#task').fill('Android keyboard fixture');
  const geometry = await page.locator('#task').evaluate(el => ({ bottom: el.getBoundingClientRect().bottom, height: innerHeight }));
  check(geometry.bottom <= geometry.height, 'keyboard covered the composer');
  await page.screenshot({ path: `${output}keyboard.png` });
  await device.screenshot({ path: `${output}device-keyboard.png` });
  run('shell', 'input', 'keyevent', '4');
  await page.waitForFunction(h => innerHeight >= h - 10, fullHeight);
  await page.locator('#send').click();
  await page.waitForFunction(() => !!document.querySelector('#stop'));
  check(app.requests.filter(r => r.method === 'agent.start').length === 1, 'send count');
  await page.locator('#stop').click();
  await page.locator('.sidebar-toggle').click();
  await page.waitForFunction(() => Math.abs(document.querySelector('aside').getBoundingClientRect().x) < 1);
  await page.screenshot({ path: `${output}drawer.png` });
  run('shell', 'input', 'keyevent', '4');
  await page.waitForFunction(() => document.querySelector('.app.sidebar-collapsed'));
  check(app.pageErrors.length === 0, `page errors: ${app.pageErrors.join('; ')}`);
  console.log('PASS: bundled entry, device selection, real IME, send/stop, Back');
} finally {
  await page.unrouteAll({ behavior: 'wait' });
  // Reload disposes every fixture socket and restores the real application entry.
  await page.goto(home);
  await device.close();
}
