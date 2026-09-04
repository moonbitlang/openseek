import { expect, gotoBrowserScenario, test } from '../support/test.js';
import {
  expectMoonBitReportPassed,
  installMoonBitReporter,
} from '../support/moonbit_reporter.js';

const mainHost = '.code-lens-main-host';
const plainHost = '.code-lens-plain-host';
const mainLens = mainHost + ' .codelens-decoration';

async function settle(page) {
  await page.evaluate(
    () =>
      new Promise((resolve) =>
        requestAnimationFrame(() =>
          requestAnimationFrame(() => requestAnimationFrame(resolve)),
        ),
      ),
  );
}

async function mountCodeLens(page, testInfo) {
  const reporter = await installMoonBitReporter(page);
  await gotoBrowserScenario(page, 'code-lens');
  await page.waitForFunction(() => Boolean(globalThis.__codeLensControls));
  const report = await reporter.waitForReport(testInfo, {
    suite: 'code_lens',
    timeout: 10_000,
  });
  expectMoonBitReportPassed(report, { suite: 'code_lens' });
  expect(report.metrics.initialRows).toBe(2);
  await settle(page);
  return reporter;
}

async function control(page, method, ...args) {
  return page.evaluate(
    ({ method: name, args: values }) =>
      globalThis.__codeLensControls[name](...values),
    { method, args },
  );
}

async function state(page) {
  return control(page, 'state');
}

async function lineTextLeft(page, line, needle) {
  return page.locator(mainHost).evaluate(
    (host, request) => {
      const lineNode = host.querySelector(
        '.view-line[data-line="' + request.line + '"]',
      );
      if (!lineNode) return null;
      const walker = document.createTreeWalker(
        lineNode,
        NodeFilter.SHOW_TEXT,
      );
      for (let node = walker.nextNode(); node; node = walker.nextNode()) {
        const index = node.textContent.indexOf(request.needle);
        if (index < 0) continue;
        const range = document.createRange();
        range.setStart(node, index);
        range.setEnd(node, index + request.needle.length);
        return range.getBoundingClientRect().left;
      }
      return null;
    },
    { line, needle },
  );
}

test('CodeLens rows sit above and align with source while unresolved work stays visible-only', async ({
  page,
}, testInfo) => {
  const reporter = await mountCodeLens(page, testInfo);
  try {
    const row = page.locator(
      mainLens + '[data-code-lens-line="2"]',
    );
    await expect(row).toBeVisible();
    await expect(row).toContainText('resolved resolve-2');
    await expect
      .poll(async () => (await state(page)).resolveCalls)
      .toContain('resolve-2');
    expect((await state(page)).resolveCalls).not.toContain('resolve-40');

    const geometry = await page.locator(mainHost).evaluate((host) => {
      const lens = host.querySelector(
        '.codelens-decoration[data-code-lens-line="2"]',
      );
      const line = host.querySelector('.view-line[data-line="2"]');
      const zone = Array.from(
        host.querySelectorAll(
          '.codelens-view-zone[monaco-visible-view-zone]',
        ),
      ).find((node) =>
        node.getBoundingClientRect().bottom <=
        line.getBoundingClientRect().top + 1);
      const rect = (node) => {
        const value = node.getBoundingClientRect();
        return {
          top: value.top,
          bottom: value.bottom,
          left: value.left,
          width: value.width,
          height: value.height,
        };
      };
      const style = getComputedStyle(lens);
      return {
        lens: rect(lens),
        line: rect(line),
        zone: zone ? rect(zone) : null,
        whiteSpace: style.whiteSpace,
        overflow: style.overflow,
        textOverflow: style.textOverflow,
        fontSize: style.fontSize,
        display: style.display,
      };
    });
    expect(geometry.zone).not.toBeNull();
    expect(geometry.zone.bottom).toBeLessThanOrEqual(geometry.line.top + 1);
    expect(geometry.lens.bottom).toBeLessThanOrEqual(geometry.line.top + 1);
    expect(geometry.lens.top).toBeGreaterThanOrEqual(geometry.zone.top - 1);
    const textLeft = await lineTextLeft(page, 2, 'fn');
    expect(textLeft).not.toBeNull();
    expect(Math.abs(geometry.lens.left - textLeft)).toBeLessThanOrEqual(1);
    expect(geometry).toMatchObject({
      whiteSpace: 'nowrap',
      overflow: 'hidden',
      textOverflow: 'ellipsis',
      fontSize: '18px',
      // Absolutely positioned content widgets blockify inline-flex to flex.
      display: 'flex',
    });

    await expect(row.locator(':scope > a')).toHaveCount(2);
    await expect(row.locator('.codelens-separator')).toHaveCount(1);
    expect(await row.textContent()).toBe(
      '3 references\u00a0|\u00a0resolved resolve-2',
    );
    await expect(
      row.locator('[data-code-lens-command="fixture.references"]'),
    ).toHaveAttribute('title', 'Show all references');

    const plain = page.locator(plainHost + ' .codelens-decoration');
    await expect(plain).toBeVisible();
    await expect(plain.locator(':scope > a')).toHaveCount(0);
    await expect(
      plain.locator(
        ':scope > span[data-code-lens-command="fixture.plain"]',
      ),
    ).toHaveText('plain without executor');
    const plainStyle = await plain.evaluate((node) => {
      const style = getComputedStyle(node);
      return { fontSize: style.fontSize, fontFamily: style.fontFamily };
    });
    expect(plainStyle.fontSize).toBe('11px');
    expect(plainStyle.fontFamily.toLowerCase()).toContain('serif');
  } finally {
    reporter.dispose();
  }
});

