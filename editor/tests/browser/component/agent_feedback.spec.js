import { expect, gotoBrowserScenario, test } from '../support/test.js';
import {
  expectMoonBitReportPassed,
  installMoonBitReporter,
} from '../support/moonbit_reporter.js';

// End-to-end coverage for the agent-feedback contrib: collapsed bubbles from
// seeded service items, expand/collapse with the one-expanded rule, the
// hover "+" glyph → inline input → add/apply flows, reply and remove
// mutations (observed through the service events mirrored on
// #feedback-events), and the bubbles tracking editor scrolls.

const eventCounts = async (page) => {
  const log = page.locator('#feedback-events');
  return {
    added: Number(await log.getAttribute('data-added')),
    replies: Number(await log.getAttribute('data-replies')),
    submitted: Number(await log.getAttribute('data-submitted')),
    items: Number(await log.getAttribute('data-items')),
    lastText: await log.getAttribute('data-last-text'),
  };
};

const boxOf = async (locator) => {
  let box = null;
  await expect
    .poll(async () => {
      box = await locator.boundingBox();
      return box;
    }, { timeout: 5_000 })
    .not.toBeNull();
  return box;
};

test('agent feedback: add and fold controls have separate hit targets', async ({ page }) => {
  await gotoBrowserScenario(page, 'agent-feedback');
  const header = page.locator('.view-line', { hasText: 'quiet_area' });
  const body = page.locator('.view-line', { hasText: 'untouched' }).first();
  const glyph = page.locator('.cldr.agent-feedback-glyph.line-hover');
  const input = page.locator('.agent-feedback-input-widget textarea');
  await expect(header).toBeVisible();

  for (const collapsed of [false, true]) {
    await header.hover();
    const row = glyph.locator('..');
    const fold = row.locator('[class*="codicon-folding-"]');
    await expect(fold).toHaveCount(1);
    if (collapsed) {
      await fold.click();
      await expect(body).toHaveCount(0);
      await expect(input).not.toBeVisible();
      await header.hover();
    }

    const addBox = await boxOf(glyph);
    const foldBox = await boxOf(fold);
    expect(foldBox.x - (addBox.x + addBox.width)).toBe(2);
    const marginBox = await boxOf(page.locator('.monaco-editor .margin'));
    expect(marginBox.x + marginBox.width - (foldBox.x + foldBox.width)).toBe(8);
    // Hit both edges of the visible plus, not only a tiny carrier's center.
    for (const offset of [2, addBox.width - 2]) {
      await header.hover();
      await glyph.click({ position: { x: offset, y: addBox.height / 2 } });
      await expect(input).toBeFocused();
      await expect(body).toHaveCount(collapsed ? 0 : 1);
      await input.press('Escape');
      await expect(input).not.toBeVisible();
      // Restore the viewport after the composer returns focus to the editor.
      await page.mouse.move(300, 100);
      await page.mouse.wheel(0, -1000);
      await expect(header).toBeVisible();
    }
  }

  await header.hover();
  await glyph.locator('..').locator('[class*="codicon-folding-"]').click();
  await expect(body).toHaveCount(1);
  await expect(input).not.toBeVisible();
});

