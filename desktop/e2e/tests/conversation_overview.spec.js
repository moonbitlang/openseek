import { test, expect } from './support/test.js';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';

test('the overview is a rail beside a wide conversation and a panel over a narrow one', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  app.gitBranch = { branch: 'feature/overview-layout' };
  await page.setViewportSize({ width: 1440, height: 900 });
  await app.install();
  await app.goto();
  await app.openSession();
  await page.getByRole('button', { name: 'Show overview', exact: true }).click();
  const panel = page.getByRole('complementary', { name: 'Overview' });
  await expect(panel).toBeVisible();
  await expect(panel.getByRole('button', { name: 'Changes', exact: true })).toBeVisible();

  // The overview never takes the transcript's place: the conversation keeps
  // its row, from the titlebar down to the composer, with its messages.
  const message = page.locator('.transcript .msg-content', { hasText: 'Show the browser fixture' });
  const keepsItsRow = async () => {
    await expect(message).toBeVisible();
    const topbar = await page.locator('.topbar').boundingBox();
    const transcript = await page.locator('.transcript').boundingBox();
    const composer = await page.locator('.composer').first().boundingBox();
    expect(transcript.y).toBeLessThanOrEqual(topbar.y + topbar.height + 1);
    expect(transcript.height).toBeGreaterThan(composer.y - transcript.y - 200);
    return { transcript, composer };
  };

  // With room for both, the conversation's column and the composer end where
  // the rail begins: nothing of the conversation is under it. The transcript
  // scroller itself runs past the rail, so its scrollbar is outside it.
  const rail = await panel.boundingBox();
  const { transcript, composer } = await keepsItsRow();
  const stream = await page.locator('.transcript .stream').boundingBox();
  expect(stream.x + stream.width).toBeLessThanOrEqual(rail.x + 1);
  expect(transcript.x + transcript.width).toBeGreaterThan(rail.x + rail.width);
  expect(composer.x + composer.width).toBeLessThanOrEqual(rail.x + 1);
  // The rail is as tall as its cards: the wheel below it scrolls the
  // transcript. The fixture conversation fits on screen, so it is lengthened
  // for this check.
  const scroller = page.locator('.transcript');
  await scroller.evaluate((el) => {
    el.querySelector('.stream').style.paddingBottom = '2000px';
    el.scrollTop = el.scrollHeight;
  });
  const bottom = await scroller.evaluate((el) => el.scrollTop);
  expect(bottom).toBeGreaterThan(0);
  const below = transcript.y + transcript.height - 30;
  expect(below).toBeGreaterThan(rail.y + rail.height);
  await page.mouse.move(rail.x + rail.width / 2, below);
  await page.mouse.wheel(0, -200);
  await expect.poll(() => scroller.evaluate((el) => el.scrollTop)).toBeLessThan(bottom);
  await scroller.evaluate((el) => { el.scrollTop = 0; });
  await scroller.evaluate((el) => { el.querySelector('.stream').style.paddingBottom = ''; });

  // Cards taller than the pane scroll inside the rail, which stops at the
  // pane's bottom edge and takes the pointer itself, its scrollbar included.
  const first = panel.locator('.conv-overview-card').first();
  await first.evaluate((el) => { el.style.minHeight = '2000px'; });
  const tall = await panel.boundingBox();
  expect(tall.y + tall.height).toBeLessThanOrEqual(900 + 1);
  expect(await panel.evaluate((el) => el.scrollHeight > el.clientHeight)).toBe(true);
  const firstBox = await first.boundingBox();
  const gap = { x: tall.x + tall.width / 2, y: firstBox.y - 4 };
  expect(await panel.evaluate((el, { x, y }) => document.elementFromPoint(x, y) === el, gap)).toBe(true);
  await page.mouse.move(tall.x + tall.width / 2, tall.y + tall.height / 2);
  await page.mouse.wheel(0, 200);
  await expect.poll(() => panel.evaluate((el) => el.scrollTop)).toBeGreaterThan(0);
  await first.evaluate((el) => { el.style.minHeight = ''; });

  // Without room, the same overview covers the transcript's right edge but
  // stops above the composer, which stays usable.
  await page.setViewportSize({ width: 960, height: 900 });
  await expect(panel).toBeVisible();
  await keepsItsRow();
  const over = await panel.boundingBox();
  const narrowTranscript = await page.locator('.transcript').boundingBox();
  const narrowComposer = await page.locator('.composer').first().boundingBox();
  expect(over.x).toBeLessThan(narrowTranscript.x + narrowTranscript.width);
  expect(over.y + over.height).toBeLessThanOrEqual(narrowComposer.y + 1);
  await page.getByRole('textbox').first().click();
  await expect(page.getByRole('textbox').first()).toBeFocused();

  // The overview still fits inside the window at phone widths.
  for (const width of [760, 390]) {
    await page.setViewportSize({ width, height: 800 });
    await expect(panel).toBeVisible();
    await keepsItsRow();
    const box = await panel.boundingBox();
    expect(box.x).toBeGreaterThanOrEqual(0);
    expect(box.x + box.width).toBeLessThanOrEqual(width);
  }
  await page.getByRole('button', { name: 'Hide overview', exact: true }).click();
  await expect(panel).toBeHidden();
  await page.getByRole('button', { name: 'Show overview', exact: true }).click();
  await expect(panel).toBeVisible();
  expect(app.pageErrors).toEqual([]);
});
