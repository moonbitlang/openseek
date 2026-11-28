import { test, expect } from '@playwright/test';
import { VizBrowserHarness, traceDocument } from './support/viz_browser_harness.js';

// One run: the root session, a child agent spawned from a tool step inside its
// first turn, and a background job the first turn waited on. Enough shape to
// cover nesting, status colour, the narrowest-bar rule and the critical path.
function demoRun({ live = false } = {}) {
  return traceDocument({
    rootId: 'viz-1',
    t0: 1_000,
    tEnd: 61_000,
    live,
    sessions: [
      { session_id: 'viz-1', title: 'Rewrite the parser', depth: 0, start: 1_000 },
      {
        session_id: 'viz-1-sr-1',
        title: 'Audit the parser',
        depth: 1,
        start: 25_000,
        parent: 'viz-1',
      },
    ],
    spans: [
      { id: 'run', kind: 'run', label: 'viz-1', start: 1_000, end: 61_000, depth: 0 },
      { id: 't1', kind: 'turn', label: 'Turn 1', start: 1_000, end: 40_000, depth: 1, parent: 'run' },
      { id: 'llm1', kind: 'llm', label: 'model call', start: 1_000, end: 6_000, depth: 2, parent: 't1', sequence: 2 },
      {
        id: 'job',
        kind: 'job',
        label: 'background job',
        start: 6_000,
        end: 24_000,
        depth: 2,
        parent: 't1',
        job: 'job-7',
      },
      {
        id: 'sub',
        kind: 'tool',
        label: 'subagent mbtx: Audit the parser',
        start: 24_000,
        end: 39_000,
        depth: 2,
        parent: 't1',
        metadata: { brief: 'explore finished' },
      },
      {
        id: 'sr1-t1',
        kind: 'turn',
        label: 'Turn 1',
        start: 25_000,
        end: 38_000,
        depth: 3,
        parent: 'sub',
        session_id: 'viz-1-sr-1',
        title: 'Audit the parser',
      },
      { id: 't2', kind: 'turn', label: 'Turn 2', start: 40_000, end: 61_000, depth: 1, parent: 'run' },
      {
        id: 'boom',
        kind: 'tool',
        label: 'shell',
        start: 41_000,
        end: 41_003,
        depth: 2,
        parent: 't2',
        status: 'failed',
      },
      {
        id: 'steer',
        kind: 'milestone',
        label: 'steer',
        start: 50_000,
        end: 50_000,
        depth: 2,
        parent: 't2',
        tag: 'steer',
      },
    ],
    stats: { critical_path: ['run', 't2', 'boom'], critical_path_ms: 20_003 },
  });
}

async function openRun(page, viewer) {
  viewer.trajectory = demoRun();
  await viewer.install();
  await viewer.goto('#t=viz-1');
  await page.locator('.waterfall-row').first().waitFor();
}

