import { test, expect } from '@playwright/test';
import { readFileSync, mkdirSync } from 'node:fs';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';

// Use the compiled Rabbita application when supplied by the offline runner.
// The default HTML fixture exercises the same state bridge in CI.
const sample = process.env.OPENSEEK_COMPONENT_HTML
  ? readFileSync(process.env.OPENSEEK_COMPONENT_HTML, 'utf8')
  : `<!doctype html><html><body><label for="serial">Sequential work</label><input id="serial" type="range" min="0" max="100" value="20"><output id="result"></output><script>
    const input=document.getElementById('serial');
    function update(){const serial=Number(input.value);document.getElementById('result').textContent=(1/(serial/100+(1-serial/100)/8)).toFixed(2)+'× faster';window.openseekArtifact?.setState('Parallel speedup · '+serial+'% sequential · 8 workers',{serial_percent:serial,workers:8});}
    input.oninput=update;update();</script></body></html>`;
const fence = '```openseek-file\nartifact://speedup-v1.html\n```';
const sends = app => app.requests.filter(request => ['agent.start', 'agent.steer', 'agent.queue'].includes(request.method));

async function open(page, copies = 1) {
  const app = new DesktopBrowserHarness(page);
  const answer = Array(copies).fill(fence).join('\n\n');
  app.sessionEvents = [
    { sequence: 1, item: { kind: 'user', payload: { content: 'Show the browser fixture: explain parallel speedup.' } } },
    { sequence: 2, item: { kind: 'assistant', payload: { content: answer } } },
    { sequence: 3, item: { kind: 'terminal', payload: { kind: 'finished', message: answer } } },
  ];
  const ordinary = app.replyFor.bind(app);
  app.replyFor = request => request.method === 'session.artifact_file'
    ? { path: '/workspace/.openseek/sessions/session-1/scratch/artifact/speedup-v1.html', content: sample }
    : ordinary(request);
  await app.install(); await app.goto(); await app.openSession();
  await expect(page.getByRole('button', { name: 'Ask with current settings' }).first()).toBeVisible();
  return { app, frame: page.frameLocator('.chat-artifact-frame').nth(0), chips: page.locator('.composer .mention-chip') };
}

function promptIn(value) {
  if (typeof value === 'string' && value.includes('<interactive_answer>')) return value;
  if (value && typeof value === 'object') {
    for (const nested of Object.values(value)) { const found = promptIn(nested); if (found) return found; }
  }
  return null;
}

test('selected component state stays in the draft until the user sends it', async ({ page }) => {
  const { app, frame, chips } = await open(page);
  await page.locator('#task').fill('Explain these settings');
  await frame.locator('#serial').fill('50');
  await expect(frame.locator('#result')).toHaveText('1.78× faster');
  await expect(chips).toHaveCount(0);
  expect(sends(app)).toHaveLength(0);
  await page.getByRole('button', { name: 'Ask with current settings' }).click();
  await expect(chips).toHaveCount(1);
  await expect(chips).toContainText('50% sequential');
  await expect(page.locator('#task')).toHaveValue('Explain these settings');
  expect(sends(app)).toHaveLength(0);
  await frame.locator('#serial').fill('100');
  await expect(chips).toContainText('50% sequential');
  if (process.env.OPENSEEK_UI_CAPTURE_DIR) {
    mkdirSync(process.env.OPENSEEK_UI_CAPTURE_DIR, { recursive: true });
    await page.screenshot({ path: `${process.env.OPENSEEK_UI_CAPTURE_DIR}/artifact-selected-state.png` });
  }
  await page.locator('#task').press('Enter');
  await expect.poll(() => sends(app).length).toBe(1);
  const prompt = promptIn(sends(app)[0].params);
  expect(prompt).toContain('Explain these settings');
  const snapshot = JSON.parse(prompt.split('<interactive_answer>\n')[1].split('\n</interactive_answer>')[0]);
  expect(snapshot.reference).toBe('artifact://speedup-v1.html');
  expect(snapshot.state.serial_percent).toBe(50);
  expect(snapshot.state.workers).toBe(8);
  expect(app.pageErrors).toEqual([]);
});