test('agent feedback: bubbles, glyph add flow, reply, remove, scroll', async ({ page }, testInfo) => {
  const reporter = await installMoonBitReporter(page);
  await gotoBrowserScenario(page, 'agent-feedback');
  await expect(page.locator('.monaco-editor.readonly-editor')).toContainText(
    'reviewed_area',
    { timeout: 10_000 },
  );
  const report = await reporter.waitForReport(testInfo, {
    suite: 'agent_feedback',
  });
  expectMoonBitReportPassed(report, { suite: 'agent_feedback' });
  expect(report.metrics.widgets).toBe(2);
  expect(report.metrics.collapsed).toBe(2);

  // Widgets mount in reverse file order (upper groups render on top), so
  // select by content rather than DOM order.
  const widgets = page.locator('.agent-feedback-widget');
  const firstWidget = widgets.filter({ hasText: '2 comments' });
  const farWidget = widgets.filter({ hasText: 'Far seeded note' });

  // The near group carries two comments; collapsed bubbles hide their items.
  await expect(firstWidget.locator('.agent-feedback-widget-title')).toHaveText(
    '2 comments',
  );
  // The collapsed body clips its items via max-height: 0 (the items keep a
  // box, so assert the clip height rather than Playwright visibility).
  await expect
    .poll(async () =>
      firstWidget
        .locator('.agent-feedback-widget-body')
        .evaluate((el) => el.clientHeight),
    )
    .toBe(0);

  // Expanding via the header shows the items; the other bubble stays
  // collapsed (one expanded per file).
  await firstWidget.locator('.agent-feedback-widget-header').click();
  await expect(firstWidget).not.toHaveClass(/collapsed/);
  await expect(firstWidget.locator('.agent-feedback-widget-item')).toHaveCount(
    2,
  );
  await expect(
    firstWidget.locator('.agent-feedback-widget-line-info').first(),
  ).toHaveText('Line 3');
  await expect(farWidget).toHaveClass(/collapsed/);

  // Hovering an item highlights its range in the editor.
  await firstWidget.locator('.agent-feedback-widget-item').first().hover();
  await expect(page.locator('.rangeHighlight')).toHaveCount(1);

  // Reply: the hover action bar's reply button opens the composer; Enter
  // stores the reply on the service and re-renders the thread.
  await firstWidget
    .locator('.agent-feedback-widget-action-reply')
    .first()
    .click();
  const composer = firstWidget.locator(
    '.agent-feedback-widget-add-reply textarea',
  );
  await expect(composer).toBeFocused();
  await composer.fill('Reply from the spec');
  await composer.press('Enter');
  await expect
    .poll(async () => (await eventCounts(page)).replies)
    .toBe(1);
  await expect(
    page.locator('.agent-feedback-widget-reply-text').first(),
  ).toContainText('Reply from the spec');

  // Hover "+" glyph on a quiet line opens the inline input; Shift+Enter adds
  // a newline while keeping the draft open, then Enter adds the multiline
  // feedback item. The new item mounts a third bubble (line 15 sits outside
  // the near group's threshold).
  const quietLine = page
    .locator('.view-line', { hasText: 'filler line 3' })
    .first();
  await quietLine.hover();
  const glyph = page.locator(
    '.margin-view-overlays .cldr.agent-feedback-glyph.line-hover',
  );
  const glyphBox = await boxOf(glyph);
  await page.mouse.click(
    glyphBox.x + glyphBox.width / 2,
    glyphBox.y + glyphBox.height / 2,
  );
  const input = page.locator('.agent-feedback-input-widget textarea');
  await expect(input).toBeVisible();
  await expect(input).toBeFocused();
  const batch = page.getByRole('checkbox', { name: 'Batch', exact: true });
  const submit = page.locator('.agent-feedback-input-action');
  await expect(batch).not.toBeChecked();
  await expect(submit).toHaveAccessibleName('Apply all feedback');
  await expect(submit).toBeDisabled();
  // Choosing Batch on an empty input keeps the composer open and puts the
  // caret back in the input, ready for the note.
  await batch.check();
  await expect(input).toBeFocused();
  await expect(submit).toHaveAccessibleName('Add feedback');
  await expect(submit).toBeDisabled();
  await input.fill('Needs a guard clause');
  await expect(submit).toBeEnabled();
  const singleLineHeight = (await boxOf(input)).height;
  await input.press('Shift+Enter');
  await expect(input).toHaveValue('Needs a guard clause\n');
  await expect(input).toBeFocused();
  await expect.poll(async () => (await eventCounts(page)).added).toBe(0);
  await input.type('Keep the early return focused');
  await input.press('Shift+Enter');
  await input.type('Leave a concise note');
  await input.press('Shift+Enter');
  await expect.poll(async () => (await boxOf(input)).height)
    .toBeGreaterThan(singleLineHeight);
  await input.type('Avoid nested branching');
  await input.press('Enter');
  await expect.poll(async () => (await eventCounts(page)).added).toBe(1);
  await expect
    .poll(async () => (await eventCounts(page)).lastText)
    .toBe(
      'Needs a guard clause\nKeep the early return focused\n' +
        'Leave a concise note\nAvoid nested branching',
    );
  await expect(page.locator('.agent-feedback-input-widget')).not.toBeVisible();
  await expect(widgets).toHaveCount(3);

  // A second item can apply the complete accepted batch immediately. The
  // sticky Batch choice is turned off to send through the same button.
  const nextQuietLine = page
    .locator('.view-line', { hasText: 'filler line 4' })
    .first();
  await nextQuietLine.hover();
  const nextGlyphBox = await boxOf(glyph);
  await page.mouse.click(
    nextGlyphBox.x + nextGlyphBox.width / 2,
    nextGlyphBox.y + nextGlyphBox.height / 2,
  );
  await expect(input).toBeFocused();
  await expect(batch).toBeChecked();
  await batch.uncheck();
  await expect(input).toBeFocused();
  await input.fill('Apply this batch now');
  await expect(submit).toHaveAccessibleName('Apply all feedback');
  await submit.click();
  await expect.poll(async () => (await eventCounts(page)).added).toBe(2);
  await expect.poll(async () => (await eventCounts(page)).submitted).toBe(5);
  await expect(page.locator('.agent-feedback-input-widget')).not.toBeVisible();

  // Remove: the hover action bar's remove button drops the item; the far
  // bubble (one comment) disappears with it.
  const counts = await eventCounts(page);
  await farWidget.locator('.agent-feedback-widget-header').click();
  await expect(farWidget).not.toHaveClass(/collapsed/);
  await farWidget.locator('.agent-feedback-widget-item').first().hover();
  await farWidget
    .locator('.agent-feedback-widget-action-remove')
    .first()
    .click();
  await expect(widgets).toHaveCount(2);
  await expect
    .poll(async () => (await eventCounts(page)).items)
    .toBe(counts.items - 1);

  // Scroll tracking: wheeling moves the bubbles with the content.
  const beforeScroll = await boxOf(page.locator('.agent-feedback-widget').first());
  await page.mouse.move(400, 200);
  await page.mouse.wheel(0, 120);
  await expect
    .poll(async () =>
      (await boxOf(page.locator('.agent-feedback-widget').first())).y,
    )
    .toBeLessThan(beforeScroll.y);
});