test('the waterfall draws one run on one axis, parents before children', async ({ page }) => {
  const viewer = new VizBrowserHarness(page);
  await openRun(page, viewer);

  // The header counts the whole run, not just the opened session.
  await expect(page.locator('.header-id')).toHaveText('run viz-1');
  await expect(page.locator('.header-meta')).toContainText('2 session(s)');
  await expect(page.locator('.header-meta')).toContainText('3 turn(s)');

  const rows = page.locator('.waterfall-row');
  await expect(rows).toHaveCount(9);
  // Depth order is the tree order: a child's rows land after the step that
  // spawned them, so the child lane reads as work inside that step.
  // Every row reads as "label, then the lane it belongs to": two sessions both
  // have a `Turn 1`, so the lane caption is what tells them apart.
  const labels = await rows.evaluateAll(elements => elements.map(el => ({
    name: el.querySelector('.waterfall-name').textContent,
    lane: el.querySelector('.waterfall-caption').textContent,
    depth: Number(el.querySelector('.waterfall-label').style.paddingLeft.replace('px', '')),
  })));
  const at = lane => labels.findIndex(row => row.lane === lane);
  const named = name => labels.findIndex(row => row.name === name);
  const spawned = named('subagent mbtx: Audit the parser');
  expect(at('Audit the parser')).toBeGreaterThan(spawned);
  expect(named('Turn 2')).toBeGreaterThan(at('Audit the parser'));
  expect(labels[named('Turn 1')].depth).toBeGreaterThan(labels[0].depth);
  // The caption names the lane the row belongs to, so the child's own rows are
  // distinguishable from the root's even when both say `Turn 1`.
  expect(labels[at('Audit the parser')].lane).toBe('Audit the parser');
  expect(labels[named('Turn 1')].lane).toBe('main');

  // Every bar sits inside the track and none has a negative offset.
  const geometry = await rows.evaluateAll(elements => elements.map(el => {
    const bar = el.querySelector('.waterfall-bar');
    return { left: parseFloat(bar.style.left), width: parseFloat(bar.style.width) };
  }));
  for (const bar of geometry) {
    expect(bar.left).toBeGreaterThanOrEqual(0);
    expect(bar.width).toBeGreaterThan(0);
    if (bar.left < 100) {
      expect(bar.left + bar.width).toBeLessThanOrEqual(100.5);
    }
  }
  // A 3 ms tool call stays visible instead of collapsing to nothing.
  const boom = geometry[named('shell')];
  expect(boom.width).toBeGreaterThanOrEqual(0.35);

  // Status and criticality are readable without hovering.
  await expect(page.locator('.waterfall-row.status-failed')).toHaveCount(1);
  await expect(page.locator('.waterfall-row.critical')).toHaveCount(3);
  // The legend names every kind the run actually uses.
  await expect(page.locator('.waterfall-legend-item')).toHaveCount(8);

  // The headline numbers are cards, and the single failed step is one click
  // away instead of a scroll hunt.
  await expect(page.locator('.stat')).toHaveCount(7);
  await expect(page.locator('.stat').filter({ hasText: 'errors' })).toContainText('1');
  await expect(page.locator('.stat-jump')).toHaveCount(1);
  // An envelope draws what it contains as ticks, so its shape reads even
  // folded. The run holds two turns.
  expect(await rows.first().locator('.waterfall-tick').count()).toBe(2);
  // The ruler says where the work sits on the axis.
  await expect(page.locator('.waterfall-ruler .ruler-seg').first()).toBeVisible();
  // The activity strip draws one column per slice of that same axis, and the
  // failure the run contains is marked on it.
  await expect(page.locator('.activity-col')).toHaveCount(60);
  await expect(page.locator('.activity-error')).not.toHaveCount(0);
  // The hover card is DOM text, so a long prompt is not clipped by `title`.
  await expect(rows.nth(1).locator('.waterfall-tip')).toContainText('turn');

  expect(viewer.pageErrors).toEqual([]);
});

test('a running span extends to the reader clock and stays open', async ({ page }) => {
  const viewer = new VizBrowserHarness(page);
  viewer.trajectory = demoRun({ live: true });
  const trace = JSON.parse(JSON.stringify(viewer.trajectory));
  // The last turn has not ended: the viewer must draw it up to now, not to an
  // invented end, and mark its right edge as open.
  const last = trace.spans.find(span => span.id === 't2');
  delete last.ended_at_ms;
  trace.t_end_ms = last.started_at_ms;
  viewer.trajectory = trace;
  await viewer.install();
  await viewer.goto('#t=viz-1');
  const open = page.locator('.waterfall-row.open');
  await expect(open).toHaveCount(1);
  await expect(open.locator('.waterfall-name')).toHaveText('Turn 2');
  const width = await open.locator('.waterfall-bar')
    .evaluate(bar => parseFloat(bar.style.width));
  expect(width).toBeGreaterThan(0);
  await expect(page.locator('.header-meta')).toContainText('live');
  expect(viewer.pageErrors).toEqual([]);
});

