import { test, expect } from '@playwright/test';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';

const market = {
  name: 'wayfinder', module_name: 'Yoorkin/wayfinder', package_path: '',
  version: '0.1.0', description: 'Plan uncertain work.', author: 'Yoorkin', repository: '',
};
const installed = {
  id: 'yoorkin-wayfinder', name: 'wayfinder', description: market.description,
  source: 'Yoorkin/wayfinder@0.1.0',
};

class SkillsHarness extends DesktopBrowserHarness {
  constructor(page, alreadyInstalled = false) {
    super(page);
    this.installedSkills = alreadyInstalled ? [structuredClone(installed)] : [];
    this.catalogSkills = [structuredClone(market)];
  }

  replyFor(request) {
    switch (request.method) {
      case 'skills.catalog': return { skills: this.catalogSkills };
      case 'skills.content':
      case 'skills.installed_content':
        return { kind: 'content', content: '# Wayfinder\n\nPlan uncertain work.', absolute: '', sig: '' };
      case 'skills.install':
        this.installedSkills = [structuredClone(installed)];
        return { installed };
      case 'skills.uninstall':
        if (request.params.id !== installed.id) throw new Error('Wrong library id');
        this.installedSkills = [];
        return { removed: true };
      default: return super.replyFor(request);
    }
  }

  holdReplyAfterCommit(method) {
    let release;
    const gate = new Promise(resolve => { release = resolve; });
    const replyFor = this.replyFor.bind(this);
    this.replyFor = request => {
      const result = replyFor(request);
      if (request.method !== method) return result;
      this.notify('skills.changed', {});
      return gate.then(() => result);
    };
    return release;
  }

  async openDetails(fromCatalog = false) {
    await this.install();
    await this.goto();
    await this.page.getByRole('button', { name: 'Skills', exact: true }).click();
    const summaries = this.page.locator('.skill-summary');
    // Installed rows render above the catalog, and each list arrives by its
    // own RPC. Until both have, first() and last() can name the same row.
    await expect(summaries).toHaveCount(this.installedSkills.length + this.catalogSkills.length);
    await (fromCatalog ? summaries.last() : summaries.first()).click();
    await expect(this.page.locator('.skill-preview-markdown')).toContainText('Plan uncertain work.');
  }
}

test('install and uninstall from the same catalog detail page', async ({ page }) => {
  const app = new SkillsHarness(page);
  await app.openDetails();
  await page.getByRole('button', { name: 'Install skill', exact: true }).click();
  await expect(page.getByRole('button', { name: 'Uninstall', exact: true })).toBeVisible();
  await page.getByRole('button', { name: 'Uninstall', exact: true }).click();
  await expect(page.getByRole('button', { name: 'Install skill', exact: true })).toBeVisible();
  expect(app.requests.filter(r => r.method === 'skills.uninstall').map(r => r.params.id)).toEqual([installed.id]);
  expect(app.installedSkills).toEqual([]);
  expect(app.pageErrors).toEqual([]);
});

test('removed skill without a catalog entry cannot be uninstalled again', async ({ page }) => {
  const app = new SkillsHarness(page, true);
  app.catalogSkills = [];
  await app.openDetails();
  await page.getByRole('button', { name: 'Uninstall', exact: true }).click();
  await expect(page.locator('.skill-detail-header')).toContainText('Not installed');
  await expect(page.getByRole('button', { name: 'Uninstall', exact: true })).toHaveCount(0);
  expect(app.installedSkills).toEqual([]);
  expect(app.pageErrors).toEqual([]);
});

for (const source of ['Yoorkin/wayfinder@0.0.9', 'Yoorkin/wayfinder@0.1.0/other']) {
  test(`catalog detail keeps install available for a different source: ${source}`, async ({ page }) => {
    const app = new SkillsHarness(page, true);
    app.installedSkills[0].source = source;
    await app.openDetails(true);
    await expect(page.getByRole('button', { name: 'Install skill', exact: true })).toBeVisible();
    await expect(page.getByRole('button', { name: 'Uninstall', exact: true })).toHaveCount(0);
    expect(app.pageErrors).toEqual([]);
  });
}

