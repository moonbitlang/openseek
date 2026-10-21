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

test('CodeLens rows sit above and align with source', async ({
  page,
}, testInfo) => {
  const reporter = await mountCodeLens(page, testInfo);
  try {
    const row = page.locator(
      mainLens + '[data-code-lens-line="2"]',
    );
    await expect(row).toBeVisible();
    await expect(row).toContainText('Outside');

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
        fontFamily: style.fontFamily,
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
    // VS Code parity: an unset CodeLens family uses the UI font, not the code
    // font of the line below it.
    const codeFamily = await page
      .locator(mainHost + ' .view-lines')
      .evaluate((node) => getComputedStyle(node).fontFamily);
    expect(geometry.fontFamily).not.toBe(codeFamily);
    expect(geometry.fontFamily.toLowerCase()).not.toContain('monospace');

    await expect(row.locator(':scope > a')).toHaveCount(2);
    await expect(row.locator('.codelens-separator')).toHaveCount(1);
    expect(await row.textContent()).toBe(
      '3 references\u00a0|\u00a0Outside',
    );
    await expect(
      row.getByRole('button', { name: '3 references', exact: true }),
    ).toHaveAttribute('title', 'Show references');

    const plain = page.locator(plainHost + ' .codelens-decoration');
    await expect(plain).toBeVisible();
    await expect(plain.getByRole('button', { name: 'references' })).toBeVisible();
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

test('CodeLens actions respond once to click, Enter and Space', async ({
  page,
}, testInfo) => {
  const reporter = await mountCodeLens(page, testInfo);
  try {
    const command = page.locator(mainHost).getByRole('button', {name: '3 references', exact: true});
    await command.click();
    await command.focus();
    await command.press('Enter');
    await command.press('Space');
    await expect.poll(async () => (await state(page)).executions).toEqual([
      '3 references', '3 references', '3 references',
    ]);

  } finally {
    reporter.dispose();
  }
});

test('CodeLens row refresh preserve the viewport anchor', async ({
  page,
}, testInfo) => {
  const reporter = await mountCodeLens(page, testInfo);
  try {
    await control(page, 'scroll_late');
    await settle(page);
    const late = page.locator(
      mainLens + '[data-code-lens-line="40"]',
    );
    await expect(late).toBeVisible();
    await expect(late).toContainText('late references');

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
