import { expect, gotoBrowserScenario, test } from '../support/test.js';

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
async function selectRenderedText(page, startText, endText = startText) {
  await page.locator(article).evaluate((root, { startText, endText }) => {
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
    selection.addRange(range);
  }, { startText, endText });
  await expect(page.locator(addSelection)).toBeVisible();
}

async function openComposer(page, startText, endText = startText) {
  await selectRenderedText(page, startText, endText);
  await page.locator(addSelection).click();
  await expect(page.locator(input)).toBeFocused();
}

async function feedbackFacts(page) {
  return page.evaluate(() => globalThis.__markdownFeedbackControls.getFeedback());
}

test('rendered emphasis adds feedback for its complete Markdown paragraph', async ({ page }) => {
  await openFixture(page);
  await openComposer(page, '自动保存');
  await page.locator(input).fill('说明自动保存的时机');
  await page.locator('.agent-feedback-input-action-add').click();

  await expect.poll(async () => (await feedbackFacts(page)).items.length).toBe(1);
  const facts = await feedbackFacts(page);
  expect(facts.submitted).toBe(0);
  expect(facts.items[0]).toMatchObject({
    text: '说明自动保存的时机',
    resource: 'inmemory://component/feedback.md',
    submitted: false,
  });
  expect(facts.items[0].range.slice(0, 2)).toEqual([3, 1]);
  expect(facts.items[0].source.trimEnd()).toBe(firstParagraph);
  await expect(page.locator(input)).not.toBeVisible();
});

test('selection across paragraphs applies feedback for the complete source span', async ({ page }) => {
  await openFixture(page);
  await openComposer(page, '自动保存', '独立说明');
  await page.locator(input).fill('合并这两段说明');
  await page.locator('.agent-feedback-input-action-apply').click();

  await expect.poll(async () => (await feedbackFacts(page)).submitted).toBe(1);
  const facts = await feedbackFacts(page);
  expect(facts.items).toHaveLength(1);
  expect(facts.items[0]).toMatchObject({ text: '合并这两段说明', submitted: true });
  expect(facts.items[0].range.slice(0, 2)).toEqual([3, 1]);
  expect(facts.items[0].source.trimEnd()).toBe(`${firstParagraph}\n\n${secondParagraph}`);
});

test('nested lists, table cells, code blocks, and image selections retain useful source context', async ({ page }) => {
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
    expect(saved.source).toContain(item.source);
    expect(saved.source).not.toContain('Unselected tail paragraph');
    expect(saved.source).not.toContain(firstParagraph);
    expect(saved.range[0]).toBeGreaterThan(5);
  }

  const image = page.locator(`${article} img[alt="Feedback image"]`);
  await expect.poll(async () => image.evaluate((node) => node.naturalWidth)).toBe(120);
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
  await expect(page.locator(addSelection)).toBeVisible();
  await page.locator(addSelection).click();
  await expect(page.locator(input)).toBeFocused();
  await page.locator(input).fill('Explain this image');
  await page.locator('.agent-feedback-input-action-add').click();
  await expect.poll(async () => (await feedbackFacts(page)).items.length).toBe(4);
  expect((await feedbackFacts(page)).items[3].source.trimEnd()).toBe(
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
    expect(saved.source.trimEnd()).toBe('New **replacement selection** has fresh context.');
    expect(saved.range.slice(0, 2)).toEqual([3, 1]);
  });
}
