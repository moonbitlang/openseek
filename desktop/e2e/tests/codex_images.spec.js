import { test, expect } from '@playwright/test';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';

const png = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aCfoAAAAASUVORK5CYII=';
const image = { name: 'screen.png', mimeType: 'image/png', buffer: Buffer.from(png, 'base64') };

class CodexImagesHarness extends DesktopBrowserHarness {
  constructor(page) {
    super(page);
    this.codexModels = [{ id: 'gpt-test', displayName: 'Codex images', isDefault: true }];
    this.items = [];
  }

  replyFor(request) {
    if (request.method === 'codex.turn.start') {
      this.items = [{ id: 'image-user', type: 'userMessage', content: request.params.input }];
      return { turn: { id: 'image-turn', status: 'inProgress', items: this.items } };
    }
    if (request.method === 'codex.turn.steer') return { turnId: 'image-turn' };
    return super.replyFor(request);
  }

  async openCodex() {
    await this.install();
    await this.goto();
    await this.page.getByRole('button', { name: 'Model', exact: true }).click();
    await this.page.getByRole('option', { name: 'Codex images', exact: true }).click();
    await expect(this.page.getByRole('button', { name: 'Attach images', exact: true })).toBeVisible();
  }

  async select(files) {
    const chooser = this.page.waitForEvent('filechooser');
    await this.page.getByRole('button', { name: 'Attach images', exact: true }).click();
    await (await chooser).setFiles(files);
  }

  // Dispatch real browser File/DataTransfer events against the production FFI.
  async transfer(kind, { name = 'pasted.png', type = 'image/png', content = png } = {}) {
    return this.page.locator('#task').evaluate((target, { kind, name, type, content }) => {
      const bytes = Uint8Array.from(atob(content), c => c.charCodeAt(0));
      const transfer = new DataTransfer();
      transfer.items.add(new File([bytes], name, { type }));
      const event = kind === 'paste'
        ? new ClipboardEvent('paste', { clipboardData: transfer, bubbles: true, cancelable: true })
        : new DragEvent('drop', { dataTransfer: transfer, bubbles: true, cancelable: true });
      target.dispatchEvent(event);
      return event.defaultPrevented;
    }, { kind, name, type, content });
  }
}

test('selected image-only input reaches Codex and remains visible in history', async ({ page }, testInfo) => {
  const app = new CodexImagesHarness(page);
  await app.openCodex();
  await app.select(image);
  await expect(page.locator('.composer-image img')).toHaveAttribute('src', `data:image/png;base64,${png}`);
  await expect(page.locator('#send')).toBeEnabled();
  await page.locator('#send').click();
  await expect.poll(() => app.requests.filter(r => r.method === 'codex.turn.start').length).toBe(1);
  expect(app.requests.find(r => r.method === 'codex.turn.start').params.input).toEqual([
    { type: 'image', url: `data:image/png;base64,${png}` },
  ]);
  await expect(page.locator('.composer-image')).toHaveCount(0);
  await expect(page.locator('.user-image')).toHaveAttribute('src', `data:image/png;base64,${png}`);
  await expect.poll(() => page.locator('.user-image').evaluate(img => img.naturalWidth)).toBe(1);
  await page.screenshot({ path: testInfo.outputPath('codex-image-sent.png') });
  expect(app.pageErrors).toEqual([]);
});

test('paste and drop preserve image bytes, allow removal and steer a running task', async ({ page }) => {
  const app = new CodexImagesHarness(page);
  await app.openCodex();
  expect(await app.transfer('paste')).toBe(true);
  expect(await app.transfer('drop', { name: 'dropped.png' })).toBe(true);
  await expect(page.locator('.composer-image')).toHaveCount(2);
  await page.getByRole('button', { name: 'Remove pasted.png', exact: true }).click();
  await expect(page.locator('.composer-image')).toHaveCount(1);
  await page.locator('#task').fill('Inspect the screenshot');
  await page.locator('#send').click();
  await expect(page.locator('.user-image')).toHaveCount(1);
  expect(app.requests.find(r => r.method === 'codex.turn.start').params.input).toEqual([
    { type: 'text', text: 'Inspect the screenshot' },
    { type: 'image', url: `data:image/png;base64,${png}` },
  ]);
  expect(await app.transfer('paste')).toBe(true);
  await expect(page.locator('.composer-image')).toHaveCount(1);
  await page.locator('#send').click();
  await expect.poll(() => app.requests.filter(r => r.method === 'codex.turn.steer').length).toBe(1);
  const steer = app.requests.find(r => r.method === 'codex.turn.steer').params;
  expect(steer.input).toEqual([{ type: 'image', url: `data:image/png;base64,${png}` }]);
  expect(steer.expectedTurnId).toBe('image-turn');
  await expect(page.locator('.composer-image')).toHaveCount(0);
  expect(app.pageErrors).toEqual([]);
});

