import { expect, gotoBrowserScenario, test } from '../support/test.js';
import {
  expectMoonBitReportPassed,
  installMoonBitReporter,
} from '../support/moonbit_reporter.js';

const codeEditor =
  '.peek-references-code-host > .monaco-editor.readonly-editor';
const codePeek = `${codeEditor} .moonbit-viewer-references-peek`;
const codePreview =
  `${codePeek} .moonbit-viewer-references-peek-preview > ` +
  '.monaco-editor.readonly-editor';
const resultTree = '.moonbit-viewer-reference-results-tree';
const groupRow = '[data-reference-row-kind="group"]';
const referenceRow = '[data-reference-row-kind="reference"]';

async function settle(page) {
  await page.evaluate(
    () =>
      new Promise((resolve) =>
        requestAnimationFrame(() => requestAnimationFrame(resolve)),
      ),
  );
}

async function mountPeekReferencesFixture(page, testInfo) {
  const reporter = await installMoonBitReporter(page);
  await gotoBrowserScenario(page, 'peek-references');
  await page.waitForFunction(() =>
    Boolean(globalThis.__peekReferencesControls),
  );
  const report = await reporter.waitForReport(testInfo, {
    suite: 'peek_references',
    timeout: 10_000,
  });
  expectMoonBitReportPassed(report, { suite: 'peek_references' });
  await expect(page.locator(codeEditor)).toContainText('anchor here');
  await settle(page);
  return reporter;
}

async function control(page, method) {
  await page.evaluate(
    (name) => globalThis.__peekReferencesControls[name](),
    method,
  );
}

async function state(page) {
  return page.evaluate(() => globalThis.__peekReferencesControls.state());
}

function treeIn(page, peekSelector = codePeek) {
  return page.locator(peekSelector).locator(resultTree);
}

function group(tree, index) {
  return tree.locator(
    `${groupRow}[data-reference-group-index="${index}"]`,
  );
}

function reference(tree, flatIndex) {
  return tree.locator(
    `${referenceRow}[data-reference-flat-index="${flatIndex}"]`,
  );
}

