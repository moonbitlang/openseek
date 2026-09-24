import { expect, gotoBrowserScenario, test } from '../support/test.js';

const documentRoot = '.markdown-feedback-host .moonbit-viewer-markdown-document';
const widget = '.agent-feedback-input-widget';
const article = '.markdown-feedback-host .moonbit-viewer-markdown-document-article';
const viewport = '.markdown-feedback-host .moonbit-viewer-markdown-document-viewport';
const addSelection = 'button[data-markdown-feedback-add]';
const input = 'textarea[data-agent-feedback-input]';
const firstParagraph = '这个功能支持 **自动保存**，也支持手动保存。';
const secondParagraph = '第二段包含 *独立说明*，用于跨段选择。';

async function openFixture(page) {
  await page.route('**/browser-tests/feedback-fixture.svg', (route) => route.fulfill({
    contentType: 'image/svg+xml',
    body: '<svg xmlns="http://www.w3.org/2000/svg" width="120" height="50"><rect width="120" height="50" fill="cornflowerblue"/></svg>',
  }));
  await gotoBrowserScenario(page, 'markdown-feedback');
  await expect(page.locator(article)).toContainText('自动保存');
}

// Native Selection and Range are the contract under test. Source positions
// are never supplied to the Viewer; it must derive them from rendered nodes.
async function selectRenderedText(page, startText, endText = startText, reverse = false) {
  await page.locator(documentRoot).focus();
  await page.locator(article).evaluate((root, { startText, endText, reverse }) => {
    const textNodes = [];
    const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
    while (walker.nextNode()) textNodes.push(walker.currentNode);
    const start = textNodes.find((node) => node.textContent.includes(startText));
    const end = textNodes.find((node) => node.textContent.includes(endText));
    if (!start || !end) throw new Error(`missing rendered selection: ${startText} / ${endText}`);
    start.parentElement.scrollIntoView({ block: 'center' });
    const range = document.createRange();
    range.setStart(start, start.textContent.indexOf(startText));
    range.setEnd(end, end.textContent.indexOf(endText) + endText.length);
    const selection = root.ownerDocument.getSelection();
    selection.removeAllRanges();
    if (reverse) {
      selection.setBaseAndExtent(end, range.endOffset, start, range.startOffset);
    } else {
      selection.addRange(range);
    }
  }, { startText, endText, reverse });
  await expect(page.locator(input)).toBeVisible();
  await expect(page.locator(input)).not.toBeFocused();
  await expect(page.locator(addSelection)).toHaveCount(0);
}

async function openComposer(page, startText, endText = startText) {
  await selectRenderedText(page, startText, endText);
  await page.locator(input).click();
  await expect(page.locator(input)).toBeFocused();
}

async function feedbackFacts(page) {
  return page.evaluate(() => globalThis.__markdownFeedbackControls.getFeedback());
}

test('rendered emphasis quotes only selected text while locating its complete source paragraph', async ({ page }) => {
  await openFixture(page);
  await openComposer(page, '自动保存');
  await page.locator(input).fill('说明自动保存的时机');
  await page.locator('.agent-feedback-input-action-add').click();

  await expect.poll(async () => (await feedbackFacts(page)).items.length).toBe(1);
  const facts = await feedbackFacts(page);
  expect(facts.submitted).toBe(0);
  expect(facts.items[0]).toMatchObject({
    text: '说明自动保存的时机',
    selected_text: '自动保存',
    resource: 'inmemory://component/feedback.md',
    submitted: false,
  });
  expect(facts.items[0].range.slice(0, 2)).toEqual([3, 1]);
  expect(facts.items[0].source.trimEnd()).toBe(firstParagraph);
  await expect(page.locator(input)).not.toBeVisible();
});

test('cross-paragraph feedback keeps exact rendered text and a complete source span', async ({ page }) => {
  await openFixture(page);
  await openComposer(page, '自动保存', '独立说明');
  await page.locator(input).fill('合并这两段说明');
  await page.locator('.agent-feedback-input-action-apply').click();

  await expect.poll(async () => (await feedbackFacts(page)).submitted).toBe(1);
  const facts = await feedbackFacts(page);
  expect(facts.items).toHaveLength(1);
  expect(facts.items[0]).toMatchObject({
    text: '合并这两段说明',
    selected_text: '自动保存，也支持手动保存。\n\n第二段包含 独立说明',
    submitted: true,
  });
  expect(facts.items[0].range.slice(0, 2)).toEqual([3, 1]);
  expect(facts.items[0].source.trimEnd()).toBe(`${firstParagraph}\n\n${secondParagraph}`);
});