test('agent feedback: default send, sticky Batch, keyboard focus and IME', async ({ page }) => {
  await gotoBrowserScenario(page, 'agent-feedback');
  const input = page.locator('.agent-feedback-input-widget textarea');
  const batch = page.getByRole('checkbox', { name: 'Batch', exact: true });
  const submit = page.locator('.agent-feedback-input-action');
  const open = async line => {
    await page.locator(`.view-line[data-line="${line}"]`).hover();
    await page.locator('.agent-feedback-glyph.line-hover').click();
    await expect(input).toBeFocused();
  };

  // Enter sends by default, including the already accepted feedback.
  await open(15);
  await input.fill('Send this note');
  await input.press('Enter');
  await expect.poll(async () => (await eventCounts(page)).added).toBe(1);
  await expect.poll(async () => (await eventCounts(page)).submitted).toBe(4);
  await expect(input).not.toBeVisible();

  // Keyboard focus can move into Batch without dismissing an empty input.
  await open(16);
  await input.press('Tab');
  await expect(batch).toBeFocused();
  await batch.press('Space');
  await expect(batch).toBeChecked();
  await expect(input).toBeFocused();
  await input.fill('   ');
  await expect(submit).toBeDisabled();
  await input.press('Enter');
  await expect(input).toBeVisible();
  await input.fill('Keep this note in the batch');
  for (const key of ['Enter', 'Escape']) {
    await input.evaluate((el, key) => el.dispatchEvent(new KeyboardEvent('keydown', {
      key, bubbles: true, cancelable: true, isComposing: true,
    })), key);
  }
  await expect(input).toHaveValue('Keep this note in the batch');
  expect((await eventCounts(page)).added).toBe(1);
  await submit.click();
  await expect.poll(async () => (await eventCounts(page)).added).toBe(2);
  expect((await eventCounts(page)).submitted).toBe(4);

  // Alt+Enter still sends the batch without changing the remembered choice.
  await open(17);
  await expect(batch).toBeChecked();
  await input.fill('Apply both notes');
  await input.press('Alt+Enter');
  await expect.poll(async () => (await eventCounts(page)).added).toBe(3);
  await expect.poll(async () => (await eventCounts(page)).submitted).toBe(6);

  // Escape also works with focus on the checkbox, and leaving an empty
  // composer from that control dismisses it.
  await open(18);
  await expect(batch).toBeChecked();
  await input.press('Tab');
  await expect(batch).toBeFocused();
  await batch.press('Escape');
  await expect(input).not.toBeVisible();
  await open(18);
  await input.press('Tab');
  await batch.evaluate(el => el.blur());
  await expect(input).not.toBeVisible();
});
