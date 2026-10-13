import { test, expect } from '@playwright/test';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';

const configPath = '/home/user/.openseek/mcp.json';

function mcpGroup(page) {
  return page.locator('.settings-group', {
    has: page.getByRole('heading', { name: 'MCP', exact: true }),
  });
}

function statusRequests(app) {
  return app.requests.filter(request => request.method === 'mcp.status');
}

function running(status) {
  return { config_path: configPath, engine: 'running', status };
}

test('Settings shows what the current conversation\'s engine holds of its MCP servers', async ({ page }, testInfo) => {
  const app = new DesktopBrowserHarness(page);
  app.mcpStatus = running({
    config: 'loaded',
    path: configPath,
    servers: [
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
  await page.getByRole('button', { name: 'Settings', exact: true }).click();
  const group = mcpGroup(page);

  await expect(group.getByText('playwright', { exact: true })).toBeVisible();
  await expect(group.getByText('stdio · npx', { exact: true })).toBeVisible();
  await expect(group.getByText('Connected', { exact: true })).toBeVisible();
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
  await expect(group.getByText(configPath, { exact: false })).toBeVisible();
  await group.screenshot({ path: testInfo.outputPath('mcp-engine-not-running.png') });
  expect(statusRequests(app)).toHaveLength(1);

  // Asking reads the engine's state and starts nothing, so every visit asks.
  await page.getByRole('button', { name: 'Skills', exact: true }).click();
  app.mcpStatus = running({
    config: 'failed',
    path: configPath,
    error: 'mcp config error: configuration is missing an `mcpServers` object',
  });
  await page.getByRole('button', { name: 'Settings', exact: true }).click();
  await expect(group.getByText(`${configPath} could not be loaded`, { exact: true })).toBeVisible();
  await expect(group.getByText('configuration is missing an `mcpServers` object')).toBeVisible();
  expect(statusRequests(app)).toHaveLength(2);

  app.mcpStatus = running({ config: 'none' });
  await group.getByRole('button', { name: 'Refresh', exact: true }).click();
  await expect(group.getByText('started without an MCP configuration', { exact: false })).toBeVisible();
  expect(statusRequests(app)).toHaveLength(3);

  // A question the host could not answer is reported as that, not as an
  // engine that is not running.
  app.rpcErrors.set('mcp.status', 'there is no home directory to look for the MCP configuration in');
  await group.getByRole('button', { name: 'Refresh', exact: true }).click();
  await expect(group.getByText('The status could not be read', { exact: true })).toBeVisible();
  await expect(group.getByText('there is no home directory to look for the MCP configuration in')).toBeVisible();
  expect(app.pageErrors).toEqual([]);
});

test('the MCP panel follows what the engine reports while Settings is open', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  // The engine has started and is still connecting its servers.
  app.mcpStatus = { config_path: configPath, engine: 'connecting' };
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
    const status = { config: 'loaded', path: configPath, servers };
    app.mcpStatus = running(status);
    app.notify('agent.event', { session: 'session-1', event: { event: 'mcp_status', status } });
  };
  const tools = [{ name: 'mcp__memory__recall', description: 'Recall a note' }];
  report([{ name: 'memory', transport: 'stdio', target: 'memory-mcp', state: 'connected', tools }]);
  await expect(group.getByText('Connected', { exact: true })).toBeVisible();
  expect(statusRequests(app)).toHaveLength(2);

  // The server exits; nobody touches Refresh.
  report([{ name: 'memory', transport: 'stdio', target: 'memory-mcp', state: 'lost', tools }]);
  await expect(group.getByText('Disconnected', { exact: true })).toBeVisible();
  await expect(group.getByText('Connected', { exact: true })).toBeHidden();
  expect(statusRequests(app)).toHaveLength(3);

  // Another conversation's engine is not this panel's business.
  app.notify('agent.event', { session: 'another-session', event: { event: 'mcp_status', status: { config: 'none' } } });
  await page.getByRole('button', { name: 'Skills', exact: true }).click();
  expect(statusRequests(app)).toHaveLength(3);
  expect(app.pageErrors).toEqual([]);
});