test('failed sends preserve attachments and invalid selections preserve the prior draft', async ({ page }) => {
  const app = new CodexImagesHarness(page);
  app.rpcErrors.set('codex.turn.start', 'Image send failed');
  await app.openCodex();
  await app.select(image);
  await expect(page.locator('.composer-image')).toHaveCount(1);
  expect(await app.transfer('drop', { name: 'note.txt', type: 'text/plain' })).toBe(true);
  await expect(page.getByRole('alert')).toContainText('Choose PNG, JPEG, WebP or GIF');
  await expect(page.locator('.composer-image')).toHaveCount(1);
  await app.select({ name: 'large.png', mimeType: 'image/png', buffer: Buffer.alloc(5 * 1024 * 1024 + 1) });
  await expect(page.getByRole('alert')).toContainText('5 MiB');
  await page.locator('#send').click();
  await expect(page.getByText('Image send failed', { exact: false }).first()).toBeVisible();
  await expect(page.locator('.composer-image')).toHaveCount(1);
  await expect(page.locator('#send')).toBeEnabled();
  expect(app.pageErrors).toEqual([]);
});

test('slow file reads disable send and report read errors without losing text', async ({ page }) => {
  const app = new CodexImagesHarness(page);
  await app.openCodex();
  await page.locator('#task').fill('Keep this text');
  await page.evaluate(() => {
    File.prototype.arrayBuffer = () => new Promise((_, reject) => { window.rejectImageRead = reject; });
  });
  await app.select(image);
  await expect(page.getByText('Reading images…')).toBeVisible();
  await expect(page.locator('#send')).toBeDisabled();
  await page.locator('#task').press('Enter');
  expect(app.requests.some(r => r.method === 'codex.turn.start')).toBe(false);
  await page.evaluate(() => window.rejectImageRead(new Error('test read failure')));
  await expect(page.getByRole('alert')).toContainText('Could not read images');
  await expect(page.locator('#task')).toHaveValue('Keep this text');
  await expect(page.locator('#send')).toBeEnabled();
  expect(app.pageErrors).toEqual([]);
});

test('Codex remote image URLs retain their position between text parts', async ({ page }) => {
  const remoteUrl = 'https://images.example.test/picture.png';
  await page.route(remoteUrl, route => route.fulfill({ contentType: 'image/png', body: image.buffer }));
  const app = new CodexImagesHarness(page);
  const replyFor = app.replyFor.bind(app);
  app.replyFor = request => request.method === 'codex.turn.start'
    ? { turn: { id: 'remote-image-turn', status: 'completed', items: [{
      id: 'remote-image-user', type: 'userMessage', content: [
        { type: 'text', text: 'Before remote picture' },
        { type: 'image', url: remoteUrl },
        { type: 'text', text: 'After remote picture' },
      ],
    }] } }
    : replyFor(request);
  await app.openCodex();
  await page.locator('#task').fill('Before remote picture');
  await page.locator('#send').click();
  const user = page.locator('.user-bubble').last();
  await expect(user.locator('.user-image')).toHaveAttribute('src', remoteUrl);
  await expect.poll(() => user.locator('.user-image').evaluate(img => img.naturalWidth)).toBe(1);
  expect(await user.locator('.msg-content, .user-images').evaluateAll(nodes =>
    nodes.map(node => node.querySelector('img') ? 'image' : node.textContent),
  )).toEqual(['Before remote picture', 'image', 'After remote picture']);
  expect(app.pageErrors).toEqual([]);
});

test('canceling the file picker removes its input and permits another selection', async ({ page }) => {
  const app = new CodexImagesHarness(page);
  await app.openCodex();
  const chooser = page.waitForEvent('filechooser');
  await page.getByRole('button', { name: 'Attach images', exact: true }).click();
  const input = (await chooser).element();
  await input.evaluate(element => element.dispatchEvent(new Event('cancel')));
  await expect(page.locator('input[type="file"]')).toHaveCount(0);
  await expect(page.locator('.composer-image')).toHaveCount(0);
  await app.select(image);
  await expect(page.locator('.composer-image')).toHaveCount(1);
  await expect(page.locator('input[type="file"]')).toHaveCount(0);
  expect(app.pageErrors).toEqual([]);
});
