import { test, expect } from '@playwright/test';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';

// Token is the mode a review opens in. Selecting a mode rebuilds the hunk
// surface even when it is the one already shown, and the controls are inert
// from the next render until that surface reports back. A focus() landing in
// that window is silently ignored, which leaves the following key outside the
// shortcut scope. Only select a mode that is not shown yet, so every wait
// below observes a real change.
async function selectDiffMode(page, mode) {
  const button = page.getByRole('button', { name: `${mode} diff`, exact: true });
  if (await button.getAttribute('aria-pressed') !== 'true') {
    await button.click();
    await expect(button).toHaveAttribute('aria-pressed', 'true');
  }
  await expect(page.locator('#review-navigation-controls')).toHaveAttribute('aria-busy', 'false');
}

// Let native scroll events and the two-frame outer reveal finish before
// checking the selected hunk; a transient toolbar label is not a landing.
async function settleReviewScroll(page) {
  await page.evaluate(async () => {
    for (let i = 0; i < 5; i++) await new Promise(requestAnimationFrame);
  });
}

{
  const mode = 'Tree';

  test(`${mode} each navigation click retains its target among short sections without Git refreshes`, async ({ page }) => {
    const app = new DesktopBrowserHarness(page);
    const baseline = Array.from({ length: 12 }, (_, i) => `fn value_${i}() -> Int {\n  ${i}\n}\n`).join('\n');
    app.gitFilesByRevision[app.gitBaseline]['src/main.mbt'] = baseline;
    app.workingFiles['src/main.mbt'] = baseline.replace(/\n  (\d+)\n/g, '\n  100 + $1\n');
    // Hold subsequent Git refresh responses after the initial review loads.
    // Navigation must publish its own state, even when host polling stalls.
    let pauseGitRefresh = false;
    let heldGitRefreshes = 0;
    const replyFor = app.replyFor.bind(app);
    app.replyFor = request => {
      if (pauseGitRefresh && request.method === 'git.changes') {
        heldGitRefreshes++;
        return new Promise(() => {});
      }
      return replyFor(request);
    };
    await app.install();
    await app.goto();
    await app.openSession();
    await app.openReview();
    await page.locator('#review-changes-body').getByRole('treeitem', { name: /View diff: src\/main\.mbt/ }).click();
    await selectDiffMode(page, mode);
    const position = page.locator('.review-hunk-position');
    await settleReviewScroll(page);
    await expect(position).toHaveText('Change 1 of 12');
    pauseGitRefresh = true;
    await expect.poll(() => heldGitRefreshes).toBeGreaterThan(0);
    for (let i = 2; i <= 12; i++) {
      await page.getByRole('button', { name: 'Next change', exact: true }).click();
      await settleReviewScroll(page);
      await expect(position).toHaveText(`Change ${i} of 12`, { timeout: 1500 });
      await expect(page.locator('.semantic-diff-entry').nth(i - 1).locator('.moonbit-diff-editor-modified .view-line').filter({ hasText: `100 + ${i - 1}` }).first()).toBeInViewport();
    }
    for (let i = 11; i >= 1; i--) {
      await page.getByRole('button', { name: 'Previous change', exact: true }).click();
      await settleReviewScroll(page);
      await expect(position).toHaveText(`Change ${i} of 12`, { timeout: 1500 });
      await expect(page.locator('.semantic-diff-entry').nth(i - 1).locator('.moonbit-diff-editor-modified .view-line').filter({ hasText: `100 + ${i - 1}` }).first()).toBeInViewport();
    }
    // Reading with the wheel must still update the active hunk after a reveal.
    await page.locator('#semantic-review-host').hover();
    await page.mouse.wheel(0, 700);
    await expect(position).not.toHaveText('Change 1 of 12');
    expect(app.pageErrors).toEqual([]);
  });
}