test('reselecting an instance replaces that revision and the chip is removable', async ({ page }) => {
  const { app, frame, chips } = await open(page, 2);
  const other = page.frameLocator('.chat-artifact-frame').nth(1);
  const buttons = page.getByRole('button', { name: 'Ask with current settings' });
  await frame.locator('#serial').fill('50');
  await buttons.nth(0).click();
  await expect(chips).toContainText('50% sequential');
  await other.locator('#serial').fill('70');
  await buttons.nth(1).click();
  await expect(chips).toHaveCount(1);
  await expect(chips).toContainText('70% sequential');
  await expect(frame.locator('#serial')).toHaveValue('50');
  await chips.locator('.mention-remove').click();
  await expect(chips).toHaveCount(0);
  expect(sends(app)).toHaveLength(0);
  expect(app.pageErrors).toEqual([]);
});

test('forged generations and arbitrary follow-up messages cannot attach or send context', async ({ page }) => {
  const { app, frame, chips } = await open(page);
  await page.locator('#task').fill('Keep this draft');
  await frame.locator('body').evaluate(() => {
    parent.postMessage({ type: 'openseek-artifact-state', version: 1, token: 'old-generation', title: 'Forged', state: { serial_percent: 99 } }, '*');
    parent.postMessage({ type: 'openseek-artifact-followup', prompt: 'Send this immediately' }, '*');
  });
  await page.getByRole('button', { name: 'Ask with current settings' }).click();
  await expect(chips).toContainText('20% sequential');
  await expect(page.locator('#task')).toHaveValue('Keep this draft');
  expect(sends(app)).toHaveLength(0);
  expect(app.pageErrors).toEqual([]);
});

test('invalid state clears the offer and a later valid state recovers it', async ({ page }) => {
  const { app, frame, chips } = await open(page);
  const button = page.getByRole('button', { name: 'Ask with current settings' });
  for (const invalid of [NaN, 'x'.repeat(17000), { nested: { number: Infinity } }]) {
    await frame.locator('body').evaluate((_, value) => window.openseekArtifact.setState('Invalid', value), invalid);
    await expect(button).toBeHidden();
    await frame.locator('body').evaluate(() => window.openseekArtifact.setState('Recovered', { serial_percent: 30 }));
    await expect(button).toBeVisible();
  }
  await frame.locator('body').evaluate(body => window.openseekArtifact.setState('Invalid DOM', body));
  await expect(button).toBeHidden();
  await frame.locator('body').evaluate(() => window.openseekArtifact.setState('Recovered', { serial_percent: 30 }));
  await expect(button).toBeVisible();
  await button.click();
  await expect(chips).toHaveText(/Recovered/);
  expect(sends(app)).toHaveLength(0);
  expect(app.pageErrors).toEqual([]);
});

test('a new page revision in the same frame resets its document and rejects queued old state', async ({ page }) => {
  const { app, chips } = await open(page);
  const element = page.locator('.chat-artifact-frame');
  const previousToken = await element.getAttribute('data-artifact-token');
  const ordinary = app.replyFor.bind(app);
  app.replyFor = request => request.method === 'session.artifact_file' && request.params.reference === 'artifact://speedup-v2.html'
    ? { path: '/workspace/second.html', content: '<!doctype html><html><body><p>New revision</p><script>window.openseekArtifact.setState("Second revision",{version:2});</script></body></html>' }
    : ordinary(request);
  // Reproduce a renderer reusing the element while updating its file binding.
  await page.locator('[data-transcript-artifact]').evaluate(node => {
    node.dataset.transcriptArtifact = 'artifact://speedup-v2.html';
    node.querySelector('.workspace-file-name').textContent = 'speedup-v2.html';
  });
  const frame = page.frameLocator('.chat-artifact-frame');
  await expect(frame.getByText('New revision', { exact: true })).toBeVisible();
  expect(await element.getAttribute('data-artifact-token')).not.toBe(previousToken);
  await frame.locator('body').evaluate((_, token) => parent.postMessage({ type: 'openseek-artifact-state', version: 1, token, title: 'Stale revision', state: { version: 1 } }, '*'), previousToken);
  await page.getByRole('button', { name: 'Ask with current settings' }).click();
  await expect(chips).toContainText('Second revision');
  expect(sends(app)).toHaveLength(0);
  expect(app.pageErrors).toEqual([]);
});