test('installed detail stops offering uninstall after the library removes it', async ({ page }) => {
  const app = new SkillsHarness(page, true);
  await app.openDetails();
  await page.getByRole('button', { name: 'Uninstall', exact: true }).click();
  await expect.poll(() => app.installedSkills.length).toBe(0);
  await expect(page.getByRole('button', { name: 'Uninstall', exact: true })).toHaveCount(0);
  await expect(page.getByRole('button', { name: 'Install skill', exact: true })).toBeVisible();
  await page.getByRole('button', { name: 'Install skill', exact: true }).click();
  await expect(page.getByRole('button', { name: 'Uninstall', exact: true })).toBeVisible();
  expect(app.pageErrors).toEqual([]);
});

test('uninstall failure is visible in the detail page and can be retried', async ({ page }) => {
  const app = new SkillsHarness(page, true);
  app.rpcErrors.set('skills.uninstall', 'Cannot remove skill: permission denied');
  await app.openDetails();
  await page.getByRole('button', { name: 'Uninstall', exact: true }).click();
  await expect(page.locator('.skill-detail-page')).toContainText('Cannot remove skill: permission denied');
  await expect(page.getByRole('button', { name: 'Uninstall', exact: true })).toBeEnabled();
  app.rpcErrors.delete('skills.uninstall');
  await page.getByRole('button', { name: 'Uninstall', exact: true }).click();
  await expect(page.getByRole('button', { name: 'Install skill', exact: true })).toBeVisible();
  expect(app.pageErrors).toEqual([]);
});

for (const removing of [false, true]) {
  test(`${removing ? 'uninstall' : 'install'} stays busy when SkillsChanged precedes its reply`, async ({ page }) => {
    const app = new SkillsHarness(page, removing);
    const method = removing ? 'skills.uninstall' : 'skills.install';
    const inverse = removing ? 'skills.install' : 'skills.uninstall';
    const busyLabel = removing ? 'Removing…' : 'Installing…';
    const release = app.holdReplyAfterCommit(method);
    await app.openDetails();
    const refreshes = app.requests.filter(r => r.method === 'skills.installed').length;
    await page.getByRole('button', { name: removing ? 'Uninstall' : 'Install skill', exact: true }).click();
    await expect.poll(() => app.requests.filter(r => r.method === 'skills.installed').length).toBeGreaterThan(refreshes);
    await expect(page.locator('.skill-detail-action')).toBeDisabled();
    await expect(page.locator('.skill-detail-action')).toHaveText(busyLabel);
    // Wait for the committed library state to render, rather than just for the request.
    await page.getByRole('button', { name: '← Back to skills', exact: true }).click();
    await expect(page.locator('.skill-row')).toHaveCount(removing ? 1 : 2);
    const listAction = page.locator('.skill-row button.skill-action');
    await expect(listAction).toBeDisabled();
    await expect(listAction).toHaveText(busyLabel);
    await page.locator('.skill-summary').first().click();
    const action = page.locator('.skill-detail-action');
    await expect(action).toBeDisabled();
    await expect(action).toHaveText(busyLabel);
    await action.evaluate(button => button.click());
    expect(app.requests.filter(r => r.method === inverse)).toHaveLength(0);
    release();
    const nextAction = page.getByRole('button', { name: removing ? 'Install skill' : 'Uninstall', exact: true });
    await expect(nextAction).toBeEnabled();
    await nextAction.click();
    await expect.poll(() => app.requests.filter(r => r.method === inverse).length).toBe(1);
    expect(app.pageErrors).toEqual([]);
  });
}

