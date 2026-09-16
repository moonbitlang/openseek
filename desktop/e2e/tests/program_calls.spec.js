import { test, expect } from '@playwright/test';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';

for (const minimal of [false, true]) {
  test(`PTC results retain edit diffs and interruptions across reload (${minimal ? 'minimal' : 'full'})`, async ({ page }, testInfo) => {
    await page.addInitScript((enabled) => {
      localStorage.setItem('openseek.minimal_transcript', String(enabled));
    }, minimal);
    const app = new DesktopBrowserHarness(page);
    app.sessionEvents = [
      { sequence: 1, item: { kind: 'user', payload: { content: 'Show the browser fixture: update the note with a program' } } },
      { sequence: 2, item: { kind: 'assistant', payload: {
        content: '', tool_calls: [{ id: 'program', name: 'mbtx', arguments: JSON.stringify({
          ptc: true, source: 'async fn main { /* call host tools */ }', description: 'Update note',
        }) }],
      } } },
      { sequence: 3, item: { kind: 'tool_result', payload: {
        tool_call_id: 'program', tool_name: 'mbtx', content: 'Program interrupted', is_error: true,
        data: { ptc_calls: [
          { name: 'edit', arguments: { path: 'note.txt', start_line: 1, old_string: 'before', new_string: 'after' },
            status: 'done', result: { content: 'Updated note.txt', is_error: false } },
          { name: 'web_search', arguments: { query: 'MoonBit documentation' }, status: 'interrupted' },
        ] },
      } } },
    ];
    await app.install();
    await app.goto();
    await app.openSession();
    for (let pass = 0; pass < 2; pass++) {
      if (minimal) {
        // No newer assistant prose follows these calls, so the latest group
        // is directly expanded both on initial load and after reload.
        const group = page.locator('#transcript .minimal-tools-live');
        await expect(group).toBeVisible();
        await expect(group.locator(':scope > summary')).toHaveCount(0);
        const calls = group.locator('.minimal-call');
        await expect(calls).toHaveCount(3);
        await expect(calls.nth(0).locator('.minimal-call-caption')).toHaveText('Update note');
        await expect(calls.nth(1)).toContainText('before');
        await expect(calls.nth(1)).toContainText('after');
        await expect(calls.nth(1).locator('.tool-status, .minimal-tool-status')).toHaveCount(0);
        await expect(calls.nth(0).getByRole('img', { name: 'Tool failed' })).toBeVisible();
        await expect(calls.nth(2).getByRole('img', { name: 'Tool failed' })).toBeVisible();
        await expect(group.locator('details.tool-params, details.tool-result')).toHaveCount(0);
      } else {
      const outer = page.locator('#transcript details.tool-call').first();
      await outer.locator(':scope > summary').click();
      await expect(outer.getByText('Program tool calls (2)', { exact: true })).toBeVisible();
      const edit = outer.locator('details.tool-call').first();
      await edit.locator(':scope > summary').click();
      await expect(edit).toContainText('before');
      await expect(edit).toContainText('after');
      await expect(edit.locator(':scope > summary').getByRole('img', { name: 'Tool succeeded' })).toBeVisible();
      const search = outer.locator('details.tool-call').nth(1);
      await expect(search.locator(':scope > summary').getByRole('img', { name: 'Tool failed' })).toBeVisible();
      const interrupted = outer.locator('details.tool-result').last();
      await interrupted.locator(':scope > summary').click();
      await expect(interrupted).toContainText('Program call interrupted; changes may have occurred.');
      }
      if (pass === 0) {
        await page.screenshot({ path: testInfo.outputPath('program-calls.png') });
        await page.reload();
        await app.openSession();
      }
    }
    expect(app.pageErrors).toEqual([]);
  });
}

for (const minimal of [false, true]) {
  test(`background call snapshots remain historical after reload (${minimal ? 'minimal' : 'full'})`, async ({ page }) => {
    await page.addInitScript(enabled => localStorage.setItem('openseek.minimal_transcript', String(enabled)), minimal);
    const app = new DesktopBrowserHarness(page);
    app.sessionEvents = [
      { sequence: 1, item: { kind: 'user', payload: { content: 'Show the browser fixture: run a program' } } },
      { sequence: 2, item: { kind: 'assistant', payload: {
        content: '', tool_calls: [{ id: 'program', name: 'mbtx', arguments: '{"source":"async fn main {}"}' }],
      } } },
      { sequence: 3, item: { kind: 'tool_result', payload: {
        tool_call_id: 'program', tool_name: 'mbtx', content: 'Moved to background job job-1', is_error: false,
        data: { ptc_job_id: 'job-1', ptc_calls: [
          { name: 'web_search', arguments: { query: 'MoonBit' }, status: 'running' },
        ] },
      } } },
    ];
    await app.install();
    await app.goto();
    await app.openSession();
    for (let pass = 0; pass < 2; pass++) {
      if (minimal) {
        // No newer assistant prose follows these calls, so the latest group
        // is directly expanded both on initial load and after reload.
        const group = page.locator('#transcript .minimal-tools-live');
        await expect(group).toBeVisible();
        await expect(group.locator(':scope > summary')).toHaveCount(0);
        const nested = group.locator('.minimal-call').nth(1);
        await expect(nested.locator('.minimal-call-caption')).toHaveText('Snapshot');
        await expect(nested.locator('.tool-status, .minimal-tool-status')).toHaveCount(0);
      } else {
        const outer = page.locator('#transcript details.tool-call').first();
        await outer.locator(':scope > summary').click();
        const nested = outer.locator('details.tool-call').first();
        await expect(nested.getByRole('img', { name: 'Recorded snapshot' })).toBeVisible();
        await expect(nested.getByRole('img', { name: 'Tool succeeded' })).toHaveCount(0);
        await expect(nested.getByRole('img', { name: 'Tool failed' })).toHaveCount(0);
        await expect(nested.locator('.tool-status-spinner')).toHaveCount(0);
        const result = outer.locator('details.tool-result').last();
        await result.locator(':scope > summary').click();
        await expect(result).toContainText('Running when this snapshot was recorded. See background job job-1');
      }
      if (pass === 0) { await page.reload(); await app.openSession(); }
    }
    expect(app.pageErrors).toEqual([]);
  });
}
