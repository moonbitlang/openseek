import { test, expect } from './support/test.js';
import { CloudHarness, sessionA, sessionB } from './support/cloud_harness.js';

test('Desktop Cloud sends the picked browser element with its draft and discards a pick after switching chats', async ({ page }) => {
  const cloud = new CloudHarness(page, { desktop: true });
  const element = {
    url: 'https://example.test/shop', title: 'Shop', tag: 'button',
    selector: '#buy', text: 'Buy', html: '<button id="buy">Buy</button>',
  };
  let finishPick;
  cloud.device.onRpc(/^browser\./, request => {
    if (request.method === 'browser.pick_element') {
      return new Promise(resolve => { finishPick = () => resolve({ kind: 'selected', element }); });
    }
    return {};
  });
  await cloud.install();
  await cloud.goto();
  await cloud.open(sessionA);
  await page.getByRole('button', { name: 'Show panel', exact: true }).click();
  await page.locator('.dock-launcher').getByRole('button', { name: /^Browse / }).click();
  const address = page.locator('.browser-address');
  await address.fill(element.url);
  await address.press('Enter');

  const task = page.locator('#task');
  const pick = page.getByRole('button', { name: 'Enter annotation mode', exact: true });
  const chip = page.locator('.composer .mention-chip');
  await task.fill('Change this button');
  await pick.click();
  await expect.poll(() => Boolean(finishPick)).toBe(true);
  await cloud.open(sessionB);
  await expect.poll(() => cloud.hostRequests.some(r => r.method === 'browser.cancel_pick')).toBe(true);
  finishPick();
  finishPick = undefined;
  await expect(chip).toHaveCount(0);
  await cloud.open(sessionA);
  await expect(chip).toHaveCount(0);
  await pick.click();
  await expect.poll(() => Boolean(finishPick)).toBe(true);
  finishPick();
  await expect(chip).toContainText('<button id="buy">');
  await expect(task).toHaveValue('Change this button');
  await expect(task).toBeFocused();
  await page.getByRole('button', { name: 'Send', exact: true }).click();
  await expect.poll(() => cloud.postCount).toBe(1);
  const send = cloud.requests.find(r => r.method === 'POST' && r.path.endsWith('/commands'));
  expect(send.path).toContain(sessionA);
  const content = JSON.parse(send.body).command.content;
  expect(content).toContain('Change this button');
  const envelope = content.match(/<browser_annotation>\n(.+)\n<\/browser_annotation>/);
  expect(envelope).toBeTruthy();
  expect(JSON.parse(envelope[1])).toEqual({ element });
});