for (const targetInstalled of [false, true]) {
  test(`opening ${targetInstalled ? 'installed' : 'catalog'} details hides another skill's error, including cached previews`, async ({ page }) => {
    const app = new SkillsHarness(page, true);
    const other = { ...market, name: 'widget', module_name: 'acme/widget' };
    app.catalogSkills.push(other);
    if (targetInstalled) {
      app.installedSkills.push({ ...installed, id: 'acme-widget', name: 'widget', source: 'acme/widget@0.1.0' });
    }
    app.rpcErrors.set('skills.uninstall', 'Cannot remove wayfinder: permission denied');
    await app.openDetails();
    const contentMethod = targetInstalled ? 'skills.installed_content' : 'skills.content';
    const initialReads = app.requests.filter(r => r.method === contentMethod).length;
    for (const cached of [false, true]) {
      await page.locator('.skill-detail-page').getByRole('button', { name: 'Uninstall', exact: true }).click();
      await expect(page.locator('.skill-detail-page')).toContainText('Cannot remove wayfinder: permission denied');
      await page.getByRole('button', { name: '← Back to skills', exact: true }).click();
      await page.locator('.skill-summary').filter({ hasText: 'widget' }).first().click();
      await expect(page.locator('.skill-detail-header h1')).toHaveText('widget');
      await expect(page.locator('.skill-preview-markdown')).toBeVisible();
      await expect(page.locator('.skill-detail-page .skills-notice')).toHaveCount(0);
      // The second navigation exercises the cached branch without another read.
      expect(app.requests.filter(r => r.method === contentMethod)).toHaveLength(initialReads + 1);
      if (!cached) {
        await page.getByRole('button', { name: '← Back to skills', exact: true }).click();
        await page.locator('.skill-summary').filter({ hasText: 'wayfinder' }).first().click();
      }
    }
    expect(app.pageErrors).toEqual([]);
  });
}

for (const removing of [false, true]) {
  test(`late ${removing ? 'uninstall' : 'install'} errors stay with their skill across navigation and retry`, async ({ page }) => {
    const app = new SkillsHarness(page, removing);
    app.catalogSkills.push({ ...market, name: 'widget', module_name: 'acme/widget' });
    const method = removing ? 'skills.uninstall' : 'skills.install';
    const actionName = removing ? 'Uninstall' : 'Install skill';
    const replyFor = app.replyFor.bind(app);
    let release;
    const pending = new Promise(resolve => { release = resolve; });
    let failWayfinder = true;
    app.replyFor = request => {
      if (request.method === 'skills.install' && request.params.module_name === 'acme/widget') {
        return { error: 'Widget install failed' };
      }
      if (request.method === method && failWayfinder) return pending;
      return replyFor(request);
    };
    await app.openDetails();
    const detail = page.locator('.skill-detail-page');
    const back = page.getByRole('button', { name: '← Back to skills', exact: true });
    await detail.getByRole('button', { name: actionName, exact: true }).click();
    await expect(detail.locator('.skill-detail-action')).toBeDisabled();
    await back.click();
    await page.locator('.skill-summary').filter({ hasText: 'widget' }).first().click();
    await expect(page.locator('.skill-detail-header h1')).toHaveText('widget');
    await detail.getByRole('button', { name: 'Install skill', exact: true }).click();
    await expect(detail.locator('.skills-notice')).toHaveText('Widget install failed');
    release({ error: 'Wayfinder operation failed after navigation' });
    await back.click();
    await expect(page.locator('.skills-notice')).toHaveCount(2);
    await expect(page.locator('.skills-notice').filter({ hasText: 'Wayfinder operation failed' })).toContainText(installed.source);
    await expect(page.locator('.skills-notice').filter({ hasText: 'Widget install failed' })).toContainText('acme/widget@0.1.0');
    // A late completion cannot overwrite B's error, including cached navigation.
    await page.locator('.skill-summary').filter({ hasText: 'widget' }).first().click();
    await expect(detail.locator('.skills-notice')).toHaveText('Widget install failed');
    await back.click();
    await page.locator('.skill-summary').filter({ hasText: 'wayfinder' }).first().click();
    await expect(detail.locator('.skills-notice')).toHaveText('Wayfinder operation failed after navigation');
    failWayfinder = false;
    await detail.getByRole('button', { name: actionName, exact: true }).click();
    await expect(detail.getByRole('button', { name: removing ? 'Install skill' : 'Uninstall', exact: true })).toBeEnabled();
    await expect(detail.locator('.skills-notice')).toHaveCount(0);
    await back.click();
    await expect(page.locator('.skills-notice')).toHaveCount(1);
    await expect(page.locator('.skills-notice')).toContainText('Widget install failed');
    expect(app.pageErrors).toEqual([]);
  });
}
