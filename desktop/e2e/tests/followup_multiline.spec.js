import { test, expect } from '@playwright/test';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';

for (const behavior of ['queue', 'steer']) {
  for (const width of [1440, 700]) {
    test(`${behavior} expands multiline follow-ups at ${width}px`, async ({ page }, testInfo) => {
      const app = new DesktopBrowserHarness(page);
      app.hostSettings.followup_behavior = behavior;
      await app.install();
      await app.goto();
      await app.openSession();
      await page.setViewportSize({ width, height: 1000 });
      if (width === 700) {
        await expect.poll(() => page.locator('.app > aside').evaluate(element =>
          element.getBoundingClientRect().right)).toBeLessThanOrEqual(0);
      }
      const composer = page.locator('#task');
      await composer.fill('Start a turn');
      await page.locator('#send').click();
      const content = '> Unix/Windows mapping\n\nWhat does this mean?\n' + 'long-path/'.repeat(30);
      await composer.fill(content);
      await composer.press('Enter');
      const row = page.locator(behavior === 'queue' ? '.queued-input-row' : '.pending-steer-row');
      const summary = row.locator('summary');
      const preview = summary.locator(behavior === 'queue' ? '.queued-input-text' : '.pending-steer-text');
      const text = row.locator('.followup-content');
      await expect(row).not.toHaveAttribute('open');
      await expect(text).toBeHidden();
      expect(await preview.textContent()).toBe(content);
      expect(await preview.evaluate(element => element.clientHeight))
        .toBeLessThanOrEqual(await preview.evaluate(element => parseFloat(getComputedStyle(element).lineHeight)) + 1);
      await summary.click();
      await expect(text).toBeVisible();
      expect(await text.textContent()).toBe(content);
      const geometry = await text.evaluate(element => {
        const content = element.firstChild;
        const topAt = offset => {
          const range = document.createRange();
          range.setStart(content, offset);
          range.setEnd(content, offset + 1);
          return range.getBoundingClientRect().top;
        };
        return {
          lineGap: topAt(content.textContent.indexOf('What')) - topAt(0),
          lineHeight: parseFloat(getComputedStyle(element).lineHeight),
          width: element.clientWidth,
          scrollWidth: element.scrollWidth,
        };
      });
      expect(geometry.lineGap).toBeGreaterThanOrEqual(geometry.lineHeight * 2 - 1);
      expect(geometry.scrollWidth).toBeLessThanOrEqual(geometry.width + 1);
      const previewBounds = await preview.boundingBox();
      const textCenter = previewBounds.y + previewBounds.height / 2;
      for (const icon of await summary.locator('.icon').all()) {
        const bounds = await icon.boundingBox();
        expect.soft(Math.abs(bounds.y + bounds.height / 2 - textCenter)).toBeLessThanOrEqual(1);
      }
      const rowBounds = await row.boundingBox();
      expect(rowBounds.x + rowBounds.width).toBeLessThanOrEqual(width);
      const path = testInfo.outputPath('multiline-followup.png');
      await row.screenshot({ path });
      await testInfo.attach('Multiline follow-up', { path, contentType: 'image/png' });
      await composer.fill('An unrelated draft');
      await expect(row).toHaveAttribute('open', '');
      await expect(text).toBeVisible();
      app.notify('agent.approvals', { generation: 1, approvals: [{
        session: 'session-1', run_id: 'run-e2e', answered: false,
        id: 'approval-followup', tool_name: 'write', detail: '/workspace/example.mbt',
        body: 'Example approval',
      }] });
      await expect(page.locator('.composer-approval')).toBeVisible();
      await expect(row).toHaveAttribute('open', '');
      app.notify('agent.approvals', { generation: 2, approvals: [] });
      await expect(page.locator('.composer-approval')).toHaveCount(0);
      await expect(row).toHaveAttribute('open', '');
      await summary.focus();
      await page.keyboard.press('Enter');
      await expect(text).toBeHidden();
      await page.keyboard.press('Space');
      await expect(text).toBeVisible();
      if (behavior === 'queue') {
        await composer.fill('');
        await row.getByTitle('Edit', { exact: true }).click();
        await expect(composer).toHaveValue(content);
        await expect(row).toHaveAttribute('open', '');
      }
      expect(app.pageErrors).toEqual([]);
    });
  }
}

test('queue disclosures keep their own state when earlier messages are removed', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  app.hostSettings.followup_behavior = 'queue';
  await app.install();
  await app.goto();
  await app.openSession();
  const composer = page.locator('#task');
  await composer.fill('Start a turn');
  await page.locator('#send').click();
  for (const content of ['First message', 'Second message\nFull details', 'Third message']) {
    await composer.fill(content);
    await composer.press('Enter');
    await expect(page.locator('.queued-input-row').filter({ hasText: content })).toBeVisible();
  }
  await composer.fill('');
  const rows = page.locator('.queued-input-row');
  const second = rows.filter({ hasText: 'Second message' });
  const third = rows.filter({ hasText: 'Third message' });
  await second.locator('summary').click();
  await rows.filter({ hasText: 'First message' }).getByTitle('Delete', { exact: true }).click();
  await expect(rows).toHaveCount(2);
  await expect(second).toHaveAttribute('open', '');
  await expect(third).not.toHaveAttribute('open');
  await third.getByTitle('Edit', { exact: true }).click();
  await expect(composer).toHaveValue('Third message');
  await expect(third).not.toHaveAttribute('open');
  await composer.fill('Third message\nEdited details');
  await page.getByTitle('Save queued message', { exact: true }).click();
  await expect(third.locator('.followup-content')).toHaveText('Third message\nEdited details');
  await expect(third).not.toHaveAttribute('open');
  await second.getByTitle('Delete', { exact: true }).click();
  await expect(rows).toHaveCount(1);
  await expect(third).not.toHaveAttribute('open');
  await third.getByTitle('Steer', { exact: true }).click();
  await expect(rows).toHaveCount(0);
  const steer = page.locator('.pending-steer-row');
  await expect(steer).toBeVisible();
  await expect(steer).not.toHaveAttribute('open');
  await steer.locator('summary').click();
  expect(await steer.locator('.followup-content').textContent()).toBe('Third message\nEdited details');
  expect(app.pageErrors).toEqual([]);
});
