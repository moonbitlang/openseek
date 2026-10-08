import { expect, gotoBrowserScenario, test } from '../support/test.js';
import {
  expectMoonBitReportPassed,
  installMoonBitReporter,
} from '../support/moonbit_reporter.js';

test('seeds layout before attach and stabilizes at explicit initialization', async ({
  page,
}, testInfo) => {
  const reporter = await installMoonBitReporter(page);
  try {
    await gotoBrowserScenario(page, 'initial-size');
    const report = await reporter.waitForReport(testInfo, {
      suite: 'initial_size',
    });
    expectMoonBitReportPassed(report, { suite: 'initial_size' });
    expect(report.metrics.hostWidth).toBeGreaterThan(0);
    expect(report.metrics.hostHeight).toBeGreaterThan(0);
    expect(report.metrics.initialLayoutWidth).toBe(report.metrics.hostWidth);
    expect(report.metrics.initialLayoutHeight).toBe(report.metrics.hostHeight);
    expect(report.metrics.initialVisibleEndLine).toBeGreaterThan(1);
    expect(report.metrics.synchronousLayoutWidth).toBe(370);
  } finally {
    reporter.dispose();
  }
});
