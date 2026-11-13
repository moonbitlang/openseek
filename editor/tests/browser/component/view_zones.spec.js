import { expect, gotoBrowserScenario, test } from '../support/test.js';
import {
  expectMoonBitReportPassed,
  installMoonBitReporter,
} from '../support/moonbit_reporter.js';

const host = '.view-zones-host';

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

async function mountViewZones(page, testInfo) {
  const reporter = await installMoonBitReporter(page);
  await gotoBrowserScenario(page, 'view-zones');
  await page.waitForFunction(() => Boolean(globalThis.__viewZonesControls));
  const report = await reporter.waitForReport(testInfo, {
    suite: 'view_zones',
    timeout: 10_000,
  });
  expectMoonBitReportPassed(report, { suite: 'view_zones' });
  expect(report.metrics.registeredZones).toBeGreaterThanOrEqual(7);
  await settle(page);
  return reporter;
}

async function state(page) {
  return page.evaluate(() => globalThis.__viewZonesControls.state());
}

async function control(page, name, ...args) {
  return page.evaluate(
    ({ method, values }) => globalThis.__viewZonesControls[method](...values),
    { method: name, values: args },
  );
}

test('ViewZones preserve caller DOM across real browser mounting', async ({
  page,
}, testInfo) => {
  const reporter = await mountViewZones(page, testInfo);
  try {
    const primary = page.locator(`${host} .vz-primary`);
    const primaryChild = primary.locator('.vz-primary-child');
    const primaryMargin = page.locator(`${host} .vz-primary-margin`);
    const primaryId = await primary.getAttribute('monaco-view-zone');
    expect(primaryId).toBeTruthy();
    await expect(primaryMargin).toHaveAttribute('monaco-view-zone', primaryId);
    await expect(primary).toHaveAttribute('aria-hidden', 'true');
    await expect(primary).toHaveAttribute('data-caller-owned', 'primary');
    await expect(primaryMargin).toHaveAttribute('data-caller-owned', 'margin');
    await expect(primary).toHaveClass(/\bhost-primary\b/);
    await expect(primary).toHaveClass(/\bpreserved-class\b/);
    await expect(primary).not.toHaveClass(/\bview-zone\b/);
    await expect(primary).toHaveCSS('color', 'rgb(1, 2, 3)');
    await expect(primary).toHaveCSS('border-left-color', 'rgb(4, 5, 6)');
    await expect(primary).toHaveCSS('padding-left', '7px');
    await expect(primaryChild).toHaveAttribute('data-caller-state', 'preserved');
    await expect(primaryMargin).toHaveClass(/\bpreserved-margin-class\b/);
    await expect(primaryMargin).toHaveCSS(
      'background-color',
      'rgb(7, 8, 9)',
    );

    await primaryChild.dispatchEvent('click');
    await primaryMargin.dispatchEvent('click');
    expect(await control(page, 'click_counts')).toEqual({
      primary: 1,
      child: 1,
      margin: 1,
    });

    const attachment = await page.locator(host).evaluate((fixture) => {
      const margin = fixture.querySelector('.margin');
      const linesContent = fixture.querySelector('.lines-content');
      const contentContainer = fixture.querySelector('.view-zones');
      const marginContainer = fixture.querySelector('.margin-view-zones');
      const primaryNode = fixture.querySelector('.vz-primary');
      const secondaryNode = fixture.querySelector('.vz-secondary');
      const primaryMarginNode = fixture.querySelector('.vz-primary-margin');
      const contentChildren = Array.from(linesContent.children);
      const marginChildren = Array.from(margin.children);
      return {
        contentRole: contentContainer.getAttribute('role'),
        marginRole: marginContainer.getAttribute('role'),
        marginAria: marginContainer.getAttribute('aria-hidden'),
        marginOwnsZones: marginContainer.parentElement === margin,
        marginZoneIndex: marginChildren.indexOf(marginContainer),
        marginOverlayIndex: marginChildren.indexOf(
          fixture.querySelector('.margin-view-overlays'),
        ),
        contentOverlayIndex: contentChildren.indexOf(
          fixture.querySelector('.view-overlays'),
        ),
        contentZoneIndex: contentChildren.indexOf(contentContainer),
        contentLineIndex: contentChildren.indexOf(
          fixture.querySelector('.view-lines'),
        ),
        primaryTop: Number.parseFloat(primaryNode.style.top),
        secondaryTop: Number.parseFloat(secondaryNode.style.top),
        marginTop: Number.parseFloat(primaryMarginNode.style.top),
        primaryHeight: Number.parseFloat(primaryNode.style.height),
        marginHeight: Number.parseFloat(primaryMarginNode.style.height),
      };
    });
    expect(attachment).toMatchObject({
      contentRole: 'presentation',
      marginRole: 'presentation',
      marginAria: 'true',
      marginOwnsZones: true,
      primaryHeight: 32,
      marginHeight: 32,
    });
    expect(attachment.marginTop).toBe(attachment.primaryTop);
    expect(attachment.marginZoneIndex).toBeLessThan(attachment.marginOverlayIndex);
    expect(attachment.contentOverlayIndex).toBeLessThan(
      attachment.contentZoneIndex,
    );
    expect(attachment.contentZoneIndex).toBeLessThan(
      attachment.contentLineIndex,
    );
    expect(attachment.secondaryTop).toBeLessThan(attachment.primaryTop);
  } finally {
    reporter.dispose();
  }
});

