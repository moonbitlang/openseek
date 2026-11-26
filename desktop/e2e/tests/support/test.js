import { test as base, expect } from '@playwright/test';

// Playwright clicks only an element whose box is unchanged across two
// animation frames. Transitions and entrance animations keep moving the target,
// so each affected click retries for up to 720ms. Tests run without motion
// unless they are tagged `@motion` because they check motion itself.
const stillCSS = '*, *::before, *::after { transition: none !important; animation: none !important; }';

export const test = base.extend({
  context: async ({ context }, use, testInfo) => {
    if (!testInfo.tags.includes('@motion')) {
      // A constructed sheet adds no DOM node that a test could observe.
      await context.addInitScript(css => {
        const sheet = new CSSStyleSheet();
        sheet.replaceSync(css);
        document.adoptedStyleSheets = [...document.adoptedStyleSheets, sheet];
      }, stillCSS);
    }
    await use(context);
  },
  page: async ({ page }, use, testInfo) => {
    const pageErrors = [];
    page.on('pageerror', error => pageErrors.push(error.message));
    await use(page);
    if (!testInfo.tags.includes('@allow-pageerror')) {
      expect(pageErrors, 'Unexpected uncaught page errors').toEqual([]);
    }
  },
});

export { expect };