test('lists, tables, code, and images preserve their selected text independently of source ranges', async ({ page }) => {
  await openFixture(page);
  const cases = [
    { text: 'review target', source: 'Nested **review target** has details.' },
    { text: 'table target', source: '**table target** with context' },
    { text: 'code target', source: 'code target with context' },
  ];
  for (const [index, item] of cases.entries()) {
    await openComposer(page, item.text);
    await page.locator(input).fill(`Review ${item.text}`);
    await page.locator('.agent-feedback-input-action-add').click();
    await expect.poll(async () => (await feedbackFacts(page)).items.length).toBe(index + 1);
    const saved = (await feedbackFacts(page)).items[index];
    expect(saved.selected_text).toBe(item.text);
    expect(saved.source).toContain(item.source);
    expect(saved.source).not.toContain('Unselected tail paragraph');
    expect(saved.source).not.toContain(firstParagraph);
    expect(saved.range[0]).toBeGreaterThan(5);
  }

  const image = page.locator(`${article} img[alt="Feedback image"]`);
  await expect.poll(async () => image.evaluate((node) => node.naturalWidth)).toBe(120);
  await page.locator(documentRoot).focus();
  const selectedText = await image.evaluate((node) => {
    node.scrollIntoView({ block: 'center' });
    const range = node.ownerDocument.createRange();
    range.selectNode(node);
    const selection = node.ownerDocument.getSelection();
    selection.removeAllRanges();
    selection.addRange(range);
    return selection.toString();
  });
  expect(selectedText).toBe('');
  await expect(page.locator(input)).toBeVisible();
  await expect(page.locator(input)).not.toBeFocused();
  await page.locator(input).click();
  await expect(page.locator(input)).toBeFocused();
  await page.locator(input).fill('Explain this image');
  await page.locator('.agent-feedback-input-action-add').click();
  await expect.poll(async () => (await feedbackFacts(page)).items.length).toBe(4);
  const savedImage = (await feedbackFacts(page)).items[3];
  // An image-only native selection has text "", distinct from a selection
  // with no supplied text. Do not replace it with Markdown or image alt text.
  expect(savedImage.selected_text).toBe('');
  expect(savedImage.source.trimEnd()).toBe(
    '![Feedback image](https://example.test/browser-tests/feedback-fixture.svg)',
  );
});

for (const change of ['setSource', 'replaceSameUri']) {
  test(`a draft cannot submit stale source after ${change}`, async ({ page }) => {
    await openFixture(page);
    await openComposer(page, '自动保存');
    await page.locator(input).fill('This draft refers to the old paragraph');

    const replacement = '# Replacement\n\nNew **replacement selection** has fresh context.\n\n' +
      Array.from({ length: 10 }, (_, index) => `Trailing paragraph ${index}.`).join('\n\n');
    await page.evaluate(({ change, replacement }) => {
      globalThis.__markdownFeedbackControls[change](replacement);
    }, { change, replacement });
    await expect(page.locator(article)).toContainText('replacement selection');
    await expect(page.locator(input)).not.toBeVisible();
    await expect(page.locator(addSelection)).not.toBeVisible();
    await page.keyboard.press('Enter');
    expect(await feedbackFacts(page)).toEqual({ items: [], submitted: 0 });

    await openComposer(page, 'replacement selection');
    await page.locator(input).fill('This draft uses the current document');
    // Its entrance animation translates the composer. Measure the settled
    // position so the subsequent delta observes scrolling alone.
    await page.locator('.agent-feedback-input-widget').evaluate((node) =>
      Promise.all(node.getAnimations().map((animation) => animation.finished)),
    );
    const beforeScroll = await page.locator(input).boundingBox();
    expect(beforeScroll).not.toBeNull();
    await page.locator(viewport).evaluate((node) => { node.scrollTop += 24; });
    await expect.poll(async () => page.locator(viewport).evaluate((node) => node.scrollTop)).toBe(24);
    await expect(page.locator(input)).toBeVisible();
    await expect(page.locator(input)).toHaveValue('This draft uses the current document');
    await expect.poll(async () => (await page.locator(input).boundingBox())?.y).toBeCloseTo(beforeScroll.y - 24, 0);
    await page.locator('.agent-feedback-input-action-add').click();
    await expect.poll(async () => (await feedbackFacts(page)).items.length).toBe(1);
    const saved = (await feedbackFacts(page)).items[0];
    expect(saved.selected_text).toBe('replacement selection');
    expect(saved.source.trimEnd()).toBe('New **replacement selection** has fresh context.');
    expect(saved.range.slice(0, 2)).toEqual([3, 1]);
  });
}