test('the session header opens the run and Back returns to the log', async ({ page }) => {
  const viewer = new VizBrowserHarness(page);
  viewer.trajectory = demoRun();
  await viewer.install();
  await viewer.goto();
  await viewer.openSession();

  await page.getByRole('link', { name: 'Trajectory' }).click();
  await page.locator('.waterfall-row').first().waitFor();
  expect(new URL(page.url()).hash).toBe('#t=viz-1');

  await page.getByRole('button', { name: 'Back to log' }).click();
  await page.locator('.header-id', { hasText: 'viz-1' }).waitFor();
  await expect(page.locator('.waterfall-row')).toHaveCount(0);
  // The run left the address bar too, so a refresh lands on the log again.
  expect(new URL(page.url()).hash).not.toContain('t=');
  expect(viewer.pageErrors).toEqual([]);
});

test('the failures filter keeps the failed step and the rows that place it', async ({ page }) => {
  const viewer = new VizBrowserHarness(page);
  await openRun(page, viewer);
  const rows = page.locator('.waterfall-row');
  await expect(rows).toHaveCount(9);

  // One tool call failed, so the cut keeps it, its turn and the run — and the
  // label counts it before the reader clicks.
  const toggle = page.getByRole('button', { name: /Failures/ });
  await expect(toggle).toContainText('1');
  await toggle.click();
  await expect(rows).toHaveCount(3);
  await expect(rows.last().locator('.waterfall-name')).toHaveText('shell');
  await expect(page.locator('.waterfall-row.status-failed')).toHaveCount(1);

  await toggle.click();
  await expect(rows).toHaveCount(9);
  expect(viewer.pageErrors).toEqual([]);
});

test('a run with no failures says so instead of drawing an empty axis', async ({ page }) => {
  const viewer = new VizBrowserHarness(page);
  const clean = demoRun();
  clean.spans.find(span => span.id === 'boom').status = 'succeeded';
  viewer.trajectory = clean;
  await viewer.install();
  await viewer.goto('#t=viz-1');
  await page.locator('.waterfall-row').first().waitFor();

  const toggle = page.getByRole('button', { name: /Failures/ });
  await expect(toggle).toContainText('none');
  await toggle.click();
  await expect(page.locator('.trajectory-placeholder'))
    .toContainText('no failed steps');
  await expect(page.locator('.waterfall-row')).toHaveCount(0);
  expect(viewer.pageErrors).toEqual([]);
});

test('the axis carries a dated scale and the grid it casts', async ({ page }) => {
  const viewer = new VizBrowserHarness(page);
  viewer.trajectory = demoRun();
  await viewer.install();
  await viewer.goto('#t=viz-1');
  await page.locator('.waterfall-row').first().waitFor();

  const labels = page.locator('.waterfall-scale .scale-label');
  await expect(labels.first()).toBeVisible();
  expect(await labels.count()).toBeGreaterThan(1);
  // One hairline per label, in the column the bars are drawn in, so a mark
  // names the same instant above and below.
  const lines = page.locator('.waterfall-grid-line');
  expect(await lines.count()).toBe(await labels.count());
  expect(await lines.first().evaluate(el => el.style.left))
    .toBe(await labels.first().evaluate(el => el.style.left));
  expect(viewer.pageErrors).toEqual([]);
});

test('a lane spawned by the run is marked with its role', async ({ page }) => {
  const viewer = new VizBrowserHarness(page);
  viewer.trajectory = demoRun();
  await viewer.install();
  await viewer.goto('#t=viz-1');
  await page.locator('.waterfall-row').first().waitFor();

  // One badge per lane, at the head of its rows: the run's own session, and
  // the agent it spawned.
  await expect(page.locator('.lane-role-main')).toHaveCount(1);
  await expect(page.locator('.lane-role-sub')).toHaveCount(1);
  await expect(page.locator('.lane-role-sub'))
    .toHaveAttribute('title', 'sub-agent viz-1-sr-1, spawned by viz-1');
  expect(viewer.pageErrors).toEqual([]);
});

