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
      const systemFont = await page.evaluate(() =>
        getComputedStyle(document.documentElement).getPropertyValue('--font-family-mono').trim());
      for (const fontFamily of [systemFont, 'Menlo, monospace']) {
        for (const fontSize of [13, 15]) {
          for (const width of [428, 700, 360]) {
            await page.evaluate(async ({ fontFamily, fontSize, width }) => {
              const { terminal, fit } = window.terminalFixture;
              document.querySelector('.terminal-instance').style.width = `${width}px`;
              terminal.options.fontFamily = fontFamily;
              terminal.options.fontSize = fontSize;
              fit.fit();
              terminal.reset();
              const output = 'M'.repeat(terminal.cols - 1) + 'O\r\n' +
                'W'.repeat(terminal.cols - 1) + 'K\r\n' + '0123456789'.repeat(40);
              await new Promise(resolve => terminal.write(output, resolve));
            }, { fontFamily, fontSize, width });
            await expect.poll(() => page.locator('.xterm-rows > div').evaluateAll(rows => {
              const populated = rows.filter(row => row.textContent.length > 0);
              return populated.length > 1 && populated.every(row => {
                const text = document.createRange();
                text.selectNodeContents(row);
                // DOMRect retains subpixel precision; scrollWidth rounds away
                // the fractional glyph overflow that clips the final character.
                return text.getBoundingClientRect().right <=
                  row.getBoundingClientRect().right + 1 / 64;
              });
            }), { message: `row clipping with ${fontFamily}, width=${width}, fontSize=${fontSize}` }).toBe(true);
          }
        }
      }
      await page.evaluate(() => window.terminalFixture.terminal.dispose());
    });
  });
}
