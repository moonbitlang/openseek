import { test, expect } from '@playwright/test';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';

const builtinPath = '/runtime/host-mcp.json';
const userPath = '/home/user/.openseek/mcp.json';

function mcpGroup(page) {
  return page.locator('.settings-group', {
    has: page.getByRole('heading', { name: 'MCP', exact: true }),
  });
}

function statusRequests(app) {
  return app.requests.filter(request => request.method === 'mcp.status');
}

function running(status) {
  return { engine: 'running', status, builtin_config: builtinPath };
}

function loaded(...paths) {
  return paths.map(path => ({ path, state: 'loaded' }));
}

test('Settings shows what the current conversation\'s engine holds of its MCP servers', async ({ page }, testInfo) => {
  const app = new DesktopBrowserHarness(page);
  app.mcpStatus = running({
    configs: loaded(builtinPath, userPath),
    servers: [
      {
        name: 'seekmoon',
        source: builtinPath,
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
        source: userPath,
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
        source: userPath,
        transport: 'http',
        target: 'https://example.com/mcp',
        state: 'failed',
        error: 'JSON-RPC error -32000: MCP endpoint exchange failed',
      },
      {
        name: 'memory',
        source: userPath,
        transport: 'stdio',
        target: 'memory-mcp',
        state: 'lost',
        tools: [{ name: 'mcp__memory__recall', description: 'Recall a note' }],
      },
      { name: 'notes', source: userPath, transport: 'stdio', target: 'notes-mcp', state: 'no_tools' },
    ],
  });
  await app.install();
  await app.goto();
  await app.openSession();
  await page.getByRole('button', { name: 'Settings', exact: true }).click();
  const group = mcpGroup(page);

  // The host's own server is named as built in, not by its file; the user's
  // servers say which file they came from.
  const seekmoon = group.locator('.mcp-server', { hasText: 'seekmoon' });
  await expect(seekmoon.getByText('SeekMoon built-in', { exact: true })).toBeVisible();
  await expect(seekmoon.getByText(builtinPath, { exact: false })).toHaveCount(0);
  await expect(group.getByText('playwright', { exact: true })).toBeVisible();
  await expect(group.getByText('stdio · npx', { exact: true })).toBeVisible();
  await expect(group.getByText(`From ${userPath}`, { exact: true }).first()).toBeVisible();
  await expect(group.getByText('Connected', { exact: true })).toHaveCount(2);
  await expect(group.getByText('Failed', { exact: true })).toBeVisible();
  await expect(group.getByText('JSON-RPC error -32000: MCP endpoint exchange failed')).toBeVisible();
  await expect(group.getByText('Disconnected', { exact: true })).toBeVisible();
  await expect(group.getByText('No tools', { exact: true })).toBeVisible();

  // The tools stay folded until asked for.
  const tool = group.getByText('mcp__playwright__browser_click', { exact: true });
  await expect(tool).toBeHidden();
  await group.getByText('2 tools', { exact: true }).click();
  await expect(tool).toBeVisible();
  await group.screenshot({ path: testInfo.outputPath('mcp-servers.png') });

  // The question names the conversation on screen, whose engine is asked.
  expect(statusRequests(app).map(request => request.params)).toEqual([{ session: 'session-1' }]);
  expect(app.pageErrors).toEqual([]);
});

test('MCP status says when there is no engine to ask, and asks again on reopen and refresh', async ({ page }, testInfo) => {
  const app = new DesktopBrowserHarness(page);
  await app.install();
  await app.goto();
  await app.openSession();
  await page.getByRole('button', { name: 'Settings', exact: true }).click();
  const group = mcpGroup(page);
  await expect(group.getByText('This conversation\'s engine is not running.', { exact: false })).toBeVisible();
  await group.screenshot({ path: testInfo.outputPath('mcp-engine-not-running.png') });
  expect(statusRequests(app)).toHaveLength(1);

  // Asking reads the engine's state and starts nothing, so every visit asks.
  // A file the engine could not load is reported beside the ones it could.
  await page.getByRole('button', { name: 'Skills', exact: true }).click();
  app.mcpStatus = running({
    configs: [
      ...loaded(builtinPath),
      { path: userPath, state: 'failed', error: 'mcp config error: configuration is missing an `mcpServers` object' },
    ],
    servers: [],
  });
  await page.getByRole('button', { name: 'Settings', exact: true }).click();
  await expect(group.getByText(`${userPath} could not be loaded`, { exact: true })).toBeVisible();
  await expect(group.getByText('configuration is missing an `mcpServers` object')).toBeVisible();
  await group.screenshot({ path: testInfo.outputPath('mcp-config-failed.png') });
  expect(statusRequests(app)).toHaveLength(2);

  app.mcpStatus = { engine: 'running', status: { configs: [], servers: [] } };
  await group.getByRole('button', { name: 'Refresh', exact: true }).click();
  await expect(group.getByText('started without an MCP configuration', { exact: false })).toBeVisible();
  expect(statusRequests(app)).toHaveLength(3);

  // A question the host could not answer is reported as that, not as an
  // engine that is not running.
  app.rpcErrors.set('mcp.status', 'the host did not answer');
  await group.getByRole('button', { name: 'Refresh', exact: true }).click();
  await expect(group.getByText('The status could not be read', { exact: true })).toBeVisible();
  await expect(group.getByText('the host did not answer')).toBeVisible();
  expect(app.pageErrors).toEqual([]);
});

test('the MCP panel follows what the engine reports while Settings is open', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  // The engine has started and is still connecting its servers.
  app.mcpStatus = { engine: 'connecting' };
  await app.install();
  await app.goto();
  await app.openSession();
  await page.getByRole('button', { name: 'Settings', exact: true }).click();
  const group = mcpGroup(page);
  await expect(group.getByText('is starting and has not finished connecting', { exact: false })).toBeVisible();
  expect(statusRequests(app)).toHaveLength(1);

  // The engine reports. The host keeps the report and forwards the event;
  // the page reads the kept state again rather than trusting the event.
  const report = servers => {
    const status = { configs: loaded(userPath), servers };
    app.mcpStatus = running(status);
    app.notify('agent.event', { session: 'session-1', event: { event: 'mcp_status', status } });
  };
  const tools = [{ name: 'mcp__memory__recall', description: 'Recall a note' }];
  const memory = state => ({ name: 'memory', source: userPath, transport: 'stdio', target: 'memory-mcp', state, tools });
  report([memory('connected')]);
  await expect(group.getByText('Connected', { exact: true })).toBeVisible();
  expect(statusRequests(app)).toHaveLength(2);

  // The server exits; nobody touches Refresh.
  report([memory('lost')]);
  await expect(group.getByText('Disconnected', { exact: true })).toBeVisible();
  await expect(group.getByText('Connected', { exact: true })).toBeHidden();
  expect(statusRequests(app)).toHaveLength(3);

  // Another conversation's engine is not this panel's business.
  app.notify('agent.event', {
    session: 'another-session',
    event: { event: 'mcp_status', status: { configs: [], servers: [] } },
  });
  await page.getByRole('button', { name: 'Skills', exact: true }).click();
  expect(statusRequests(app)).toHaveLength(3);
  expect(app.pageErrors).toEqual([]);
});