test('a standalone export opens the run it baked, with no server', async ({ page }) => {
  const viewer = new VizBrowserHarness(page);
  viewer.trajectory = demoRun();
  await viewer.install({ standalone: true });
  await viewer.goto();
  await viewer.openSession();

  // The archive carried the run, so the link is offered and the waterfall
  // draws from the baked document — no request leaves the file.
  await page.getByRole('link', { name: 'Trajectory' }).click();
  await expect(page.locator('.waterfall-row')).toHaveCount(9);
  expect(viewer.apiCalls).toEqual([]);
  expect(viewer.pageErrors).toEqual([]);
});

test('a standalone export without that run does not offer the link', async ({ page }) => {
  const viewer = new VizBrowserHarness(page);
  // No `trajectory`: nothing was baked, and there is no server to fold one.
  await viewer.install({ standalone: true });
  await viewer.goto();
  await viewer.openSession();
  await expect(page.getByRole('link', { name: 'Trajectory' })).toHaveCount(0);
  expect(viewer.pageErrors).toEqual([]);
});

test('picking a session from the sidebar leaves the run behind', async ({ page }) => {
  const viewer = new VizBrowserHarness(page);
  viewer.trajectory = demoRun();
  await viewer.install();
  await viewer.goto('#t=viz-1');
  await page.locator('.waterfall-row').first().waitFor();

  await page.locator('.session-item').first().click();
  await page.locator('.waterfall-row').first().waitFor({ state: 'detached' });
  // The run left the address bar too, so a refresh lands on the log the reader
  // chose instead of reopening the waterfall.
  expect(new URL(page.url()).hash).not.toContain('t=');
  expect(viewer.pageErrors).toEqual([]);
});

test('a run the server cannot fold says so instead of drawing an empty axis', async ({ page }) => {
  const viewer = new VizBrowserHarness(page);
  // `this.trajectory` stays null: the route answers 404, as it does for an id
  // with no session file behind it.
  await viewer.install();
  await viewer.goto('#t=viz-missing');
  await expect(page.locator('.trajectory-placeholder')).toContainText('could not load');
  await expect(page.locator('.waterfall-row')).toHaveCount(0);
});

test('a poll that changes nothing keeps the drawing and spends no document', async ({ page }) => {
  const viewer = new VizBrowserHarness(page);
  viewer.trajectoryCursor = 'c1';
  viewer.trajectory = demoRun({ live: true });
  await viewer.install({ watchMs: 60 });
  await viewer.goto('#t=viz-1');
  const rows = page.locator('.waterfall-row');
  await expect(rows).toHaveCount(9);

  // The viewer echoes the cursor the document carried…
  await expect
    .poll(() => viewer.trajectoryRequests.some(url => url.includes('cursor=c1')))
    .toBe(true);
  // …and the `unchanged` answer leaves the drawing exactly as it was.
  await page.waitForTimeout(200);
  await expect(rows).toHaveCount(9);
  await expect(rows.first().locator('.waterfall-name')).toHaveText('viz-1');
  expect(viewer.pageErrors).toEqual([]);
});

test('a row opens its session log at the event the span records', async ({ page }) => {
  const viewer = new VizBrowserHarness(page);
  await openRun(page, viewer);

  const link = page.locator('.waterfall-row')
    .filter({ has: page.locator('.waterfall-name', { hasText: 'model call' }) })
    .first()
    .locator('.waterfall-open');
  // The model call in the fixture is durable event 2 of `viz-1`.
  await expect(link).toHaveAttribute('href', '#s=viz-1&seq=2');
  await link.click();
  // The log replaces the waterfall, and the seq= it arrived with survives the
  // selection so the reader lands on that event.
  await expect(page.locator('.waterfall-row')).toHaveCount(0);
  await expect(page.locator('.header-id', { hasText: 'viz-1' })).toBeVisible();
  expect(new URL(page.url()).hash).toContain('seq=2');
  expect(viewer.pageErrors).toEqual([]);
});

