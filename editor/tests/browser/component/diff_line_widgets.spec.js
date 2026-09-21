import { expect, gotoBrowserScenario, test } from '../support/test.js';

// Real Chromium is required for external DOM ownership, ResizeObserver,
// paired ViewZone geometry, native focus and wheel routing.
test('host line widgets retain focus and paired geometry through resize and layout changes', async ({ page }) => {
  await gotoBrowserScenario(page, 'diff-line-widgets');
  const root = page.locator('#line-widget-editor');
  const old = page.locator('#old-card');
  const current = page.locator('#new-card');
  await expect(old).toBeVisible();
  await expect(current).toBeVisible();
  const tail = side => root.locator(`.moonbit-diff-editor-${side} .view-line`).filter({ hasText: /^shared\s+tail$/ });
  const aligned = async () => {
    await expect.poll(async () => {
      const a = await tail('original').boundingBox();
      const b = await tail('modified').boundingBox();
      return a && b ? Math.abs(a.y - b.y) : Infinity;
    }).toBeLessThanOrEqual(1);
  };
  await aligned();
  const input = page.getByRole('textbox', { name: 'new-card' });
  await input.click();
  await input.fill('host-owned input');
  await page.evaluate(() => globalThis.__lineWidgets.refresh());
  await expect(input).toBeFocused();
  const before = await tail('modified').boundingBox();
  await input.evaluate(node => { node.style.height = '140px'; });
  await expect.poll(async () => (await tail('modified').boundingBox()).y - before.y).toBeGreaterThan(0);
  await expect.poll(async () => {
    const card = await current.boundingBox();
    return (await tail('modified').boundingBox()).y - (card.y + card.height);
  }).toBeGreaterThanOrEqual(0);
  await aligned();
  await expect(input).toBeFocused();
  await page.evaluate(() => globalThis.__lineWidgets.action(false));
  await root.locator('.moonbit-diff-editor-modified .view-line').filter({ hasText: /^new$/ }).hover();
  await expect(root.getByRole('button', { name: 'Add line comment' })).toBeHidden();
  await page.evaluate(() => globalThis.__lineWidgets.action(true));
  await expect(root.getByRole('button', { name: 'Add line comment' })).toBeVisible();
  await root.getByRole('button', { name: 'Add line comment' }).click();
  await expect(root).toHaveAttribute('data-action', 'false:2');
  await page.evaluate(() => globalThis.__lineWidgets.layout(true));
  const deleted = root.locator('.diff-editor-inline-deleted-block');
  await expect(deleted).toBeVisible();
  await expect.poll(async () => {
    const a = await deleted.boundingBox();
    const b = await old.boundingBox();
    return a && b ? b.y - (a.y + a.height) : -Infinity;
  }).toBeGreaterThanOrEqual(-1);
  await expect(input).toHaveValue('host-owned input');
  const scrollTop = async () => Number(await root.locator('[data-diff-overview-side="modified"]').getAttribute('data-overview-ruler-scroll-top'));
  await input.fill('overflow\n'.repeat(50));
  await input.hover();
  const beforeWheel = await scrollTop();
  await page.mouse.wheel(0, 100);
  await expect.poll(() => input.evaluate(node => node.scrollTop)).toBeGreaterThan(0);
  expect(await scrollTop()).toBe(beforeWheel);
  await input.fill('host-owned input');
  await input.hover();
  await page.mouse.wheel(0, 220);
  await expect.poll(scrollTop).toBeGreaterThan(beforeWheel + 50);
  await page.evaluate(() => globalThis.__lineWidgets.clear());
  await expect(old).toBeHidden();
  await expect(current).toBeHidden();
  await page.evaluate(() => globalThis.__lineWidgets.dispose());
  await expect(root.locator('.moonbit-diff-editor')).toHaveCount(0);
});

test('a scrollable widget root consumes native wheel input before the diff', async ({ page }) => {
  await gotoBrowserScenario(page, 'diff-line-widgets');
  const input = page.getByRole('textbox', { name: 'old-card', exact: true });
  await input.fill('overflow\n'.repeat(50));
  await input.hover();
  const scrollTop = () => page.locator('[data-diff-overview-side="original"]')
    .getAttribute('data-overview-ruler-scroll-top').then(Number);
  const before = await scrollTop();
  await page.mouse.wheel(0, 100);
  await expect.poll(() => input.evaluate(node => node.scrollTop)).toBeGreaterThan(0);
  expect(await scrollTop()).toBe(before);
  await input.fill('short content');
  await input.hover();
  await page.mouse.wheel(0, 220);
  await expect.poll(scrollTop).toBeGreaterThan(before + 50);
});

test('editing either diff model retires the hovered action until a fresh hit test', async ({ page }) => {
  for (const original of [true, false]) {
    await gotoBrowserScenario(page, 'diff-line-widgets');
    const root = page.locator('#line-widget-editor');
    const header = root.locator(`.moonbit-diff-editor-${original ? 'original' : 'modified'} .view-line`)
      .filter({ hasText: /^header$/ });
    const action = root.getByRole('button', { name: 'Add line comment' });
    await header.hover();
    await expect(action).toBeVisible();
    const immediate = await page.evaluate(original => {
      globalThis.__lineWidgets.edit(original);
      const button = document.querySelector('.moonbit-diff-line-action');
      button.click();
      return { hidden: button.hidden, dispatched: document.querySelector('#line-widget-editor').hasAttribute('data-action') };
    }, original);
    expect(immediate).toEqual({ hidden: true, dispatched: false });
    await expect.poll(() => page.evaluate(() => globalThis.__lineWidgets.ready())).toBe(true);
    await expect(action).toBeHidden();
    await header.hover();
    await expect(action).toBeVisible();
    await action.click();
    await expect(root).toHaveAttribute('data-action', `${original}:2`);
  }
});