for (const mode of ['Line', 'Tree']) {
  test(`${mode} continuous navigation crosses files in both directions and wraps`, async ({ page }) => {
    const app = new DesktopBrowserHarness(page);
    const baseline = ['fn first() -> Int { 1 }', ...Array.from({ length: 8 }, (_, i) => `fn same_${i}() -> Int { ${i} }`), 'fn last() -> Int { 2 }', ''].join('\n\n');
    for (const path of ['src/main.mbt', 'src/lib.mbt']) {
      app.gitFilesByRevision[app.gitBaseline][path] = baseline;
      app.workingFiles[path] = baseline.replace('first() -> Int { 1 }', 'first() -> Int { 10 }').replace('last() -> Int { 2 }', 'last() -> Int { 20 }');
    }
    app.rpcDelays.set('git.original_file', 150);
    await app.install();
    await app.goto();
    await app.openSession();
    await app.openReview();
    const changes = page.locator('#review-changes-body');
    const main = changes.getByRole('treeitem', { name: /View diff: src\/main\.mbt/ });
    const lib = changes.getByRole('treeitem', { name: /View diff: src\/lib\.mbt/ });
    await main.click();
    await page.getByRole('button', { name: 'Show file tree', exact: true }).click();
    await page.getByRole('button', { name: `${mode} diff`, exact: true }).click();
    const navigation = page.getByRole('group', { name: 'Diff change navigation' });
    const position = navigation.locator('.review-hunk-position');
    await expect(navigation).toHaveCount(1);
    await expect(page.getByRole('group', { name: 'Changed file navigation' })).toHaveCount(0);
    await expect(position).toHaveText('Change 1 of 2');
    // Backward entry into an uncached file must survive its asynchronous read
    // and land on the last change, not the normal first-change initialization.
    await navigation.getByRole('button', { name: 'Previous change', exact: true }).click();
    await expect(lib).toHaveAttribute('aria-current', 'page');
    await expect(position).toHaveText('Change 2 of 2');
    await expect(navigation.locator('.review-nav-position')).toHaveText('File 2 of 2');
    await page.keyboard.press('p');
    await expect(position).toHaveText('Change 1 of 2');
    await expect(lib).toHaveAttribute('aria-current', 'page');
    await page.keyboard.press('p');
    await expect(main).toHaveAttribute('aria-current', 'page');
    await expect(position).toHaveText('Change 2 of 2');
    await page.keyboard.press('n');
    await expect(lib).toHaveAttribute('aria-current', 'page');
    await expect(position).toHaveText('Change 1 of 2');
    await navigation.getByRole('button', { name: 'Next change', exact: true }).click();
    await expect(position).toHaveText('Change 2 of 2');
    await page.keyboard.press('n');
    await expect(main).toHaveAttribute('aria-current', 'page');
    await expect(position).toHaveText('Change 1 of 2');
    expect(app.pageErrors).toEqual([]);
  });
}