test('folding a step hides its subtree and keeps the rest in place', async ({ page }) => {
  const viewer = new VizBrowserHarness(page);
  await openRun(page, viewer);

  const rows = page.locator('.waterfall-row');
  await expect(rows).toHaveCount(9);
  // Folding the first turn takes its model call, job, subagent step and the
  // whole child lane with it — four rows — and leaves the run, the folded turn
  // itself, and the second turn with its two steps.
  const turn = page.locator('.waterfall-row', { has: page.locator('.waterfall-name', { hasText: /^Turn 1$/ }) }).first();
  await turn.locator('.waterfall-toggle').click();
  await expect(rows).toHaveCount(5);
  await expect(page.locator('.waterfall-row', { hasText: 'Audit the parser' })).toHaveCount(0);
  await expect(page.locator('.waterfall-row.collapsed')).toHaveCount(1);
  // A leaf has nothing to fold, so it keeps an empty slot instead of a chevron.
  const leaf = page.locator('.waterfall-row').filter({ has: page.locator('.waterfall-name', { hasText: /^shell$/ }) });
  await expect(leaf.locator('.waterfall-toggle.placeholder')).toHaveCount(1);

  // Unfolding brings it all back.
  await page.locator('.waterfall-row.collapsed .waterfall-toggle').click();
  await expect(rows).toHaveCount(9);
  expect(viewer.pageErrors).toEqual([]);
});

test('a night of idle folds away, and the axis can show it at scale', async ({ page }) => {
  const viewer = new VizBrowserHarness(page);
  // Two short bursts of work a day apart, inside one run.
  viewer.trajectory = traceDocument({
    rootId: 'viz-1',
    t0: 0,
    tEnd: 86_400_000,
    spans: [
      { id: 'run', kind: 'run', label: 'viz-1', start: 0, end: 86_400_000 },
      { id: 'a', kind: 'tool', label: 'first', start: 0, end: 60_000, parent: 'run' },
      { id: 'b', kind: 'tool', label: 'second', start: 86_340_000, end: 86_400_000, parent: 'run' },
    ],
  });
  await viewer.install();
  await viewer.goto('#t=viz-1');
  await page.locator('.waterfall-row').first().waitFor();

  const width = async () => page.locator('.waterfall-row')
    .filter({ has: page.locator('.waterfall-name', { hasText: /^first$/ }) })
    .locator('.waterfall-bar')
    .evaluate(bar => parseFloat(bar.style.width));

  // Folded: a minute of work is a real share of the frame, not a hairline.
  const folded = await width();
  expect(folded).toBeGreaterThan(20);
  await expect(page.locator('.trajectory-totals')).toContainText('idle folded');
  // The folded night is a narrow slot that says how long it really was.
  await expect(page.locator('.ruler-gap')).toHaveCount(1);
  await expect(page.locator('.ruler-gap').first()).toContainText('23h');

  // At true scale the same minute is a sliver of the day, as it really is.
  await page.locator('.mode-button', { hasText: 'Idle folded' }).click();
  // Wait for the re-render before measuring: the width is read off the DOM.
  await expect(page.locator('.mode-button', { hasText: 'Idle at scale' })).toBeVisible();
  await expect(page.locator('.trajectory-totals')).not.toContainText('idle folded');
  // At true scale nothing is folded, so no idle slot is drawn.
  await expect(page.locator('.ruler-gap')).toHaveCount(0);
  expect(await width()).toBeLessThan(1);
  expect(viewer.pageErrors).toEqual([]);
});

