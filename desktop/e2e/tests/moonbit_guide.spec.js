import { test, expect } from '@playwright/test';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';

class GuideHarness extends DesktopBrowserHarness {
  constructor(page) {
    super(page);
    this.guides = new Map([['session-1', true]]);
  }

  replyFor(request) {
    if (request.method === 'agent.start') {
      this.guides.set(request.params.session, request.params.moonbit_guide);
      if (!this.liveSessions.some(session => session.id === request.params.session)) {
        this.liveSessions.push({ id: request.params.session, title: 'Guide choice fixture', updated_at_ms: 2 });
      }
    }
    const reply = super.replyFor(request);
    if (request.method === 'session.load') {
      return { ...reply, session: { ...reply.session, id: request.params.session, moonbit_guide: this.guides.get(request.params.session) } };
    }
    return reply;
  }
}

async function settings(page) {
  await page.getByRole('button', { name: 'Settings', exact: true }).click();
  await expect(page.getByRole('heading', { name: 'Settings', exact: true })).toBeVisible();
  return page.getByRole('switch', { name: 'MoonBit guide', exact: true });
}

async function chooseDefault(page, enabled) {
  const control = await settings(page);
  if (await control.getAttribute('aria-checked') !== String(enabled)) await control.click();
  await expect(control).toHaveAttribute('aria-checked', String(enabled));
}

async function newChat(page) {
  await page.locator('.workspace-row').hover();
  await page.getByRole('button', { name: 'New conversation in this project', exact: true }).click();
  await expect(page.locator('#task')).toBeVisible();
}

async function send(page, app, text) {
  const previous = app.requests.filter(request => request.method === 'agent.start').length;
  await page.locator('#task').fill(text);
  await page.locator('#send').click();
  await expect.poll(() => app.requests.filter(request => request.method === 'agent.start').length).toBe(previous + 1);
  return app.requests.filter(request => request.method === 'agent.start').at(-1).params;
}

test('Settings default persists, applies to new chats and preserves saved sessions', async ({ page }, testInfo) => {
  const app = new GuideHarness(page);
  await app.install();
  await app.goto();
  await app.openSession();
  const control = await settings(page);
  await expect(control).toHaveAttribute('aria-checked', 'true');
  await chooseDefault(page, false);
  await expect.poll(() => page.evaluate(() => localStorage.getItem('openseek.moonbit_guide'))).toBe('false');
  await page.screenshot({ animations: 'disabled', path: testInfo.outputPath('guide-settings-off.png') });
  await app.openSession();
  expect((await send(page, app, 'Continue the saved session')).moonbit_guide).toBe(true);
  await newChat(page);
  expect((await send(page, app, 'Create without the guide')).moonbit_guide).toBe(false);
  const saved = new URL(page.url()).pathname;
  await chooseDefault(page, true);
  await page.goto(saved);
  await expect(page.locator('#task')).toBeVisible();
  expect((await send(page, app, 'Continue without the guide')).moonbit_guide).toBe(false);
  await chooseDefault(page, false);
  await page.reload();
  await expect(page.getByRole('switch', { name: 'MoonBit guide', exact: true })).toHaveAttribute('aria-checked', 'false');
  await newChat(page);
  expect((await send(page, app, 'Use the restored default')).moonbit_guide).toBe(false);
  expect(app.pageErrors).toEqual([]);
});

test('changing the default preserves an existing unsent draft', async ({ page }) => {
  const app = new GuideHarness(page);
  await app.install();
  await app.goto();
  await page.locator('#task').fill('Keep this draft');
  const draft = new URL(page.url()).pathname;
  await chooseDefault(page, false);
  await page.getByRole('button', { name: 'Back', exact: true }).click();
  await expect.poll(() => new URL(page.url()).pathname).toBe(draft);
  await expect(page.locator('#task')).toBeVisible();
  expect((await send(page, app, 'Send the existing draft')).moonbit_guide).toBe(true);
  expect(app.pageErrors).toEqual([]);
});

test('MoonBit default remains usable in narrow dark Settings', async ({ page }, testInfo) => {
  const app = new DesktopBrowserHarness(page);
  await app.install();
  await app.goto();
  await settings(page);
  await page.setViewportSize({ width: 390, height: 844 });
  await page.emulateMedia({ colorScheme: 'dark' });
  await expect.poll(() => page.locator('.app > aside').evaluate(el => el.getBoundingClientRect().right)).toBeLessThanOrEqual(0);
  const control = page.getByRole('switch', { name: 'MoonBit guide', exact: true });
  await control.focus();
  await page.keyboard.press('Space');
  await expect(control).toHaveAttribute('aria-checked', 'false');
  const bounds = await control.boundingBox();
  expect(bounds.x).toBeGreaterThanOrEqual(0);
  expect(bounds.x + bounds.width).toBeLessThanOrEqual(390);
  await page.screenshot({ animations: 'disabled', path: testInfo.outputPath('guide-settings-narrow-dark.png') });
  expect(app.pageErrors).toEqual([]);
});