test('ViewZones use offscreen callback tops and retain widths when none are visible', async ({
  page,
}, testInfo) => {
  const reporter = await mountViewZones(page, testInfo);
  try {
    const initial = await state(page);
    expect(initial.primaryLastTop).toBeGreaterThan(-1_000_000);
    expect(initial.offscreenLastTop).toBe(-1_000_000);
    const containers = await page.locator(host).evaluate((fixture) => ({
      contentWidth: Number.parseFloat(
        fixture.querySelector('.view-zones').style.width,
      ),
      marginWidth: Number.parseFloat(
        fixture.querySelector('.margin-view-zones').style.width,
      ),
      contentWidthText: fixture.querySelector('.view-zones').style.width,
      marginWidthText: fixture.querySelector('.margin-view-zones').style.width,
    }));
    expect(containers.contentWidth).toBe(
      Math.max(initial.scrollWidth, initial.contentWidth),
    );
    expect(containers.marginWidth).toBe(initial.contentLeft);
    await expect(page.locator(`${host} .vz-offscreen`)).not.toHaveAttribute(
      'monaco-visible-view-zone',
      'true',
    );
    await expect(page.locator(`${host} .vz-offscreen`)).toHaveCSS(
      'display',
      'none',
    );
    await expect(page.locator(`${host} .vz-offscreen`)).toHaveCSS('top', '0px');
    await expect(page.locator(`${host} .vz-offscreen`)).toHaveCSS(
      'height',
      '0px',
    );

    // The content rail is translated while the merged local `.margin` root is
    // viewport-fixed. ViewZones must nevertheless keep its gutter companion
    // at the exact same client-space top after a nonzero scroll.
    await control(page, 'set_scroll_top', 20);
    await settle(page);
    const pairedRects = await page.locator(host).evaluate((fixture) => ({
      content: fixture.querySelector('.vz-suppress').getBoundingClientRect().top,
      margin: fixture
        .querySelector('.vz-suppress-margin')
        .getBoundingClientRect().top,
      contentInlineTop: fixture.querySelector('.vz-suppress').style.top,
      marginInlineTop: fixture.querySelector('.vz-suppress-margin').style.top,
    }));
    expect(pairedRects.marginInlineTop).toBe(pairedRects.contentInlineTop);
    expect(Math.abs(pairedRects.content - pairedRects.margin)).toBeLessThanOrEqual(
      1,
    );

    // This scroll band lies after every top zone and before the line-40 zone.
    await control(page, 'set_scroll_top', 400);
    await settle(page);
    const gap = await state(page);
    expect(gap.scrollTop).toBe(400);
    await expect(page.locator(`${host} [monaco-visible-view-zone]`)).toHaveCount(
      0,
    );
    expect(gap.primaryLastTop).toBe(-1_000_000 - gap.scrollTop);
    expect(gap.offscreenLastTop).toBe(-1_000_000 - gap.scrollTop);
    const retainedWidths = await page.locator(host).evaluate((fixture) => ({
      content: fixture.querySelector('.view-zones').style.width,
      margin: fixture.querySelector('.margin-view-zones').style.width,
    }));
    expect(retainedWidths).toEqual({
      content: containers.contentWidthText,
      margin: containers.marginWidthText,
    });

    await control(page, 'show_offscreen');
    await settle(page);
    const visible = await state(page);
    await expect(page.locator(`${host} .vz-offscreen`)).toHaveAttribute(
      'monaco-visible-view-zone',
      'true',
    );
    await expect(page.locator(`${host} .vz-offscreen`)).toHaveCSS(
      'display',
      'block',
    );
    await expect(page.locator(`${host} .vz-offscreen`)).toHaveCSS(
      'height',
      '28px',
    );
    expect(visible.offscreenLastTop).toBeGreaterThanOrEqual(0);
    expect(visible.offscreenLastTop).toBeLessThan(260);
  } finally {
    reporter.dispose();
  }
});

async function zonePoint(locator) {
  const box = await locator.boundingBox();
  expect(box).not.toBeNull();
  // Content-zone width follows scrollWidth and can extend far beyond the
  // clipped editor viewport; choose a point near its visible left edge.
  return {
    x: box.x + Math.min(box.width / 2, 20),
    y: box.y + box.height / 2,
  };
}

async function mouseDownAt(page, point, button = 'left') {
  await page.mouse.move(point.x, point.y);
  await page.mouse.down({ button });
  await page.mouse.up({ button });
  await settle(page);
}

