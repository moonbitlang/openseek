import { test, expect } from '@playwright/test';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';

for (const marker of ['@', '$']) {
  test(`${marker} completion keeps keyboard selection inside the menu`, async ({ page }) => {
    const app = new DesktopBrowserHarness(page);
    app.searchFiles = Array.from({ length: 20 }, (_, i) => `src/file-${i}.mbt`);
    app.installedSkills = Array.from({ length: 20 }, (_, i) => ({
      id: `skill-${i}`, name: `skill-${i}`, description: `Skill ${i}`, source: '',
    }));
    await app.install();
    await app.goto();
    await app.openSession();

    const input = page.locator('#task');
    await input.fill(marker);
    const list = page.locator('.completion-list');
    const rows = list.locator('.completion-item');
    await expect(rows).toHaveCount(20);
    expect(await list.evaluate(el => el.scrollHeight > el.clientHeight)).toBe(true);
    const labels = await rows.locator('.completion-label').allTextContents();
    const selected = list.locator('.completion-item.selected');
    const inputBounds = await input.boundingBox();

    async function expectSelection(index) {
      await expect(selected.locator('.completion-label')).toHaveText(labels[index]);
      await expect.poll(() => selected.evaluate(el => {
        const row = el.getBoundingClientRect();
        const list = el.parentElement.getBoundingClientRect();
        return row.top >= list.top - 1 && row.bottom <= list.bottom + 1;
      })).toBe(true);
      await expect(input).toBeFocused();
    }

    await expectSelection(0);
    await input.press('ArrowDown');
    await expectSelection(1);
    expect(await list.evaluate(el => el.scrollTop)).toBe(0);
    for (let i = 2; i < labels.length; i++) {
      await input.press('ArrowDown');
      await expectSelection(i);
    }
    await input.press('ArrowDown');
    await expectSelection(0);
    await input.press('ArrowUp');
    await expectSelection(labels.length - 1);
    for (let i = labels.length - 2; i >= 0; i--) {
      await input.press('ArrowUp');
      await expectSelection(i);
    }
    expect(await input.boundingBox()).toEqual(inputBounds);
    expect(app.pageErrors).toEqual([]);
  });
}
