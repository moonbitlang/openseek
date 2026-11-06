import { test, expect } from './support/test.js';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';

const hostPath = '/runtime/host-mcp.json';
const userPath = '/home/user/.openseek/mcp.json';

function statusRequests(app) {
  return app.requests.filter(request => request.method === 'mcp.status');
}

function running(status) {
  return { engine: 'running', status };
}

function loaded(...paths) {
  return paths.map(path => ({ path, state: 'loaded' }));
}

function overview(page) {
  return page.locator('#conversation-overview');
}

async function showOverview(page) {
  await page.locator('#conversation-overview-toggle').click();
  const panel = overview(page);
  await expect(panel).toBeVisible();
  return panel;
}

// Show the overview and unfold its connectors card.
async function openConnectors(page) {
  const panel = await showOverview(page);
  await panel.locator('[data-overview-card=connectors]').getByTestId('overview-card-toggle').click();
  return panel;
}

test('the overview shows what the conversation\'s engine is connected to', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  app.mcpStatus = running({
    configs: loaded(hostPath, userPath),
    servers: [
      {
        name: 'seekmoon',
        transport: 'http',
        target: 'http://127.0.0.1:4321/mcp',
        state: 'connected',
        tools: [
          { name: 'mcp__seekmoon__browser_tabs', description: 'List the Browser tabs' },
          { name: 'mcp__seekmoon__browser_open', description: 'Open a Browser tab' },
          { name: 'mcp__seekmoon__browser_navigate', description: 'Navigate a Browser tab' },
        ],
      },
      {
        name: 'playwright',
        transport: 'stdio',
        target: 'npx',
        state: 'connected',
        tools: [
          { name: 'mcp__playwright__browser_navigate', description: 'Navigate to a URL' },
          { name: 'mcp__playwright__browser_click', description: 'Perform click on a web page' },
        ],
      },
      {
        name: 'docs',
        transport: 'http',
        target: 'https://example.com/mcp',
        state: 'failed',
        error: 'JSON-RPC error -32000: MCP endpoint exchange failed',
      },
      {
        name: 'memory',
        transport: 'stdio',
        target: 'memory-mcp',
        state: 'lost',
        tools: [{ name: 'mcp__memory__recall', description: 'Recall a note' }],
      },
      { name: 'notes', transport: 'stdio', target: 'notes-mcp', state: 'no_tools' },
    ],
  });
  await app.install();
  await app.goto();
  await app.openSession();
  // Folded, the card is one line; unfolded, it lists every server.
  const panel = await showOverview(page);
  await expect(panel.locator('[data-overview-card=connectors] .conv-overview-summary')).toHaveText('2 connected · 2 failed');
  await panel.locator('[data-overview-card=connectors]').getByTestId('overview-card-toggle').click();
  await expect(panel.locator('[data-overview-card=connectors] .conv-overview-summary')).toBeHidden();
  const seekmoon = panel.locator('[data-connector-id="server:seekmoon"]');
  await expect(seekmoon.locator('.connectors-state')).toContainText('3 tools');
  // How a server is reached and its tools are on hover.
  await expect(seekmoon).toHaveAttribute('title', /http · http:\/\/127\.0\.0\.1:4321\/mcp/);
  const playwright = panel.locator('[data-connector-id="server:playwright"]');
  await expect(playwright).toHaveAttribute('title', /mcp__playwright__browser_click — Perform click on a web page/);
  const docs = panel.locator('[data-connector-id="server:docs"]');
  await expect(docs.locator('.connectors-state')).toContainText('Failed');
  await expect(docs.locator('.connectors-detail')).toContainText('JSON-RPC error -32000: MCP endpoint exchange failed');
  await expect(panel.locator('[data-connector-id="server:memory"] .connectors-state')).toHaveText('Disconnected');
  await expect(panel.locator('[data-connector-id="server:notes"] .connectors-state')).toHaveText('No tools');

  // The question names the conversation on screen, whose engine is asked.
  expect(statusRequests(app).map(request => request.params)).toEqual([{ session: 'session-1' }]);

  // The overview is a window preference, not a menu: a click elsewhere leaves
  // it, and only its titlebar control hides it.
  await page.locator('.transcript').click();
  await expect(panel).toBeVisible();
  await page.locator('#conversation-overview-toggle').click();
  await expect(panel).toBeHidden();
  expect(app.pageErrors).toEqual([]);
});