// A job's own output: the record and a page of the file it wrote, as
// `/api/sessions/<key>/jobs/<job>` serves them.
function jobReply({
  text = '',
  size = text.length,
  nextOffset = size,
  headOmitted = false,
  stale = false,
  outputBytes = size,
  outputTruncated = false,
  state = { kind: 'exited', code: 0 },
  error = null,
}) {
  return {
    found: true,
    job: {
      id: 'job-7',
      generation: 'gen-1',
      state,
      command: 'mbtx run build.mbtx',
      description: 'build the package',
      started_at_ms: 6_000,
      finished_at_ms: 24_000,
      output_bytes: outputBytes,
      output_file: 'fg-7.out',
      output_truncated: outputTruncated,
      invalid_utf8: false,
      output_error: null,
    },
    output: error === null
      ? { text, start_offset: size - text.length, next_offset: nextOffset, size, head_omitted: headOmitted, stale }
      : { error },
  };
}

test('a job row opens the log the job wrote', async ({ page }) => {
  const viewer = new VizBrowserHarness(page);
  viewer.trajectory = demoRun();
  viewer.jobLogs.set('viz-1/job-7', jobReply({
    text: 'building\nwarning: unused import\n',
  }));
  await viewer.install();
  await viewer.goto('#t=viz-1');
  await page.locator('.waterfall-row').first().waitFor();

  const jobRow = page.locator('.waterfall-row.kind-job');
  // The way in is on the row itself, not behind a hover: a job that ran for
  // forty minutes is the row a reader most wants to open.
  const button = jobRow.locator('.job-log-button');
  await expect(button).toBeVisible();
  await expect(button).toHaveAttribute('aria-expanded', 'false');
  await button.click();

  const block = page.locator('.job-log');
  await expect(block.locator('.job-log-text')).toContainText('warning: unused import');
  // The header says which job and how it ended, so a scrolled-past row still
  // reads.
  await expect(block.locator('.job-log-title')).toContainText('job job-7');
  await expect(block.locator('.job-log-title')).toContainText('exited 0');
  // The span's own start rides along, so a legacy job id reused by an earlier
  // engine run resolves to the record this row is about.
  expect(viewer.jobRequests).toEqual(['/api/sessions/viz-1/jobs/job-7?start=6000']);
  await expect(button).toHaveAttribute('aria-expanded', 'true');

  // Folding it away leaves the row, and opening it again does not re-read a
  // finished job.
  await block.locator('.job-log-close').click();
  await expect(page.locator('.job-log')).toHaveCount(0);
  await expect(button).toHaveAttribute('aria-expanded', 'false');
  expect(viewer.pageErrors).toEqual([]);
});

test('a job with no saved record says so instead of showing an empty log', async ({ page }) => {
  const viewer = new VizBrowserHarness(page);
  await openRun(page, viewer);

  await page.locator('.waterfall-row.kind-job .job-log-button').click();
  // A missing record and an empty file must not look alike: one is an error.
  const error = page.locator('.job-log-error');
  await expect(error).toHaveAttribute('role', 'alert');
  await expect(error).toContainText('no saved record');
  await expect(page.locator('.job-log-text')).toHaveCount(0);
  expect(viewer.pageErrors).toEqual([]);
});

test('a long job log says its earlier output is not shown', async ({ page }) => {
  const viewer = new VizBrowserHarness(page);
  viewer.trajectory = demoRun();
  viewer.jobLogs.set('viz-1/job-7', jobReply({
    text: 'tail line\n',
    size: 4_200_000,
    nextOffset: 4_200_000,
    outputBytes: 4_200_000,
    headOmitted: true,
  }));
  await viewer.install();
  await viewer.goto('#t=viz-1');
  await page.locator('.waterfall-row').first().waitFor();

  await page.locator('.waterfall-row.kind-job .job-log-button').click();
  await expect(page.locator('.job-log-text')).toContainText('tail line');
  await expect(page.locator('.job-log-note')).toContainText('earlier output is not shown');
  await expect(page.locator('.job-log-title')).toContainText('4 MB');
  expect(viewer.pageErrors).toEqual([]);
});

