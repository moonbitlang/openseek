import { expect, gotoBrowserScenario, test } from '../support/test.js';
import { expectMoonBitReportPassed, installMoonBitReporter } from '../support/moonbit_reporter.js';

test('large MoonBit preparation paints its default outline and reuses structural ranges', async ({page}, testInfo) => {
  const reporter = await installMoonBitReporter(page);
  try {
    await gotoBrowserScenario(page, 'prepared-folding');
    const report = await reporter.waitForReport(testInfo, {suite: 'prepared_folding'});
    expectMoonBitReportPassed(report, {suite: 'prepared_folding'});
    expect(report.metrics.viewLines).toBe(801);
    await expect(page.locator('.view-lines')).toContainText('f0');
    await expect(page.locator('.view-lines')).not.toContainText('let');
  } finally { reporter.dispose(); }
});

test('a busy real Worker times out and cancellation terminates both owned workers', async ({page}, testInfo) => {
  // Keep a real thread busy, so a timeout around main-thread compute would
  // hang the heartbeat and the test. Count actual termination calls.
  await page.addInitScript(() => {
    const NativeWorker = window.Worker;
    window.__workerTerminations = 0;
    window.Worker = class extends NativeWorker {
      terminate() { window.__workerTerminations++; super.terminate(); }
    };
  });
  await page.route('**/editor-code-worker.js', route => route.fulfill({
    contentType: 'text/javascript', body: 'onmessage = () => { while (true) {} };',
  }));
  const reporter = await installMoonBitReporter(page);
  try {
    await gotoBrowserScenario(page, 'worker-timeout');
    const report = await reporter.waitForReport(testInfo, {suite: 'worker_timeout'});
    expectMoonBitReportPassed(report, {suite: 'worker_timeout'});
    expect(await page.evaluate(() => window.__workerTerminations)).toBe(2);
  } finally { reporter.dispose(); }
});