{
  const mode = 'Tree';
  test(`${mode} n/p cycle skips marked hunks and files and m can reopen the completed cycle`, async ({ page }) => {
    const app = new DesktopBrowserHarness(page);
    const baseline = ['fn review {', ...Array.from({ length: 90 }, (_, i) => `  println("line ${i}")`), '}', ''].join('\n');
    for (const path of ['src/main.mbt', 'src/lib.mbt']) {
      app.gitFilesByRevision[app.gitBaseline][path] = baseline;
      app.workingFiles[path] = baseline.replace('line 5"', 'changed 5"').replace('line 45"', 'changed 45"').replace('line 85"', 'changed 85"');
    }
    await app.install();
    await app.goto();
    await app.openSession();
    await app.openReview();
    const changes = page.locator('#review-changes-body');
    const main = changes.getByRole('treeitem', { name: /View diff: src\/main\.mbt/ });
    const lib = changes.getByRole('treeitem', { name: /View diff: src\/lib\.mbt/ });
    await main.click();
    await page.getByRole('button', { name: 'Show file tree', exact: true }).click();
    await selectDiffMode(page, mode);
    const navigation = page.getByRole('group', { name: 'Diff change navigation' });
    const next = navigation.getByRole('button', { name: 'Next change', exact: true });
    const previous = navigation.getByRole('button', { name: 'Previous change', exact: true });
    const position = navigation.locator('.review-hunk-position');
    const mark = page.locator('.review-navigation-controls .review-progress');
    await expect(position).toHaveText('Change 1 of 3');
    await expect(next).toHaveAttribute('aria-keyshortcuts', 'n F7');
    await expect(previous).toHaveAttribute('aria-keyshortcuts', 'p Shift+F7');
    await expect(mark).toHaveAttribute('aria-keyshortcuts', 'm');
    await next.focus();
    await page.keyboard.press('n');
    await expect(position).toHaveText('Change 2 of 3');
    await page.keyboard.press('m');
    await expect(mark).toHaveAttribute('aria-pressed', 'true');
    await page.keyboard.press('n');
    await expect(position).toHaveText('Change 3 of 3');
    await page.keyboard.press('p');
    await expect(position).toHaveText('Change 1 of 3');
    await page.keyboard.press('n');
    await expect(position).toHaveText('Change 3 of 3');
    await page.keyboard.press('m');
    await expect(mark).toHaveAttribute('aria-pressed', 'true');
    await page.keyboard.press('n');
    await expect(lib).toHaveAttribute('aria-current', 'page');
    await expect(position).toHaveText('Change 1 of 3');
    // Backward cross-file entry skips the destination's marked final hunks.
    await page.keyboard.press('p');
    await expect(main).toHaveAttribute('aria-current', 'page');
    await expect(position).toHaveText('Change 1 of 3');
    await page.keyboard.press('m');
    await expect(page.getByRole('button', { name: 'Mark file unreviewed', exact: true })).toHaveAttribute('aria-pressed', 'true');
    await page.keyboard.press('n');
    await expect(lib).toHaveAttribute('aria-current', 'page');
    await expect(position).toHaveText('Change 1 of 3');
    await page.keyboard.press('n');
    await expect(position).toHaveText('Change 2 of 3');
    await page.keyboard.press('m');
    await expect(mark).toHaveAttribute('aria-pressed', 'true');
    await page.keyboard.press('n');
    await expect(position).toHaveText('Change 3 of 3');
    await page.keyboard.press('n');
    await expect(lib).toHaveAttribute('aria-current', 'page');
    await expect(position).toHaveText('Change 1 of 3');
    // With only this file outstanding, wrap also excludes its marked middle hunk.
    await page.keyboard.press('p');
    await expect(position).toHaveText('Change 3 of 3');
    await page.keyboard.press('m');
    await expect(mark).toHaveAttribute('aria-pressed', 'true');
    await page.keyboard.press('n');
    await expect(position).toHaveText('Change 1 of 3');
    await page.keyboard.press('m');
    await expect(next).toBeDisabled();
    await expect(previous).toBeDisabled();
    await mark.focus();
    await page.keyboard.press('m');
    await expect(mark).toHaveAttribute('aria-pressed', 'false');
    await expect(next).toBeEnabled();
    await page.keyboard.press('n');
    await expect(lib).toHaveAttribute('aria-current', 'page');
    await expect(position).toHaveText('Change 1 of 3');
    expect(app.pageErrors).toEqual([]);
  });
}

test('review shortcuts preserve modified keys, composition, repeats, and feedback typing', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  await app.install();
  await app.goto();
  await app.openSession();
  await app.openReview();
  await page.getByRole('button', { name: 'Expand panel', exact: true }).click();
  const changes = page.locator('#review-changes-body');
  const main = changes.getByRole('treeitem', { name: /View diff: src\/main\.mbt/ });
  await main.click();
  await page.getByRole('button', { name: 'Show file tree', exact: true }).click();
  await page.getByRole('button', { name: 'Line diff', exact: true }).click();
  const next = page.getByRole('button', { name: 'Next change', exact: true });
  const consumed = await next.evaluate(button => ['ctrlKey', 'altKey', 'metaKey', 'shiftKey', 'isComposing', 'repeat'].map(flag => {
    const event = new KeyboardEvent('keydown', { key: 'm', bubbles: true, cancelable: true, [flag]: true });
    button.dispatchEvent(event);
    return event.defaultPrevented;
  }));
  expect(consumed).toEqual([false, false, false, false, false, false]);
  const modified = page.locator('.moonbit-diff-editor:visible .moonbit-diff-editor-modified');
  await modified.locator('.view-line').filter({ hasText: 'working tree' }).first().hover();
  await modified.locator('.agent-feedback-glyph.line-hover').click();
  const feedback = page.locator('.agent-feedback-input-widget textarea');
  await expect(feedback).toBeVisible();
  await feedback.pressSequentially('npm');
  await expect(feedback).toHaveValue('npm');
  await expect(main).toHaveAttribute('aria-current', 'page');
  await expect(page.getByRole('button', { name: 'Mark hunk viewed', exact: true })).toHaveAttribute('aria-pressed', 'false');
  expect(app.pageErrors).toEqual([]);
});