test('the connectors card says when there is no engine, and asks again on reshow and refresh', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  await app.install();
  await app.goto();
  await app.openSession();
  let panel = await openConnectors(page);
  await expect(panel.locator('.connectors-note')).toHaveText('Not running. Servers connect with the next message.');
  expect(statusRequests(app)).toHaveLength(1);

  // Asking reads the engine's state and starts nothing, so every showing
  // asks. A file the engine could not load is listed by its full path. The
  // card stays unfolded across hide and show.
  await page.locator('#conversation-overview-toggle').click();
  await expect(panel).toBeHidden();
  app.mcpStatus = running({
    configs: [
      ...loaded(hostPath),
      { path: userPath, state: 'failed', error: 'mcp config error: configuration is missing an `mcpServers` object' },
    ],
    servers: [],
  });
  await page.locator('#conversation-overview-toggle').click();
  panel = overview(page);
  const config = panel.locator(`[data-connector-id="config:${userPath}"]`);
  await expect(config.locator('.connectors-name')).toHaveText(userPath);
  await expect(config.locator('.connectors-detail')).toContainText('configuration is missing an `mcpServers` object');
  await expect(config).toHaveAttribute('title', new RegExp(userPath.replaceAll('.', '\\.')));
  expect(statusRequests(app)).toHaveLength(2);

  app.mcpStatus = running({ configs: [], servers: [] });
  await panel.locator('#connectors-refresh').click();
  await expect(panel.locator('.connectors-note')).toHaveText('No MCP servers configured.');
  expect(statusRequests(app)).toHaveLength(3);

  // A question the host could not answer is reported as that, not as an
  // engine that is not running.
  app.rpcErrors.set('mcp.status', 'the host did not answer');
  await panel.locator('#connectors-refresh').click();
  await expect(panel.locator('[data-connector-id=status-error] .connectors-name')).toHaveText('The status could not be read');
  await expect(panel.locator('[data-connector-id=status-error] .connectors-detail')).toHaveText('the host did not answer');
  expect(app.pageErrors).toEqual([]);
});

test('the connectors card follows what the engine reports while it is shown', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  // The engine has started and is still connecting its servers.
  app.mcpStatus = { engine: 'connecting' };
  await app.install();
  await app.goto();
  await app.openSession();
  const panel = await openConnectors(page);
  await expect(panel.locator('.connectors-note')).toHaveText('Connecting…');
  expect(statusRequests(app)).toHaveLength(1);

  // The engine reports. The host keeps the report and forwards the event;
  // the page reads the kept state again rather than trusting the event.
  const report = servers => {
    const status = { configs: loaded(userPath), servers };
    app.mcpStatus = running(status);
    app.notify('agent.event', { session: 'session-1', event: { event: 'mcp_status', status } });
  };
  const tools = [{ name: 'mcp__memory__recall', description: 'Recall a note' }];
  const memory = state => ({ name: 'memory', transport: 'stdio', target: 'memory-mcp', state, tools });
  report([memory('connected')]);
  await expect(panel.locator('[data-connector-id="server:memory"] .connectors-state')).toHaveText('1 tool');
  expect(statusRequests(app)).toHaveLength(2);

  // The server exits; nobody touches Refresh.
  report([memory('lost')]);
  await expect(panel.locator('[data-connector-id="server:memory"] .connectors-state')).toHaveText('Disconnected');
  await expect(panel.locator('[data-connector-id="server:memory"] .connectors-state')).not.toHaveText('1 tool');
  expect(statusRequests(app)).toHaveLength(3);

  // Another conversation's engine is not this card's business.
  app.notify('agent.event', {
    session: 'another-session',
    event: { event: 'mcp_status', status: { configs: [], servers: [] } },
  });
  await page.waitForTimeout(200);
  expect(statusRequests(app)).toHaveLength(3);
  expect(app.pageErrors).toEqual([]);
});