test('a running job appends what it printed since the last page', async ({ page }) => {
  const viewer = new VizBrowserHarness(page);
  viewer.trajectory = demoRun({ live: true });
  viewer.jobLogs.set('viz-1/job-7', url => {
    // The first page is the tail so far; a poll continuing from its end gets
    // the lines written since, exactly as the store would answer.
    if (url.searchParams.get('cursor') === String('12')) {
      return jobReply({
        text: 'second page\n',
        size: 24,
        nextOffset: 24,
        state: { kind: 'running' },
      });
    }
    return jobReply({
      text: 'first page\n',
      size: 12,
      nextOffset: 12,
      state: { kind: 'running' },
    });
  });
  await viewer.install({ watchMs: 60 });
  await viewer.goto('#t=viz-1');
  await page.locator('.waterfall-row').first().waitFor();

  await page.locator('.waterfall-row.kind-job .job-log-button').click();
  const text = page.locator('.job-log-text');
  await expect(text).toContainText('first page');
  // The open log follows its own file while the job runs, from where the last
  // page ended rather than from the top.
  await expect
    .poll(() => viewer.jobRequests.some(url => url.includes('cursor=12')))
    .toBe(true);
  await expect(text).toContainText('second page');
  expect(viewer.pageErrors).toEqual([]);
});

test('a standalone export offers no job log it cannot read', async ({ page }) => {
  const viewer = new VizBrowserHarness(page);
  // An archive bakes session logs and trajectories, not job outputs, so the
  // button would only fail on click; it is not offered.
  viewer.trajectory = demoRun();
  await viewer.install({ standalone: true });
  await viewer.goto();
  await viewer.openSession();
  await page.getByRole('link', { name: 'Trajectory' }).click();
  await expect(page.locator('.waterfall-row.kind-job')).toHaveCount(1);
  await expect(page.locator('.job-log-button')).toHaveCount(0);
  expect(viewer.pageErrors).toEqual([]);
});

test('multiple idle gaps keep ruler segments aligned with waterfall bars', async ({ page }) => {
  const viewer = new VizBrowserHarness(page);
  viewer.trajectory = traceDocument({
    rootId: 'viz-1',
    t0: 0,
    tEnd: 100_000_000,
    spans: [
      { id: 'run', kind: 'run', label: 'viz-1', start: 0, end: 100_000_000 },
      { id: 's1', kind: 'tool', label: 's1', start: 0, end: 10_000, parent: 'run' },
      { id: 's2', kind: 'tool', label: 's2', start: 20_000_000, end: 20_010_000, parent: 'run' },
      { id: 's3', kind: 'tool', label: 's3', start: 40_000_000, end: 40_010_000, parent: 'run' },
      { id: 's4', kind: 'tool', label: 's4', start: 60_000_000, end: 60_010_000, parent: 'run' },
      { id: 's5', kind: 'tool', label: 's5', start: 99_990_000, end: 100_000_000, parent: 'run' },
    ],
  });
  await viewer.install();
  await viewer.goto('#t=viz-1');
  await page.locator('.waterfall-row').first().waitFor();

  const seg = page.locator('.ruler-seg').last();
  const bar = page.locator('.waterfall-row')
    .filter({ has: page.locator('.waterfall-name', { hasText: /^s5$/ }) })
    .locator('.waterfall-bar');
  const segLeft = await seg.evaluate(el => parseFloat(el.style.left));
  const barLeft = await bar.evaluate(el => parseFloat(el.style.left));
  expect(Math.abs(segLeft - barLeft)).toBeLessThan(0.2);
  expect(viewer.pageErrors).toEqual([]);
});

