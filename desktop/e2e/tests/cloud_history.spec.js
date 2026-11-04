import { test, expect } from '@playwright/test';
import { readFileSync } from 'node:fs';
import { CloudHarness, authOrigin, sessionA } from './support/cloud_harness.js';

const png = readFileSync(new URL('../../../deepseek/client/testdata/two-colors.png', import.meta.url)).toString('base64');
const image = { type: 'image', media_type: 'image/png', data: png };
const sessionURL = `${authOrigin}/cloud/session/${sessionA}`;
const user = (task, content, created_at) => ({ task_id: task, kind: 'user', data: { content }, created_at });

test('Cloud history recalls text from image messages in order and skips image-only or empty prompts', async ({ page }) => {
  const cloud = new CloudHarness(page);
  cloud.histories.set(sessionA, {
    messages: [
      user('plain', 'An older plain question', 1000),
      user('mixed', [{ type: 'text', text: 'Review ' }, image, { type: 'text', text: 'the attached image' }], 1001),
      user('image-only', [image], 1002),
      user('empty', '  ', 1003),
    ],
    generating: false,
  });
  await cloud.install();
  await page.goto(sessionURL);
  const task = page.locator('#task');
  const caption = page.locator('.composer-mode-chip');

  for (const reload of [false, true]) {
    if (reload) await page.reload();
    await expect(task).toBeEnabled();
    await task.press('ArrowUp');
    await expect(task).toHaveValue('Review the attached image');
    await expect(caption).toHaveText('History 2/2');
    await expect(page.locator('.composer-image')).toHaveCount(0);
    await task.press('Home');
    await task.press('ArrowUp');
    await expect(task).toHaveValue('An older plain question');
    await expect(caption).toHaveText('History 1/2');
    await task.press('End');
    await task.press('ArrowDown');
    await expect(task).toHaveValue('Review the attached image');
    await task.press('End');
    await task.press('ArrowDown');
    await expect(task).toHaveValue('');
    await expect(caption).toHaveCount(0);
  }

  await task.fill('Keep my unsent draft');
  await task.press('Home');
  await task.press('ArrowUp');
  await expect(task).toHaveValue('Keep my unsent draft');
  expect(cloud.device.ticketRequests).toHaveLength(0);
  expect(cloud.device.pageErrors).toEqual([]);
});

test('Cloud rich-message history restores file mention chips without exposing the wire envelope or old image', async ({ page }) => {
  const cloud = new CloudHarness(page);
  const prompt = 'Update the heading\n\n<user_mentions>\n<file path="src/index.html"/>\n</user_mentions>';
  cloud.histories.set(sessionA, {
    messages: [user('with-file-and-image', [{ type: 'text', text: prompt }, image], 1000)],
    generating: false,
  });
  await cloud.install();
  await page.goto(sessionURL);
  const task = page.locator('#task');
  await expect(task).toBeEnabled();
  await task.press('ArrowUp');
  await expect(task).toHaveValue('Update the heading');
  await expect(page.locator('.composer .mention-chip')).toContainText('index.html');
  await expect(page.locator('.composer-image')).toHaveCount(0);
  await expect(page.locator('.composer-mode-chip')).toHaveText('History 1/1');
  await task.press('End');
  await task.press('ArrowDown');
  await expect(task).toHaveValue('');
  await expect(page.locator('.composer .mention-chip')).toHaveCount(0);
  expect(cloud.device.ticketRequests).toHaveLength(0);
  expect(cloud.device.pageErrors).toEqual([]);
});