test('ViewZone suppressMouseDown is live for content and gutter hits', async ({
  page,
}, testInfo) => {
  const reporter = await mountViewZones(page, testInfo);
  try {
    const initial = await state(page);
    const omitted = page.locator(`${host} .vz-omitted-suppress`);
    const primaryMargin = page.locator(`${host} .vz-primary-margin`);
    const suppressed = page.locator(`${host} .vz-suppress`);
    const suppressedMargin = page.locator(`${host} .vz-suppress-margin`);
    await expect(omitted).toBeVisible();
    await expect(primaryMargin).toBeVisible();
    await expect(suppressed).toBeVisible();
    await expect(suppressedMargin).toBeVisible();

    await control(page, 'focus_sink');
    await control(page, 'clear_mouse');
    await mouseDownAt(page, await zonePoint(omitted));
    let records = await control(page, 'mouse_records');
    expect(records).toHaveLength(1);
    expect(records[0]).toMatchObject({
      button: 0,
      defaultPrevented: false,
      activeRoot: false,
    });
    expect(await state(page)).toMatchObject({
      mouseTargetId: initial.omittedId,
      mouseTargetKind: 'content',
    });

    // Omitted suppressMouseDown is false for a gutter companion too.
    await control(page, 'focus_sink');
    await control(page, 'clear_mouse');
    await mouseDownAt(page, await zonePoint(primaryMargin));
    records = await control(page, 'mouse_records');
    expect(records).toHaveLength(1);
    expect(records[0]).toMatchObject({
      button: 0,
      defaultPrevented: false,
      activeRoot: false,
    });
    expect(await state(page)).toMatchObject({
      mouseTargetId: initial.primaryId,
      mouseTargetKind: 'gutter',
    });

    // Explicit false is the same branch, read live from the retained delegate.
    await control(page, 'set_primary_suppress', false);
    await control(page, 'focus_sink');
    await control(page, 'clear_mouse');
    await mouseDownAt(page, await zonePoint(primaryMargin));
    records = await control(page, 'mouse_records');
    expect(records[0]).toMatchObject({
      button: 0,
      defaultPrevented: false,
      activeRoot: false,
    });

    await control(page, 'focus_sink');
    await control(page, 'clear_mouse');
    await mouseDownAt(page, await zonePoint(suppressed));
    records = await control(page, 'mouse_records');
    expect(records).toHaveLength(1);
    expect(records[0]).toMatchObject({
      button: 0,
      defaultPrevented: true,
      activeRoot: true,
    });
    expect(await state(page)).toMatchObject({
      mouseTargetId: initial.suppressId,
      mouseTargetKind: 'content',
    });

    // Middle-button is still a handled mouse-down when suppression is live.
    await control(page, 'focus_sink');
    await control(page, 'clear_mouse');
    await mouseDownAt(page, await zonePoint(suppressed), 'middle');
    records = await control(page, 'mouse_records');
    expect(records).toHaveLength(1);
    expect(records[0]).toMatchObject({
      button: 1,
      defaultPrevented: true,
      activeRoot: true,
    });

    await control(page, 'focus_sink');
    await control(page, 'clear_mouse');
    await mouseDownAt(page, await zonePoint(suppressedMargin));
    records = await control(page, 'mouse_records');
    expect(records).toHaveLength(1);
    expect(records[0]).toMatchObject({
      button: 0,
      defaultPrevented: true,
      activeRoot: true,
    });
    expect(await state(page)).toMatchObject({
      mouseTargetId: initial.suppressId,
      mouseTargetKind: 'gutter',
    });

    // A right-button mousedown is not a handled selection start.
    await control(page, 'focus_sink');
    await control(page, 'clear_mouse');
    await mouseDownAt(page, await zonePoint(suppressed), 'right');
    records = await control(page, 'mouse_records');
    expect(records).toHaveLength(1);
    expect(records[0]).toMatchObject({
      button: 2,
      defaultPrevented: false,
      activeRoot: false,
    });
    expect(await state(page)).toMatchObject({
      mouseTargetId: initial.suppressId,
      mouseTargetKind: 'content',
    });

    // The delegate is read live; no layout transaction is required.
    await control(page, 'set_suppress', false);
    await control(page, 'focus_sink');
    await control(page, 'clear_mouse');
    await mouseDownAt(page, await zonePoint(suppressed));
    records = await control(page, 'mouse_records');
    expect(records[0]).toMatchObject({
      defaultPrevented: false,
      activeRoot: false,
    });
    expect(await state(page)).toMatchObject({
      mouseTargetId: initial.suppressId,
      mouseTargetKind: 'content',
    });

    await control(page, 'focus_sink');
    await control(page, 'clear_mouse');
    await mouseDownAt(page, await zonePoint(suppressedMargin));
    records = await control(page, 'mouse_records');
    expect(records[0]).toMatchObject({
      button: 0,
      defaultPrevented: false,
      activeRoot: false,
    });
    expect(await state(page)).toMatchObject({
      mouseTargetId: initial.suppressId,
      mouseTargetKind: 'gutter',
    });
    expect((await state(page)).mouseEvents).toBe(initial.mouseEvents + 9);
  } finally {
    reporter.dispose();
  }
});
