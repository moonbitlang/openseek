import { readFile } from 'node:fs/promises';
import { test, expect } from './support/test.js';

// Execute the module's compiled MoonBit black-box tests against real IndexedDB.
// The normal Node gate skips them because Node does not provide that browser API.
test('IndexedDB public module contracts', async ({ page }) => {
  const build = new URL('../../../_build/js/debug/test/moonbitlang/indexeddb/', import.meta.url);
  const metadata = JSON.parse(await readFile(new URL('__blackbox_test_info.json', build), 'utf8'));
  const files = Object.entries(metadata.tests).filter(([, cases]) => cases.length);
  const count = files.reduce((total, [, cases]) => total + cases.length, 0);
  expect(count).toBeGreaterThan(0);
  // The JS test driver reads `file:start-end,start-end/file:...` from argv[2].
  const args = files.map(([file, cases]) => `${file}:${cases.map(({ index }) => `${index}-${index + 1}`).join(',')}`).join('/');
  const results = [];
  const errors = [];
  page.on('pageerror', error => errors.push(error.message));
  page.on('console', message => {
    try {
      const record = JSON.parse(message.text());
      if (record.type === 'result') results.push(record);
    } catch { /* MoonBit's result boundary markers are not JSON. */ }
  });
  await page.route('**/indexeddb-contracts', route => route.fulfill({ contentType: 'text/html', body: '<!doctype html><title>IndexedDB contracts</title>' }));
  await page.goto('/indexeddb-contracts');
  await page.evaluate(args => {
    globalThis.exports = {};
    globalThis.process = { argv: ['browser', 'indexeddb', args], exit(code) { throw new Error(`Test driver exited: ${code}`); } };
  }, args);
  await page.addScriptTag({ content: await readFile(new URL('indexeddb.blackbox_test.js', build), 'utf8') });
  await expect.poll(() => results.length).toBe(count);
  expect(errors).toEqual([]);
  expect(results.map(({ message }) => message)).toEqual(Array(count).fill(''));
});
