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
const resumed = () => run('shell', 'dumpsys', 'activity', 'activities')
  .match(/(?:topResumedActivity|mResumedActivity)[^\n]*/)?.[0] ?? '';
const until = async (ok, label) => {
  for (let attempt = 0; attempt < 50; attempt += 1) {
    if (ok()) return;
    await new Promise(resolve => setTimeout(resolve, 200));
  }
  throw new Error(label);
};
try {
  // Keep unmocked requests off the network; the harness below owns every API
  // reply.
  const assets = new URL('.', home);
  await page.route('**/*', route => {
    const url = new URL(route.request().url());
    return url.origin === assets.origin &&
      (url.pathname.startsWith(assets.pathname) || url.pathname.startsWith('/assets/'))
      ? route.continue() : route.abort();
  });
  const app = new DesktopBrowserHarness(page);
  // A Git checkout gives the composer its Git chip, whose menu Back closes.
  app.gitBranch = { branch: 'android/smoke', diffstat: { added: 3, removed: 1, files: 1, partial: false } };
  // The export the Download step saves.
  const reply = app.replyFor.bind(app);
  app.replyFor = request => request.method === 'session.snapshot'
    ? { html: '<html>Android smoke export</html>', json: '{}' }
    : reply(request);
  await app.install();
  // The APK answers the frontend's document paths with its bundled document.
  // Let those navigations through to it instead of the desktop harness's
  // /dist/browser document, which only the desktop test server has.
  await page.route(url => url.origin === assets.origin &&
    (url.pathname === '/cloud' || url.pathname.startsWith('/cloud/') || url.pathname.startsWith('/device/')),
  route => route.continue());
  // The entry lands on Cloud; choose the device from the sidebar's selector,
  // which loads that device's page.
  await page.goto(home);
  await page.waitForURL(url => url.pathname === '/cloud');
  await page.locator('.sidebar-toggle').click();
  await page.getByRole('button', { name: 'Choose a device', exact: true }).click();
  await page.getByRole('menuitem', { name: 'Test Mac', exact: true }).click();
  await page.waitForURL(url => url.pathname.startsWith('/device/device-a/'));
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
  // Back dismisses an open menu or modal instead of leaving the page beneath it.
  const deviceUrl = page.url();
  const transfer = page.getByRole('button', { name: 'Export and import', exact: true });
  await transfer.click();
  const transferMenu = page.getByRole('menu', { name: 'Export and import', exact: true });
  await transferMenu.waitFor();
  run('shell', 'input', 'keyevent', '4');
  // Action menus stay mounted as popovers; a closed one leaves the tree.
  await transferMenu.waitFor({ state: 'hidden' });
  check(page.url() === deviceUrl, 'Back left the page under the action menu');
  await transfer.click();
  await page.getByRole('menuitem', { name: 'Export', exact: true }).click();
  const exportDialog = page.getByRole('dialog', { name: 'Export conversation', exact: true });
  await exportDialog.waitFor();
  // Download hands the export's blob to the system's save dialog; Back
  // cancels it and returns to the export dialog.
  await exportDialog.getByRole('button', { name: 'Download', exact: true }).click();
  await until(() => resumed().includes('documentsui'), 'Download did not open the save dialog');
  await device.screenshot({ path: `${output}device-download.png` });
  run('shell', 'input', 'keyevent', '4');
  await until(() => resumed().includes(pkg), 'cancelling the save dialog left the app');
  await exportDialog.waitFor();
  run('shell', 'input', 'keyevent', '4');
  await exportDialog.waitFor({ state: 'hidden' });
  check(page.url() === deviceUrl, 'Back left the page under the export dialog');
  await page.locator('.composer-git-button').click();
  await page.locator('.composer-git-menu').waitFor();
  run('shell', 'input', 'keyevent', '4');
  await page.locator('.composer-git-menu').waitFor({ state: 'detached' });
  check(page.url() === deviceUrl, 'Back left the page under the Git menu');
  await page.locator('.sidebar-toggle').click();
  await page.waitForFunction(() => Math.abs(document.querySelector('aside').getBoundingClientRect().x) < 1);
  await page.screenshot({ path: `${output}drawer.png` });
  run('shell', 'input', 'keyevent', '4');
  await page.waitForFunction(() => document.querySelector('.app.sidebar-collapsed'));
  check(app.pageErrors.length === 0, `page errors: ${app.pageErrors.join('; ')}`);
  console.log('PASS: bundled entry and device page, device selector, real IME, send/stop, Back on menu, modal and drawer, export download');
} finally {
  await page.unrouteAll({ behavior: 'wait' });
  // Reload disposes every fixture socket and restores the real application entry.
  await page.goto(home);
  await device.close();
}
