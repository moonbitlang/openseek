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
    // Check the actual browser contract rather than grepping MoonBit view
    // code: an ancestor disappearing is just as much an unmount as removing
    // the dialog itself. Native close clears `open` synchronously.
    const unmounted = [];
    await context.exposeBinding('__reportUnmountedRuiDialog', (_, id) => unmounted.push(id));
    await context.addInitScript(() => {
      if (window !== window.top) return;
      const selector = 'dialog[data-slot="dialog"][open]';
      new MutationObserver(records => {
        for (const record of records) for (const node of record.removedNodes) {
          if (!(node instanceof Element) || node.isConnected) continue;
          const dialog = node.matches(selector) ? node : node.querySelector(selector);
          if (dialog) void window.__reportUnmountedRuiDialog(dialog.id || '(unnamed dialog)');
        }
      }).observe(document, { subtree: true, childList: true });
    });
    await use(context);
    expect(unmounted, 'Open RUI dialogs were unmounted without native close').toEqual([]);
  },
});

export { expect };