async function settleComposer(page) {
  await page.locator(widget).evaluate((node) =>
    Promise.all(node.getAnimations().map((animation) => animation.finished)),
  );
}

async function selectionFrame(page) {
  await page.evaluate(() => new Promise((resolve) =>
    requestAnimationFrame(() => requestAnimationFrame(resolve)),
  ));
}

test('mouse selection opens after release, preserves document focus, and supports shared keyboard actions', async ({ page }) => {
  await openFixture(page);
  const textBox = await page.locator(`${article} strong`).first().evaluate((node) => {
    node.scrollIntoView({ block: 'center' });
    const range = document.createRange();
    range.selectNodeContents(node);
    return range.getBoundingClientRect().toJSON();
  });
  await page.mouse.move(textBox.x + 1, textBox.y + textBox.height / 2);
  await page.mouse.down();
  await page.mouse.move(textBox.right - 1, textBox.y + textBox.height / 2, { steps: 6 });
  await expect.poll(() => page.evaluate(() => window.getSelection().toString())).toBe('自动保存');
  await selectionFrame(page);
  await expect(page.locator(input)).not.toBeVisible();
  await page.mouse.up();
  await expect(page.locator(input)).toBeVisible();
  await expect(page.locator(input)).not.toBeFocused();
  await expect(page.locator(documentRoot)).toBeFocused();
  await expect(page.locator(addSelection)).toHaveCount(0);

  await page.keyboard.press('ControlOrMeta+i');
  await expect(page.locator(input)).toBeFocused();
  await page.locator(input).fill('First line');
  await page.locator(input).press('Shift+Enter');
  await expect(page.locator(input)).toHaveValue('First line\n');
  expect((await feedbackFacts(page)).items).toHaveLength(0);
  await page.locator(input).press('Enter');
  await expect.poll(async () => (await feedbackFacts(page)).items.length).toBe(1);
  expect((await feedbackFacts(page)).submitted).toBe(0);

  await selectRenderedText(page, '独立说明');
  await page.keyboard.press('ControlOrMeta+i');
  await expect(page.locator(input)).toBeFocused();
  await page.locator(input).fill('Apply the batch');
  await page.locator(input).press('Alt+Enter');
  await expect.poll(async () => (await feedbackFacts(page)).submitted).toBe(2);
  await expect(page.locator(input)).not.toBeVisible();
});

test('empty drafts follow reselection, typed drafts keep source and selected text, and dismissed selections stay closed', async ({ page }) => {
  await openFixture(page);
  await page.evaluate(() => {
    const controls = globalThis.__markdownFeedbackControls;
    controls.setSource(controls.getSource() + '\n\n## Later section\n\n## Final section');
  });
  await expect(page.locator('.moonbit-viewer-markdown-toc-toggle')).toBeVisible();
  await selectRenderedText(page, '自动保存');
  await selectRenderedText(page, '独立说明');
  await page.locator(input).fill('Keep this source target');
  await selectRenderedText(page, '自动保存');
  await expect(page.locator(input)).toHaveValue('Keep this source target');
  await page.evaluate(() => {
    globalThis.__lastFeedbackSelection = window.getSelection().getRangeAt(0).cloneRange();
  });
  await page.locator('.agent-feedback-input-action-add').click();
  await expect.poll(async () => (await feedbackFacts(page)).items.length).toBe(1);
  expect((await feedbackFacts(page)).items[0].selected_text).toBe('独立说明');
  expect((await feedbackFacts(page)).items[0].source.trimEnd()).toBe(secondParagraph);
  // The dismissed UI must suppress the live selection, even when a typed
  // draft was pinned to a different source block. Refocus/selection events
  // and scrolling must not immediately reopen that live range.
  await page.locator(documentRoot).focus();
  await page.evaluate(() => {
    const selection = window.getSelection();
    selection.removeAllRanges();
    selection.addRange(globalThis.__lastFeedbackSelection);
  });
  await page.locator(viewport).evaluate((node) => { node.scrollTop += 12; });
  await selectionFrame(page);
  await expect(page.locator(input)).not.toBeVisible();

  const rootBox = await page.locator(documentRoot).boundingBox();
  // A click in the article's empty right padding collapses the selection.
  await selectRenderedText(page, '独立说明');
  await page.mouse.click(rootBox.x + rootBox.width - 20, rootBox.y + 100);
  await expect(page.locator(input)).not.toBeVisible();

  for (const dismiss of ['Escape', 'Cancel', 'Add']) {
    // A real new mouse gesture clears the previous dismissal, even when it
    // selects the same text. Double-click is a native word selection.
    await page.locator(`${article} strong`).first().dblclick();
    await expect(page.locator(input)).toBeVisible();
    await page.evaluate(() => {
      globalThis.__lastFeedbackSelection = window.getSelection().getRangeAt(0).cloneRange();
    });
    if (dismiss === 'Escape') {
      await page.keyboard.press('Escape');
    } else if (dismiss === 'Cancel') {
      await page.locator('.agent-feedback-input-action-cancel').click();
    } else {
      await page.locator(input).fill('Final feedback');
      await page.locator('.agent-feedback-input-action-add').click();
    }
    await expect(page.locator(input)).not.toBeVisible();
    if (dismiss === 'Escape') {
      const selectedText = await page.evaluate(() => window.getSelection().toString());
      await page.locator('.moonbit-viewer-markdown-toc-toggle').click();
      expect(await page.evaluate(() => window.getSelection().toString())).toBe(selectedText);
      await selectionFrame(page);
      await expect(page.locator(input)).not.toBeVisible();
      await page.locator('.moonbit-viewer-markdown-toc-toggle').click();
    }
    await page.locator(documentRoot).focus();
    await page.evaluate(() => {
      const selection = window.getSelection();
      selection.removeAllRanges();
      selection.addRange(globalThis.__lastFeedbackSelection);
    });
    await page.locator(viewport).evaluate((node) => { node.scrollTop += 12; });
    await selectionFrame(page);
    await expect(page.locator(input)).not.toBeVisible();
  }
});