test('CodeLens click forwards exactly one complete host request', async ({
  page,
}, testInfo) => {
  const reporter = await mountCodeLens(page, testInfo);
  try {
    const command = page.locator(
      mainLens +
        '[data-code-lens-line="2"] ' +
        '[data-code-lens-command="fixture.references"]',
    );
    await command.click();
    await expect
      .poll(async () => (await state(page)).executions.length)
      .toBe(1);
    const execution = (await state(page)).executions[0];
    expect(execution.sourceViewerId).toMatch(
      /^vs\.editor\.ICodeEditor:\d+$/,
    );
    expect(execution).toMatchObject({
      resource: 'inmemory://model/code-lens-main.mbt',
      startLine: 2,
      startColumn: 5,
      endLine: 2,
      endColumn: 5,
      id: 'fixture.references',
      title: '3 references',
      tooltip: 'Show all references',
      arguments: ['payload', 7, { nested: true }],
    });
  } finally {
    reporter.dispose();
  }
});

test('CodeLens lazy resolution and row refresh preserve the viewport anchor', async ({
  page,
}, testInfo) => {
  const reporter = await mountCodeLens(page, testInfo);
  try {
    expect((await state(page)).resolveCalls).not.toContain('resolve-40');
    await control(page, 'scroll_late');
    await settle(page);
    const late = page.locator(
      mainLens + '[data-code-lens-line="40"]',
    );
    await expect(late).toBeVisible();
    await expect(late).toContainText('resolved resolve-40');
    await expect
      .poll(async () => (await state(page)).resolveCalls)
      .toContain('resolve-40');

    const before = await page.locator(mainHost).evaluate((host) => ({
      top: host
        .querySelector('.view-line[data-line="40"]')
        .getBoundingClientRect().top,
      scrollTop: globalThis.__codeLensControls.state().scrollTop,
    }));
    await control(page, 'expand');
    await expect(
      page.locator(mainLens + '[data-code-lens-line="10"]'),
    ).toHaveCount(1);
    await expect(
      page.locator(mainLens + '[data-code-lens-line="20"]'),
    ).toHaveCount(1);
    await settle(page);
    const expanded = await page.locator(mainHost).evaluate((host) => ({
      top: host
        .querySelector('.view-line[data-line="40"]')
        .getBoundingClientRect().top,
      scrollTop: globalThis.__codeLensControls.state().scrollTop,
    }));
    expect(Math.abs(expanded.top - before.top)).toBeLessThanOrEqual(1);
    expect(expanded.scrollTop).toBeGreaterThan(before.scrollTop);

    await control(page, 'collapse');
    await expect(
      page.locator(mainLens + '[data-code-lens-line="10"]'),
    ).toHaveCount(0);
    await settle(page);
    const collapsed = await page.locator(mainHost).evaluate((host) => ({
      top: host
        .querySelector('.view-line[data-line="40"]')
        .getBoundingClientRect().top,
      scrollTop: globalThis.__codeLensControls.state().scrollTop,
    }));
    expect(Math.abs(collapsed.top - before.top)).toBeLessThanOrEqual(1);
    expect(Math.abs(collapsed.scrollTop - before.scrollTop)).toBeLessThanOrEqual(
      1,
    );

    await control(page, 'set_enabled', false);
    await expect(page.locator(mainLens)).toHaveCount(0);
    await expect(
      page.locator(mainHost + ' .codelens-view-zone'),
    ).toHaveCount(0);
    await control(page, 'set_enabled', true);
    await expect(
      page.locator(mainLens + '[data-code-lens-line="40"]'),
    ).toHaveCount(1);
  } finally {
    reporter.dispose();
  }
});
