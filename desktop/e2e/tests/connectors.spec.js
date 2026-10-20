import { test, expect } from '@playwright/test';
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

async function openConnectors(page) {
  await page.locator('.run-status-button').click();
  const panel = page.locator('.connectors-menu');
  await expect(panel).toBeVisible();
  return panel;
}

test('the run status opens what the conversation\'s engine is connected to', async ({ page }, testInfo) => {
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
  const panel = await openConnectors(page);

  await expect(panel.getByText('Connectors', { exact: true })).toBeVisible();
  const seekmoon = panel.locator('.connectors-row', { hasText: 'seekmoon' });
  await expect(seekmoon.getByText('3 tools', { exact: true })).toBeVisible();
  // How a server is reached and its tools are on hover.
  await expect(seekmoon).toHaveAttribute('title', /http · http:\/\/127\.0\.0\.1:4321\/mcp/);
  const playwright = panel.locator('.connectors-row', { hasText: 'playwright' });
  await expect(playwright).toHaveAttribute('title', /mcp__playwright__browser_click — Perform click on a web page/);
  const docs = panel.locator('.connectors-row', { hasText: 'docs' });
  await expect(docs.getByText('Failed', { exact: true })).toBeVisible();
  await expect(docs.getByText('JSON-RPC error -32000: MCP endpoint exchange failed')).toBeVisible();
  await expect(panel.getByText('Disconnected', { exact: true })).toBeVisible();
  await expect(panel.getByText('No tools', { exact: true })).toBeVisible();
  await page.screenshot({ path: testInfo.outputPath('connectors.png') });

  // The question names the conversation on screen, whose engine is asked.
  expect(statusRequests(app).map(request => request.params)).toEqual([{ session: 'session-1' }]);

  // A click elsewhere closes it; a click inside does not.
  await panel.locator('.connectors-row', { hasText: 'notes' }).click();
  await expect(panel).toBeVisible();
  await page.locator('.transcript').click();
  await expect(panel).toBeHidden();
  expect(app.pageErrors).toEqual([]);
});

test('the connectors panel says when there is no engine, and asks again on reopen and refresh', async ({ page }, testInfo) => {
  const app = new DesktopBrowserHarness(page);
  await app.install();
  await app.goto();
  await app.openSession();
  let panel = await openConnectors(page);
  await expect(panel.getByText('Not running. Servers connect with the next message.', { exact: true })).toBeVisible();
  await page.screenshot({ path: testInfo.outputPath('connectors-stopped.png') });
  expect(statusRequests(app)).toHaveLength(1);

  // Asking reads the engine's state and starts nothing, so every opening
  // asks. A file the engine could not load is listed by its full path.
  await page.locator('.run-status-button').click();
  await expect(panel).toBeHidden();
  app.mcpStatus = running({
    configs: [
      ...loaded(hostPath),
      { path: userPath, state: 'failed', error: 'mcp config error: configuration is missing an `mcpServers` object' },
    ],
    servers: [],
  });
  panel = await openConnectors(page);
  const config = panel.locator('.connectors-row', { hasText: userPath });
  await expect(config.locator('.connectors-name')).toHaveText(userPath);
  await expect(config.getByText('configuration is missing an `mcpServers` object', { exact: false })).toBeVisible();
  await expect(config).toHaveAttribute('title', new RegExp(userPath.replaceAll('.', '\\.')));
  await page.screenshot({ path: testInfo.outputPath('connectors-config-failed.png') });
  expect(statusRequests(app)).toHaveLength(2);

  app.mcpStatus = running({ configs: [], servers: [] });
  await panel.getByRole('button', { name: 'Refresh', exact: true }).click();
  await expect(panel.getByText('No MCP servers configured.', { exact: true })).toBeVisible();
  expect(statusRequests(app)).toHaveLength(3);

  // A question the host could not answer is reported as that, not as an
  // engine that is not running.
  app.rpcErrors.set('mcp.status', 'the host did not answer');
  await panel.getByRole('button', { name: 'Refresh', exact: true }).click();
  await expect(panel.getByText('The status could not be read', { exact: true })).toBeVisible();
  await expect(panel.getByText('the host did not answer')).toBeVisible();
  expect(app.pageErrors).toEqual([]);
});

test('the connectors panel follows what the engine reports while it is open', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  // The engine has started and is still connecting its servers.
  app.mcpStatus = { engine: 'connecting' };
  await app.install();
  await app.goto();
  await app.openSession();
  const panel = await openConnectors(page);
  await expect(panel.getByText('Connecting…', { exact: true })).toBeVisible();
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
  await expect(panel.getByText('1 tool', { exact: true })).toBeVisible();
  expect(statusRequests(app)).toHaveLength(2);

  // The server exits; nobody touches Refresh.
  report([memory('lost')]);
  await expect(panel.getByText('Disconnected', { exact: true })).toBeVisible();
  await expect(panel.getByText('1 tool', { exact: true })).toBeHidden();
  expect(statusRequests(app)).toHaveLength(3);

  // Another conversation's engine is not this panel's business.
  app.notify('agent.event', {
    session: 'another-session',
    event: { event: 'mcp_status', status: { configs: [], servers: [] } },
  });
  await page.waitForTimeout(200);
  expect(statusRequests(app)).toHaveLength(3);
  expect(app.pageErrors).toEqual([]);
});