test('failures filter reveals a failed step inside a collapsed turn', async ({ page }) => {
  const viewer = new VizBrowserHarness(page);
  await openRun(page, viewer);
  const turn = page.locator('.waterfall-row', { has: page.locator('.waterfall-name', { hasText: /^Turn 2$/ }) }).first();
  await turn.locator('.waterfall-toggle').click();
  await expect(page.locator('.waterfall-row.status-failed')).toHaveCount(0);

  await page.getByRole('button', { name: /Failures/ }).click();
  await expect(page.locator('.waterfall-row.status-failed')).toHaveCount(1);
  expect(viewer.pageErrors).toEqual([]);
});

test('a multi-job wait row opens each waited job log independently', async ({ page }) => {
  const viewer = new VizBrowserHarness(page);
  viewer.trajectory = traceDocument({
    rootId: 'viz-1',
    t0: 0,
    tEnd: 10_000,
    spans: [
      { id: 'run', kind: 'run', label: 'viz-1', start: 0, end: 10_000 },
      { id: 'wait', kind: 'wait', label: 'job_wait', start: 1_000, end: 8_000, parent: 'run', job: 'job-1', jobs: ['job-1', 'job-2'] },
    ],
  });
  viewer.jobLogs.set('viz-1/job-1', jobReply({ text: 'output from one\n' }));
  viewer.jobLogs.set('viz-1/job-2', jobReply({ text: 'output from two\n' }));
  await viewer.install();
  await viewer.goto('#t=viz-1');
  await page.locator('.waterfall-row').first().waitFor();

  const waitRow = page.locator('.waterfall-row.kind-wait');
  await waitRow.getByRole('button', { name: /job-1\.out/ }).click();
  await waitRow.getByRole('button', { name: /job-2\.out/ }).click();
  await expect(page.locator('.job-log-text')).toHaveCount(2);
  await expect(page.locator('.job-log-text').nth(0)).toContainText('output from one');
  await expect(page.locator('.job-log-text').nth(1)).toContainText('output from two');
  expect(viewer.pageErrors).toEqual([]);
});

test('deep-linking #t=<root>&job=<id> highlights the job row and opens its log', async ({ page }) => {
  const viewer = new VizBrowserHarness(page);
  viewer.trajectory = demoRun();
  viewer.jobLogs.set('viz-1/job-7', jobReply({ text: 'focused output\n' }));
  await viewer.install();
  await viewer.goto('#t=viz-1&job=job-7');

  const focused = page.locator('.waterfall-row.job-focus');
  await expect(focused).toHaveCount(1);
  await expect(focused).toHaveClass(/kind-job/);
  await expect(page.locator('.job-log-text')).toContainText('focused output');
  expect(viewer.pageErrors).toEqual([]);
});

test('deep-linking #t=<root>&job=<id>&start=<ms> disambiguates repeated legacy job ids', async ({ page }) => {
  const viewer = new VizBrowserHarness(page);
  viewer.trajectory = traceDocument({
    rootId: 'viz-1',
    t0: 0,
    tEnd: 12_000,
    spans: [
      { id: 'run', kind: 'run', label: 'viz-1', start: 0, end: 12_000 },
      { id: 'job-old', kind: 'job', label: 'background job bg-1', start: 1_000, end: 3_000, parent: 'run', job: 'bg-1' },
      { id: 'job-new', kind: 'job', label: 'background job bg-1', start: 7_000, end: 10_000, parent: 'run', job: 'bg-1' },
    ],
  });
  await viewer.install();
  await viewer.goto('#t=viz-1&job=bg-1&start=7000');

  const focused = page.locator('.waterfall-row.job-focus');
  await expect(focused).toHaveCount(1);
  await expect(page.locator('.waterfall-row.kind-job').nth(1)).toHaveClass(/job-focus/);
  expect(viewer.pageErrors).toEqual([]);
});