test('composer follows the active selection endpoint and fits a narrow document on first display', async ({ page }) => {
  await openFixture(page);
  // Use the already-rendered code fence as the editor-font oracle: prose and
  // the feedback widget have different DOM ancestors and must not inherit
  // different typefaces. Check the initial textarea before any input event.
  const editorFont = await page.locator(`${article} .moonbit-viewer-markdown-code-block .monaco-tokenized-source`)
    .evaluate((node) => getComputedStyle(node).fontFamily);
  await selectRenderedText(page, '自动保存');
  await settleComposer(page);
  expect(await page.locator(input).evaluate((node) => getComputedStyle(node).fontFamily)).toBe(editorFont);
  expect((await page.locator(input).boundingBox()).height).toBe(64);
  const source = Array.from({ length: 20 }, (_, index) =>
    index === 8 ? 'Start **anchor start** with some context.' :
      index === 9 ? 'The final **anchor finish** follows here.' : `Paragraph ${index}.`,
  ).join('\n\n');
  await page.evaluate((source) => globalThis.__markdownFeedbackControls.setSource(source), source);
  await expect(page.locator(article)).toContainText('anchor finish');

  for (const reverse of [false, true]) {
    await selectRenderedText(page, 'anchor start', 'anchor finish', reverse);
    await settleComposer(page);
    const focus = await page.evaluate(() => {
      const selection = window.getSelection();
      const caret = document.createRange();
      caret.setStart(selection.focusNode, selection.focusOffset);
      caret.collapse(true);
      return caret.getBoundingClientRect().toJSON();
    });
    const composer = await page.locator(widget).boundingBox();
    if (reverse) {
      expect(composer.y + composer.height).toBeLessThanOrEqual(focus.top);
    } else {
      expect(composer.y).toBeGreaterThanOrEqual(focus.bottom);
    }
    // Both endpoints have ample horizontal space; the widget starts at the
    // active caret, not at the bounding rectangle of the whole selection.
    expect(composer.x).toBeCloseTo(focus.left, 0);
    await page.keyboard.press('Escape');
    const bounds = await page.locator(documentRoot).boundingBox();
    await page.mouse.click(bounds.x + bounds.width - 20, bounds.y + 100);
  }

  await page.locator('.markdown-feedback-host').evaluate((node) => { node.style.width = '320px'; });
  await selectRenderedText(page, 'anchor finish');
  await settleComposer(page);
  const root = await page.locator(documentRoot).boundingBox();
  const composer = await page.locator(widget).boundingBox();
  const textarea = await page.locator(input).boundingBox();
  expect(composer.width).toBeLessThanOrEqual(root.width * 0.9 + 1);
  expect(composer.x).toBeGreaterThanOrEqual(root.x);
  expect(composer.x + composer.width).toBeLessThanOrEqual(root.x + root.width);
  expect(composer.y).toBeGreaterThanOrEqual(root.y);
  expect(composer.y + composer.height).toBeLessThanOrEqual(root.y + root.height);
  expect(textarea.height).toBe(64);
  await expect(page.locator(input)).not.toBeFocused();
});
