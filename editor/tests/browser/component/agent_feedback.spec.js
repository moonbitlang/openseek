import { expect, test } from '../support/test.js';
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

test('agent feedback: bubbles, glyph add flow, reply, remove, scroll', async ({ page }, testInfo) => {
  const reporter = await installMoonBitReporter(page);
  await page.goto('/browser-tests/agent_feedback.html');
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
  const cancelFeedback = page.locator(
    '.agent-feedback-input-action-cancel',
  );
  const addFeedback = page.locator(
    '.agent-feedback-input-action-add',
  );
  const applyAllFeedback = page.locator(
    '.agent-feedback-input-action-apply',
  );
  await expect(cancelFeedback).toHaveText('Cancel');
  await expect(addFeedback).toHaveText('Add feedback');
  await expect(applyAllFeedback).toHaveText('Apply all feedback');
  await expect(addFeedback).toBeDisabled();
  await expect(applyAllFeedback).toBeDisabled();
  await input.fill('Needs a guard clause');
  await expect(addFeedback).toBeEnabled();
  await expect(applyAllFeedback).toBeEnabled();
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
  // explicit button is always visible; Alt+Enter remains its keyboard path.
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
  await input.fill('Apply this batch now');
  await applyAllFeedback.click();
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