test('the overview is a rail beside a wide conversation and a panel over a narrow one', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  await page.setViewportSize({ width: 1440, height: 900 });
  await app.install();
  await app.goto();
  await app.openSession();
  await page.locator('#conversation-overview-toggle').click();
  const panel = overview(page);
  await expect(panel).toBeVisible();
  // The browser console runs the conversation on a remote device, named by
  // the roster.
  await expect(panel.getByText('Test Mac', { exact: true })).toBeVisible();

  // The overview never takes the transcript's place: the conversation keeps
  // its row, from the titlebar down to the composer, with its messages.
  const message = page.locator('.transcript .msg-content', { hasText: 'Show the browser fixture' });
  const keepsItsRow = async () => {
    await expect(message).toBeVisible();
    const topbar = await page.locator('.topbar').boundingBox();
    const transcript = await page.locator('.transcript').boundingBox();
    const composer = await page.locator('.composer').first().boundingBox();
    expect(transcript.y).toBeLessThanOrEqual(topbar.y + topbar.height + 1);
    expect(transcript.height).toBeGreaterThan(composer.y - transcript.y - 200);
    return { transcript, composer };
  };

  // With room for both, the conversation's column and the composer end where
  // the rail begins: nothing of the conversation is under it. The transcript
  // scroller itself runs past the rail, so its scrollbar is outside it.
  const rail = await panel.boundingBox();
  const { transcript, composer } = await keepsItsRow();
  const stream = await page.locator('.transcript .stream').boundingBox();
  expect(stream.x + stream.width).toBeLessThanOrEqual(rail.x + 1);
  expect(transcript.x + transcript.width).toBeGreaterThan(rail.x + rail.width);
  expect(composer.x + composer.width).toBeLessThanOrEqual(rail.x + 1);
  // The rail is as tall as its cards: the wheel below it scrolls the
  // transcript. The fixture conversation fits on screen, so it is lengthened
  // for this check.
  const scroller = page.locator('.transcript');
  await scroller.evaluate((el) => {
    el.querySelector('.stream').style.paddingBottom = '2000px';
    el.scrollTop = el.scrollHeight;
  });
  const bottom = await scroller.evaluate((el) => el.scrollTop);
  expect(bottom).toBeGreaterThan(0);
  const below = transcript.y + transcript.height - 30;
  expect(below).toBeGreaterThan(rail.y + rail.height);
  await page.mouse.move(rail.x + rail.width / 2, below);
  await page.mouse.wheel(0, -200);
  await expect.poll(() => scroller.evaluate((el) => el.scrollTop)).toBeLessThan(bottom);
  await scroller.evaluate((el) => { el.scrollTop = 0; });
  await scroller.evaluate((el) => { el.querySelector('.stream').style.paddingBottom = ''; });

  // Cards taller than the pane scroll inside the rail, which stops at the
  // pane's bottom edge and takes the pointer itself, its scrollbar included.
  const first = panel.locator('.conv-overview-card').first();
  await first.evaluate((el) => { el.style.minHeight = '2000px'; });
  const tall = await panel.boundingBox();
  expect(tall.y + tall.height).toBeLessThanOrEqual(900 + 1);
  expect(await panel.evaluate((el) => el.scrollHeight > el.clientHeight)).toBe(true);
  const firstBox = await first.boundingBox();
  const gap = { x: tall.x + tall.width / 2, y: firstBox.y - 4 };
  expect(await panel.evaluate((el, { x, y }) => document.elementFromPoint(x, y) === el, gap)).toBe(true);
  await page.mouse.move(tall.x + tall.width / 2, tall.y + tall.height / 2);
  await page.mouse.wheel(0, 200);
  await expect.poll(() => panel.evaluate((el) => el.scrollTop)).toBeGreaterThan(0);
  await first.evaluate((el) => { el.style.minHeight = ''; });

  // Without room, the same overview covers the transcript's right edge but
  // stops above the composer, which stays usable.
  await page.setViewportSize({ width: 960, height: 900 });
  await expect(panel).toBeVisible();
  await keepsItsRow();
  const over = await panel.boundingBox();
  const narrowTranscript = await page.locator('.transcript').boundingBox();
  const narrowComposer = await page.locator('.composer').first().boundingBox();
  expect(over.x).toBeLessThan(narrowTranscript.x + narrowTranscript.width);
  expect(over.y + over.height).toBeLessThanOrEqual(narrowComposer.y + 1);
  await page.locator('#task').click();
  await expect(page.locator('#task')).toBeFocused();

  // The narrow layout (760px and below, phones included) keeps the overview:
  // it is the only place the connectors are shown. It stays a panel inside
  // the window, the transcript keeps its row, and the titlebar control still
  // hides and shows it.
  for (const width of [760, 390]) {
    await page.setViewportSize({ width, height: 800 });
    await expect(panel).toBeVisible();
    await keepsItsRow();
    const box = await panel.boundingBox();
    expect(box.x).toBeGreaterThanOrEqual(0);
    expect(box.x + box.width).toBeLessThanOrEqual(width);
    await panel.locator('[data-overview-card=connectors]').getByTestId('overview-card-toggle').click();
    await expect(panel.locator('#connectors-refresh')).toBeVisible();
    await panel.locator('[data-overview-card=connectors]').getByTestId('overview-card-toggle').click();
  }
  await page.locator('#conversation-overview-toggle').click();
  await expect(panel).toBeHidden();
  await page.locator('#conversation-overview-toggle').click();
  await expect(panel).toBeVisible();
  expect(app.pageErrors).toEqual([]);
});
