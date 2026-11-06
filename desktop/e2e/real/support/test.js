import { mkdir, mkdtemp, realpath, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { test as base, expect } from '../../tests/support/test.js';
import { AppServer } from './app_server.js';
import { ScriptedModel } from './scripted_model.js';

// One real app-server (and scripted model) per worker; one workspace per test.
export const test = base.extend({
  realServer: [async ({}, use, workerInfo) => {
    const model = new ScriptedModel();
    const modelUrl = await model.listen();
    // Outside the checkout: a workspace inside it would resolve to this
    // repository's project and instructions.
    const home = await realpath(await mkdtemp(path.join(tmpdir(), `seekmoon-e2e-${workerInfo.parallelIndex}-`)));
    const server = new AppServer({ home, modelUrl });
    try {
      await server.start();
    } catch (error) {
      await server.stop();
      throw new Error(`${error.message}\n--- app-server stderr ---\n${server.stderr}`);
    }
    // A fresh home attaches `~/OpenSeek` as its default project; detach it so
    // each test's own project is the only one.
    const { workspaces } = await server.request('workspace.list', {});
    for (const dir of workspaces) await server.request('workspace.remove', { path: dir });
    await mkdir(workerInfo.project.outputDir, { recursive: true });
    await writeFile(path.join(workerInfo.project.outputDir, `timings-${workerInfo.workerIndex}.json`),
      JSON.stringify(server.timings));
    await use({ server, model, home });
    await server.stop();
    await model.close();
    await rm(home, { recursive: true, force: true });
  }, { scope: 'worker', timeout: 60_000 }],

  // On failure, attach what the page reported: a blank page otherwise looks
  // the same whether a script failed to load or the host never answered.
  page: async ({ page }, use, testInfo) => {
    const events = [];
    page.on('pageerror', error => events.push(`pageerror: ${error.message}`));
    page.on('console', message => {
      if (message.type() === 'error') events.push(`console: ${message.text()}`);
    });
    page.on('requestfailed', request =>
      events.push(`requestfailed: ${request.url()} ${request.failure()?.errorText}`));
    await use(page);
    if (testInfo.status !== testInfo.expectedStatus && events.length > 0) {
      await testInfo.attach('page-events', { body: events.join('\n'), contentType: 'text/plain' });
    }
  },

  server: async ({ realServer }, use) => use(realServer.server),

  model: async ({ realServer }, use) => {
    realServer.model.reset();
    await use(realServer.model);
  },

  baseURL: async ({ realServer }, use) => use(realServer.server.origin),

  // A registered project the page can open, removed again afterwards so
  // later tests on this worker start from the same project list.
  workspace: async ({ realServer, server }, use) => {
    const dir = await mkdtemp(path.join(realServer.home, 'project-'));
    await server.request('workspace.add', { path: dir });
    await use(dir);
    await server.request('workspace.remove', { path: dir });
  },
});

export { expect };
