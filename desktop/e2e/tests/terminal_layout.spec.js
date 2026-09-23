import { test, expect } from '@playwright/test';

for (const deviceScaleFactor of [1, 2]) {
  test.describe(`terminal at ${deviceScaleFactor}x`, () => {
    test.use({ deviceScaleFactor });

    test('full terminal rows remain inside their clipping boundary', async ({ page }) => {
      // Isolate the imperative widget while keeping the packaged application
      // CSS (including body typography) and the actual xterm renderer.
      await page.route('**/terminal-layout-fixture', route => route.fulfill({
        contentType: 'text/html',
        body: `<!doctype html>
          <link rel="stylesheet" href="/dist/browser/app.css">
          <link rel="stylesheet" href="/dist/browser/xterm.css">
          <div class="terminal-instance" style="display:block;width:428px;height:360px"></div>
          <script src="/dist/browser/xterm.js"></script>`,
      }));
      await page.goto('/terminal-layout-fixture');
      await page.evaluate(() => {
        const { Terminal, FitAddon } = globalThis.__openseek_xterm;
        const rootStyle = getComputedStyle(document.documentElement);
        const terminal = new Terminal({
          fontFamily: rootStyle.getPropertyValue('--font-family-mono').trim(),
          fontSize: 13,
        });
        const fit = new FitAddon();
        terminal.loadAddon(fit);
        terminal.open(document.querySelector('.terminal-instance'));
        window.terminalFixture = { terminal, fit };
      });
      for (const fontSize of [13, 15]) {
        for (const width of [428, 700, 360]) {
          await page.evaluate(async ({ fontSize, width }) => {
            const { terminal, fit } = window.terminalFixture;
            document.querySelector('.terminal-instance').style.width = `${width}px`;
            terminal.options.fontSize = fontSize;
            fit.fit();
            terminal.reset();
            await new Promise(resolve => terminal.write('0123456789'.repeat(40), resolve));
          }, { fontSize, width });
          await expect.poll(() => page.locator('.xterm-rows > div').evaluateAll(rows => {
            const populated = rows.filter(row => row.textContent.length > 0);
            return populated.length > 1 && populated.every(row =>
              // Allow pixel rounding, but never a clipped terminal cell.
              row.scrollWidth <= row.clientWidth + 1);
          }), { message: `row clipping at width=${width}, fontSize=${fontSize}` }).toBe(true);
        }
      }
      await page.evaluate(() => window.terminalFixture.terminal.dispose());
    });
  });
}
