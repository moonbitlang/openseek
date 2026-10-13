import { expect } from '@playwright/test';

// Chromium delivers trackpad pinches as Ctrl+wheel. Send a real wheel event
// through the browser so cancellation, layout and host state all participate.
export async function pinchZoom(page, target, deltaY = -10) {
  const value = page.locator('.office-viewer-zoom-value');
  const pixelRatio = await page.evaluate(() => window.devicePixelRatio);
  const before = await page.locator('#openseek-office-surface').evaluate(host => {
    const pdf = host.__officeViewerPdf;
    return pdf ? pdf.viewer.currentScale * 100
      : Number(getComputedStyle(host).getPropertyValue('--office-zoom')) * 100;
  });
  await target.hover();
  await page.keyboard.down('Control');
  try {
    await page.mouse.wheel(0, deltaY);
  } finally {
    await page.keyboard.up('Control');
  }
  const after = Math.round(before * Math.exp(-deltaY / 100));
  await expect(value).toHaveText(`${after}%`);
  expect(await page.evaluate(() => window.visualViewport.scale)).toBe(1);
  expect(await page.evaluate(() => window.devicePixelRatio)).toBe(pixelRatio);
  return after;
}
