import { test, expect } from './support/test.js';
import { CloudHarness, sessionA } from './support/cloud_harness.js';

function commands(app) {
  return app.requests.filter(request => request.method === 'POST' && request.path.endsWith('/commands'))
    .map(request => JSON.parse(request.body).command.command);
}

// A Cloud prompt is admitted only when its run starts, so the composer shows
// Send until `task_started` and then switches to the run's Stop and follow-up
// controls. A click aimed at Send while that switch lands must never cancel
// the run that has just started.
test('Cloud Send pressed as a run starts follows up instead of stopping it', async ({ page }) => {
  const app = new CloudHarness(page);
  app.manualTasks = true;
  let admit;
  app.pauseSend = new Promise(resolve => { admit = resolve; });
  await app.install();
  await app.goto();
  await app.open();
  await page.locator('#task').fill('Start a Cloud turn');
  await page.locator('#send').click();
  await expect.poll(() => app.postCount).toBe(1);
  await page.locator('#task').fill('Follow up as soon as it starts');
  const send = page.locator('#send');
  await expect(send).toHaveAttribute('title', 'Send');
  await expect(send).toBeDisabled();
  await expect(page.locator('#stop')).toHaveCount(0);
  // Resolve the button before the run starts. Playwright then waits for that
  // element to become enabled, as a pointer press would land on it.
  const pressed = await send.elementHandle();
  let acknowledge;
  app.pauseControl = new Promise(resolve => { acknowledge = resolve; });
  const click = pressed.click();
  admit();
  await click;
  await expect.poll(() => commands(app)).toEqual(['prompt', 'steer']);
  await expect(page.locator('.pending-steer-row')).toContainText('Follow up as soon as it starts');
  await expect(page.locator('#stop')).toBeEnabled();
  // Until the steer is acknowledged the run takes no further follow-up, yet
  // the submit action keeps Send's place at the end instead of leaving it to
  // Stop.
  await page.locator('#task').fill('Another follow-up');
  const buttons = page.locator('.composer-actions > button');
  await expect(buttons).toHaveCount(2);
  await expect(buttons.first()).toHaveId('stop');
  await expect(buttons.last()).toHaveId('send');
  await expect(buttons.last()).toBeDisabled();
  acknowledge();
  await expect(buttons.last()).toBeEnabled();
  expect(commands(app)).toEqual(['prompt', 'steer']);
  expect(app.controlState(sessionA).data.status).toBe('running');
  expect(app.device.pageErrors).toEqual([]);
});
