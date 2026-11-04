import { execFileSync } from 'node:child_process';
import { existsSync, readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { chromium } from '../e2e/node_modules/playwright/index.mjs';
import { DesktopBrowserHarness } from '../e2e/tests/support/desktop_browser_harness.js';

const repo = fileURLToPath(new URL('../../', import.meta.url));
const assets = fileURLToPath(new URL('../dist/browser/', import.meta.url));
const origin = 'http://127.0.0.1:5175';

// Keep measured widgets on the real xterm renderer. Unlike ordinary CSS,
// xterm options must be refreshed when a palette changes within one mode.
const paletteTerminal = `
const terminals = new Set();
const OriginalTerminal = globalThis.__openseek_xterm.Terminal;
globalThis.__openseek_xterm.Terminal = class extends OriginalTerminal {
  constructor(options) { super(options); terminals.add(this); }
  dispose() { terminals.delete(this); super.dispose(); }
};
window.addEventListener('theme-lab-palette', () => {
  const style = getComputedStyle(document.documentElement);
  for (const terminal of terminals) {
    terminal.options.theme = {
      background: style.getPropertyValue('--color-bg-surface').trim(),
      foreground: style.getPropertyValue('--color-text-primary').trim(),
      cursor: style.getPropertyValue('--color-text-primary').trim(),
      selectionBackground: style.getPropertyValue('--color-text-selection').trim(),
      selectionInactiveBackground: style.getPropertyValue('--color-text-selection').trim(),
    };
  }
});
`;

export async function openThemeLab(page) {
  // Nothing may fall through to real authentication, model, or Host services.
  await page.context().route('**/*', route => route.abort('blockedbyclient'));
  const app = new DesktopBrowserHarness(page);
  app.liveSessions[0].title = 'Review the application theme';
  app.sessionEvents = [
    { sequence: 1, item: { kind: 'user', payload: { content: 'Check the application colors and the file panel.' } } },
    { sequence: 2, item: { kind: 'assistant', payload: { content: '## Theme review\n\nThe preview uses the **real application components**, including the composer and file viewer.\n\n- Inspect text and surface contrast.\n- Open menus and settings to check interaction states.\n\n```moonbit\nfn main {\n  println("Hello, SeekMoon")\n}\n```' } } },
    { sequence: 3, item: { kind: 'assistant', payload: { content: '', tool_calls: [{ id: 'theme-check', name: 'mbtx', arguments: JSON.stringify({ source: 'fn main { println("Preview ready") }' }) }] } } },
    { sequence: 4, item: { kind: 'tool_result', payload: { tool_call_id: 'theme-check', tool_name: 'mbtx', content: 'Preview ready', is_error: false, brief: 'Check theme preview' } } },
    { sequence: 5, item: { kind: 'assistant', payload: { content: 'Open [src/main.mbt](src/main.mbt) or [README.md](README.md) to inspect the editor and Markdown preview. No commands or model calls are executed in this demo.' } } },
  ];
  app.directoryEntries['/workspace'] = [
    { name: 'src', is_dir: true },
    { name: 'README.md', is_dir: false },
  ];
  app.directoryEntries['/workspace/src'] = [
    { name: 'main.mbt', is_dir: false },
    { name: 'lib.mbt', is_dir: false },
  ];
  app.workingFiles['README.md'] = '# Theme preview\n\nRendered by the real **SeekMoon** Markdown viewer.\n\n> Open settings, menus, and the terminal to inspect more components.\n';
  await app.install({ offlineAssets: assets });
  for (const [path, file, contentType] of [
    ['/dev/theme-lab.html', new URL('./theme-lab.html', import.meta.url), 'text/html'],
    ['/styles/palette-light.css', new URL('../styles/palette-light.css', import.meta.url), 'text/css'],
    ['/styles/palette-dark.css', new URL('../styles/palette-dark.css', import.meta.url), 'text/css'],
  ]) {
    await page.route(origin + path, route => route.fulfill({ contentType, body: readFileSync(file) }));
  }
  await page.route(origin + '/assets/xterm.js', route => route.fulfill({
    contentType: 'text/javascript',
    body: readFileSync(new URL('../dist/browser/assets/xterm.js', import.meta.url), 'utf8') + '\n' + paletteTerminal,
  }));
  await page.addInitScript(() => {
    // The palette editor owns appearance; the real app follows system changes.
    localStorage.setItem('openseek.theme', 'system');
  });
  await page.exposeFunction('themeLabSetMode', mode => page.emulateMedia({ colorScheme: mode }));
  await page.goto(origin + '/dev/theme-lab.html');
  const preview = page.frameLocator('#preview');
  await preview.locator('#task').waitFor();
  await preview.locator('.transcript').getByText('src/main.mbt', { exact: true }).click();
  await preview.locator('.editor-tab.active').waitFor();
  return app;
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  execFileSync(process.execPath, ['desktop/package/build.mjs', 'browser', '--release'], { cwd: repo, stdio: 'inherit' });
  const context = await chromium.launchPersistentContext(
    fileURLToPath(new URL('../target/theme-lab-profile/', import.meta.url)),
    {
      headless: false,
      // Some test setups install only the headless shell. Reuse Chrome
      // instead of downloading another browser for this development tool.
      channel: existsSync(chromium.executablePath()) ? undefined : 'chrome',
      viewport: { width: 1700, height: 1100 },
      serviceWorkers: 'block',
    },
  );
  const page = context.pages()[0];
  await openThemeLab(page);
  console.log('Theme Lab is ready. Close the browser to exit. Demo data only; no real Host or model is connected.');
}