test('public locations render an accessible lazy tree, snippets, and decorated previews', async ({
  page,
}, testInfo) => {
  const reporter = await mountPeekReferencesFixture(page, testInfo);
  try {
    await control(page, 'show_code');

    const dialog = page.locator(codePeek);
    const tree = treeIn(page);
    await expect(dialog).toHaveAttribute('role', 'dialog');
    await expect(dialog).toHaveAttribute('aria-label', 'Peek References');
    await expect(tree).toHaveAttribute('role', 'tree');
    await expect(tree).toHaveAttribute(
      'aria-label',
      'Found 6 results in 3 files',
    );
    await expect(dialog.locator(groupRow)).toHaveCount(3);

    // Explicitly supplied results replace the existing Peek at this anchor.
    await control(page, 'show_code');
    await expect(dialog).toBeVisible();
    await expect(tree).toHaveAttribute('aria-label', 'Found 6 results in 3 files');

    const remoteGroup = group(tree, 0);
    const sourceGroup = group(tree, 1);
    const otherGroup = group(tree, 2);
    await expect(remoteGroup).toHaveAttribute('aria-expanded', 'false');
    await expect(remoteGroup).toHaveAttribute(
      'aria-label',
      '2 results in remote.mbt, full path lib',
    );
    await expect(sourceGroup).toHaveAttribute('aria-expanded', 'true');
    await expect(sourceGroup).toContainText('source.mbt');
    await expect(sourceGroup.locator('.moonbit-viewer-reference-results-file-parent')).toHaveText('src');
    await expect(sourceGroup).toHaveAttribute('title', 'src/source.mbt');
    await expect(remoteGroup).toHaveAttribute('title', 'lib/remote.mbt');
    await expect(sourceGroup).toContainText('3');
    await expect(otherGroup).toHaveAttribute('aria-expanded', 'false');

    const initial = reference(tree, 4);
    await expect(initial).toHaveAttribute('aria-selected', 'true');
    await expect(initial).toHaveAttribute('tabindex', '0');
    await expect(initial).toHaveAttribute(
      'aria-label',
      'target again in source.mbt on line 3 at column 1',
    );
    await expect(
      initial.locator('.moonbit-viewer-reference-results-snippet-match'),
    ).toHaveText('target');
    await expect(page.locator(codePreview)).toContainText('target again');
    await expect
      .poll(async () => (await state(page)).resolverCalls)
      .toBe(0);

    await expect(
      page.locator(
        `${codePreview} ` +
          '.moonbit-viewer-references-peek-reference-match-selected',
      ),
    ).toHaveCount(1);
    await expect(
      page.locator(
        `${codePreview} ` +
          '.moonbit-viewer-references-peek-reference-match',
      ),
    ).toHaveCount(3);

    await remoteGroup.click();
    await expect(remoteGroup).toHaveAttribute('aria-expanded', 'true');
    await expect
      .poll(async () => (await state(page)).resolverCalls)
      .toBe(1);
    const firstRemote = reference(tree, 0);
    await expect(
      firstRemote.locator(
        '.moonbit-viewer-reference-results-snippet-match',
      ),
    ).toHaveText('target');
    await expect(firstRemote).toHaveAttribute(
      'aria-label',
      'remote target value in remote.mbt on line 1 at column 8',
    );

    await remoteGroup.click();
    await expect(remoteGroup).toHaveAttribute('aria-expanded', 'false');
    await remoteGroup.click();
    await expect(remoteGroup).toHaveAttribute('aria-expanded', 'true');
    expect((await state(page)).resolverCalls).toBe(1);

    await firstRemote.click();
    await expect(firstRemote).toHaveAttribute('aria-selected', 'true');
    await expect
      .poll(async () => (await state(page)).resolverCalls)
      .toBe(2);
    await expect(page.locator(codePreview)).toContainText(
      'remote target value',
    );
    await expect(
      page.locator(
        `${codePreview} ` +
          '.moonbit-viewer-references-peek-reference-match-selected',
      ),
    ).toHaveCount(1);
    await expect(
      page.locator(
        `${codePreview} ` +
          '.moonbit-viewer-references-peek-reference-match',
      ),
    ).toHaveCount(2);

    await page.keyboard.press('Escape');
    await expect(dialog).toHaveCount(0);
    await expect
      .poll(async () => (await state(page)).resolverReleases)
      .toBe(2);
    await expect
      .poll(async () => (await state(page)).codeHasTextFocus)
      .toBe(true);
  } finally {
    reporter.dispose();
  }
});

test('Enter uses Current and Ctrl+Enter uses Side before closing Peek', async ({
  page,
}, testInfo) => {
  const reporter = await mountPeekReferencesFixture(page, testInfo);
  try {
    await control(page, 'clear_opens');
    await control(page, 'show_code');
    const tree = treeIn(page);
    await group(tree, 0).click();
    const firstRemote = reference(tree, 0);
    await firstRemote.click();
    await expect(page.locator(codePreview)).toContainText(
      'remote target value',
    );
    await page.keyboard.press('Enter');
    await expect(page.locator(codePeek)).toHaveCount(0);
    await expect
      .poll(async () => (await state(page)).openModes)
      .toEqual(['Current']);
    expect((await state(page)).openUris[0]).toContain(
      '/workspace/lib/remote.mbt',
    );
    expect((await state(page)).openLines).toEqual([1]);
    expect((await state(page)).openColumns).toEqual([8]);

    await control(page, 'clear_opens');
    await control(page, 'show_code');
    const selected = reference(treeIn(page), 4);
    await expect(selected).toHaveAttribute('aria-selected', 'true');
    await selected.press('Control+Enter');
    await expect(page.locator(codePeek)).toHaveCount(0);
    await expect
      .poll(async () => (await state(page)).openModes)
      .toEqual(['Side']);
    expect((await state(page)).openUris[0]).toContain(
      '/workspace/src/source.mbt',
    );
    expect((await state(page)).openLines).toEqual([3]);
    expect((await state(page)).openColumns).toEqual([1]);
  } finally {
    reporter.dispose();
  }
});
