import { test, expect } from './support/test.js';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';

for (const behavior of ['queue', 'steer']) {
    test(`${behavior} preserves multiline follow-up content and disclosure state`, async ({ page }) => {
      const app = new DesktopBrowserHarness(page);
      app.hostSettings.followup_behavior = behavior;
      await app.install();
      await app.goto();
      await app.openSession();
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
      await summary.click();
      await expect(text).toBeVisible();
      expect(await text.textContent()).toBe(content);
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
        await row.getByTestId('queued-input-edit').click();
        await expect(composer).toHaveValue(content);
        await expect(row).toHaveAttribute('open', '');
      }
      expect(app.pageErrors).toEqual([]);
    });
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
  const ids = [];
  for (const content of ['First message', 'Second message\nFull details', 'Third message']) {
    await composer.fill(content);
    await composer.press('Enter');
    const id = app.requests.filter(r => r.method === 'agent.queue').at(-1).params.id;
    ids.push(id);
    await expect(page.locator(`[data-queued-input-id=${JSON.stringify(id)}]`)).toContainText(content);
  }
  await composer.fill('');
  const rows = page.locator('.queued-input-row');
  const second = page.locator(`[data-queued-input-id=${JSON.stringify(ids[1])}]`);
  const third = page.locator(`[data-queued-input-id=${JSON.stringify(ids[2])}]`);
  await second.locator('summary').click();
  await page.locator(`[data-queued-input-id=${JSON.stringify(ids[0])}]`).getByTestId('queued-input-delete').click();
  await expect(rows).toHaveCount(2);
  await expect(second).toHaveAttribute('open', '');
  await expect(third).not.toHaveAttribute('open');
  await third.getByTestId('queued-input-edit').click();
  await expect(composer).toHaveValue('Third message');
  await expect(third).not.toHaveAttribute('open');
  await composer.fill('Third message\nEdited details');
  await page.locator('#send').click();
  await expect(third.locator('.followup-content')).toHaveText('Third message\nEdited details');
  await expect(third).not.toHaveAttribute('open');
  await second.getByTestId('queued-input-delete').click();
  await expect(rows).toHaveCount(1);
  await expect(third).not.toHaveAttribute('open');
  await third.getByTestId('queued-input-steer').click();
  await expect(rows).toHaveCount(0);
  const steer = page.locator('.pending-steer-row');
  await expect(steer).toBeVisible();
  await expect(steer).not.toHaveAttribute('open');
  await steer.locator('summary').click();
  expect(await steer.locator('.followup-content').textContent()).toBe('Third message\nEdited details');
  expect(app.pageErrors).toEqual([]);
});
