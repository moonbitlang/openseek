import { test, expect } from '@playwright/test';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';

const market = {
  name: 'wayfinder', module_name: 'Yoorkin/wayfinder', package_path: '',
  version: '0.1.0', description: 'Plan uncertain work.', author: 'Yoorkin', repository: '',
};
const installed = {
  id: 'yoorkin-wayfinder', name: 'wayfinder', description: market.description,
  source: 'Yoorkin/wayfinder@0.1.0',
  registry: { module_name: 'Yoorkin/wayfinder', package_path: '' },
  enabled: true,
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
      case 'skills.install': {
        const previous = this.installedSkills.find(skill => skill.id === installed.id);
        const updated = {
          ...structuredClone(installed),
          source: `${request.params.module_name}@${request.params.version}`,
          enabled: previous?.enabled ?? true,
        };
        this.installedSkills = [updated];
        return { installed: updated };
      }
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
    const installedGroup = this.page.locator('.settings-group').filter({
      has: this.page.getByRole('heading', { name: 'Installed', exact: true }),
    });
    const availableGroup = this.page.locator('.settings-group').filter({
      has: this.page.getByRole('heading', { name: 'Available', exact: true }),
    });
    await expect(availableGroup).toBeVisible();
    await expect(installedGroup.locator('.skill-row')).toHaveCount(this.installedSkills.length);
    await expect(availableGroup.getByText('Loading the skill catalog…', { exact: true })).toHaveCount(0);
    const group = fromCatalog || this.installedSkills.length === 0 ? availableGroup : installedGroup;
    await group.locator('.skill-summary').first().click();
    await expect(this.page.locator('.skill-preview-markdown')).toContainText('Plan uncertain work.');
  }

  async performAction(name) {
    if (name === 'Uninstall') {
      await this.page.locator('.skill-detail-page').getByRole('button', { name: 'Manage skill', exact: true }).click();
    }
    await this.page.getByRole(name === 'Uninstall' ? 'menuitem' : 'button', { name, exact: true }).click();
  }
}

test('install and uninstall from the same catalog detail page', async ({ page }) => {
  const app = new SkillsHarness(page);
  await app.openDetails();
  await expect(page.locator('.skill-detail-header h2')).toHaveText(installed.name);
  await expect(page.locator('.skill-detail-meta')).toHaveText(installed.source);
  await page.getByRole('button', { name: 'Install skill', exact: true }).click();
  await expect(page.getByRole('button', { name: 'Manage skill', exact: true })).toBeVisible();
  await expect(page.locator('.skill-detail-header h2')).toHaveText(installed.name);
  await app.performAction('Uninstall');
  await expect(page.getByRole('button', { name: 'Install skill', exact: true })).toBeVisible();
  expect(app.requests.filter(r => r.method === 'skills.uninstall').map(r => r.params.id)).toEqual([installed.id]);
  expect(app.installedSkills).toEqual([]);
  expect(app.pageErrors).toEqual([]);
});

test('removed skill without a catalog entry cannot be uninstalled again', async ({ page }) => {
  const app = new SkillsHarness(page, true);
  app.catalogSkills = [];
  await app.openDetails();
  await app.performAction('Uninstall');
  await expect(page.locator('.skill-detail-header')).toContainText('Not installed');
  await expect(page.getByRole('button', { name: 'Manage skill', exact: true })).toHaveCount(0);
  expect(app.installedSkills).toEqual([]);
  expect(app.pageErrors).toEqual([]);
});

for (const { source, packagePath } of [
  { source: 'Yoorkin/wayfinder@0.0.9', packagePath: '' },
  { source: 'Yoorkin/wayfinder@0.1.0/other', packagePath: 'other' },
]) {
  test(`catalog excludes installed packages regardless of version: ${source}`, async ({ page }) => {
    const app = new SkillsHarness(page, true);
    app.installedSkills[0].source = source;
    app.installedSkills[0].registry.package_path = packagePath;
    const samePackage = packagePath === '';
    await app.openDetails(!samePackage);
    if (samePackage) {
      await page.getByRole('button', { name: 'Back', exact: true }).click();
      const registry = page.locator('.settings-group').filter({ has: page.getByRole('heading', { name: 'Available', exact: true }) });
      await expect(registry.locator('.skill-row')).toHaveCount(0);
    } else {
      await expect(page.getByRole('button', { name: 'Install skill', exact: true })).toBeVisible();
      await expect(page.getByRole('button', { name: 'Manage skill', exact: true })).toHaveCount(0);
    }
    expect(app.pageErrors).toEqual([]);
  });
}

test('installed detail stops offering uninstall after the library removes it', async ({ page }) => {
  const app = new SkillsHarness(page, true);
  await app.openDetails();
  await app.performAction('Uninstall');
  await expect.poll(() => app.installedSkills.length).toBe(0);
  await expect(page.getByRole('button', { name: 'Manage skill', exact: true })).toHaveCount(0);
  await expect(page.getByRole('button', { name: 'Install skill', exact: true })).toBeVisible();
  await page.getByRole('button', { name: 'Install skill', exact: true }).click();
  await expect(page.getByRole('button', { name: 'Manage skill', exact: true })).toBeVisible();
  expect(app.pageErrors).toEqual([]);
});

test('uninstall failure is visible in the detail page and can be retried', async ({ page }) => {
  const app = new SkillsHarness(page, true);
  app.rpcErrors.set('skills.uninstall', 'Cannot remove skill: permission denied');
  await app.openDetails();
  await app.performAction('Uninstall');
  await expect(page.locator('.skill-detail-page')).toContainText('Cannot remove skill: permission denied');
  await expect(page.getByRole('button', { name: 'Manage skill', exact: true })).toBeEnabled();
  app.rpcErrors.delete('skills.uninstall');
  await app.performAction('Uninstall');
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
    await app.performAction(removing ? 'Uninstall' : 'Install skill');
    await expect.poll(() => app.requests.filter(r => r.method === 'skills.installed').length).toBeGreaterThan(refreshes);
    await expect(page.locator('.skill-detail-action')).toBeDisabled();
    await expect(page.locator('.skill-detail-action')).toHaveAccessibleName(busyLabel);
    // Wait for the committed library state to render, rather than just for the request.
    await page.getByRole('button', { name: 'Back', exact: true }).click();
    const group = page.locator('.settings-group').filter({
      has: page.getByRole('heading', { name: removing ? 'Available' : 'Installed', exact: true }),
    });
    await expect(group.locator('.skill-row')).toHaveCount(1);
    const listAction = group.locator('.skill-row button.skill-action');
    await expect(listAction).toBeDisabled();
    await expect(listAction).toHaveAccessibleName(busyLabel);
    await group.locator('.skill-summary').click();
    const action = page.locator('.skill-detail-action');
    await expect(action).toBeDisabled();
    await expect(action).toHaveAccessibleName(busyLabel);
    await action.evaluate(button => button.click());
    expect(app.requests.filter(r => r.method === inverse)).toHaveLength(0);
    release();
    const nextAction = page.getByRole('button', { name: removing ? 'Install skill' : 'Manage skill', exact: true });
    await expect(nextAction).toBeEnabled();
    await app.performAction(removing ? 'Install skill' : 'Uninstall');
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
      app.installedSkills.push({ ...installed, id: 'acme-widget', name: 'widget', source: 'acme/widget@0.1.0', registry: { module_name: 'acme/widget', package_path: '' } });
    }
    app.rpcErrors.set('skills.uninstall', 'Cannot remove wayfinder: permission denied');
    await app.openDetails();
    const contentMethod = targetInstalled ? 'skills.installed_content' : 'skills.content';
    const initialReads = app.requests.filter(r => r.method === contentMethod).length;
    for (const cached of [false, true]) {
      await app.performAction('Uninstall');
      await expect(page.locator('.skill-detail-page')).toContainText('Cannot remove wayfinder: permission denied');
      await page.getByRole('button', { name: 'Back', exact: true }).click();
      await page.locator('.skill-summary').filter({ hasText: 'widget' }).first().click();
      await expect(page.locator('.skill-detail-header h2')).toHaveText('widget');
      await expect(page.locator('.skill-preview-markdown')).toBeVisible();
      await expect(page.locator('.skill-detail-page .skills-notice')).toHaveCount(0);
      // The second navigation exercises the cached branch without another read.
      expect(app.requests.filter(r => r.method === contentMethod)).toHaveLength(initialReads + 1);
      if (!cached) {
        await page.getByRole('button', { name: 'Back', exact: true }).click();
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
    const back = page.getByRole('button', { name: 'Back', exact: true });
    await app.performAction(actionName);
    await expect(detail.locator('.skill-detail-action')).toBeDisabled();
    await back.click();
    await page.locator('.skill-summary').filter({ hasText: 'widget' }).first().click();
    await expect(page.locator('.skill-detail-header h2')).toHaveText('widget');
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
    await app.performAction(actionName);
    await expect(detail.getByRole('button', { name: removing ? 'Install skill' : 'Manage skill', exact: true })).toBeEnabled();
    await expect(detail.locator('.skills-notice')).toHaveCount(0);
    await back.click();
    await expect(page.locator('.skills-notice')).toHaveCount(1);
    await expect(page.locator('.skills-notice')).toContainText('Widget install failed');
    expect(app.pageErrors).toEqual([]);
  });
}

test('skill enablement comes from the host and survives list/detail navigation and reload', async ({ page }) => {
  const app = new SkillsHarness(page, true);
  await app.openDetails();
  const toggle = page.getByRole('switch');
  const contentReads = app.requests.filter(r => r.method === 'skills.installed_content').length;
  await expect(toggle).toHaveAttribute('aria-checked', 'true');
  await toggle.click();
  await expect(toggle).toHaveAttribute('aria-checked', 'false');
  await expect(page.locator('.skill-preview-markdown')).toContainText('Plan uncertain work.');
  expect(app.requests.filter(r => r.method === 'skills.installed_content')).toHaveLength(contentReads);
  expect(app.requests.filter(r => r.method === 'skills.set_enabled').map(r => r.params))
    .toEqual([{ id: installed.id, enabled: false }]);
  await page.getByRole('button', { name: 'Back', exact: true }).click();
  await expect(toggle).toHaveAttribute('aria-checked', 'false');
  await page.reload();
  await page.getByRole('button', { name: 'Skills', exact: true }).click();
  await expect(toggle).toHaveAttribute('aria-checked', 'false');
  await toggle.click();
  await expect(toggle).toHaveAttribute('aria-checked', 'true');
  expect(app.requests.filter(r => r.method === 'skills.set_enabled').map(r => r.params))
    .toEqual([{ id: installed.id, enabled: false }, { id: installed.id, enabled: true }]);
  expect(app.pageErrors).toEqual([]);
});

test('enablement changes preserve an in-flight preview request', async ({ page }) => {
  const app = new SkillsHarness(page, true);
  const replyFor = app.replyFor.bind(app);
  let release;
  const content = new Promise(resolve => { release = resolve; });
  app.replyFor = request => request.method === 'skills.installed_content'
    ? content.then(() => replyFor(request))
    : replyFor(request);
  await app.install();
  await app.goto();
  await page.getByRole('button', { name: 'Skills', exact: true }).click();
  await page.getByRole('button', { name: installed.name, exact: true }).click();
  const toggle = page.getByRole('switch');
  await expect(toggle).toHaveAttribute('aria-checked', 'true');
  await expect(page.getByRole('button', { name: 'Copy SKILL.md', exact: true })).toHaveCount(0);
  await toggle.click();
  await expect(toggle).toHaveAttribute('aria-checked', 'false');
  release();
  await expect(page.locator('.skill-preview-markdown')).toContainText('Plan uncertain work.');
  await expect(page.getByRole('button', { name: 'Copy SKILL.md', exact: true })).toBeVisible();
  expect(app.requests.filter(r => r.method === 'skills.installed_content')).toHaveLength(1);
  expect(app.pageErrors).toEqual([]);
});

test('a failed handwritten skill move preserves its state and can be retried', async ({ page }) => {
  const app = new SkillsHarness(page, true);
  app.installedSkills[0] = { ...installed, id: 'My notes', source: '', registry: undefined };
  app.rpcErrors.set('skills.set_enabled', 'Cannot move skill: permission denied');
  await app.openDetails();
  await expect(page.getByRole('button', { name: 'Manage skill', exact: true })).toHaveCount(0);
  const toggle = page.getByRole('switch');
  await toggle.click();
  await expect(page.locator('.skill-detail-page .skills-notice')).toHaveText('Cannot move skill: permission denied');
  await expect(toggle).toHaveAttribute('aria-checked', 'true');
  await expect(toggle).toBeEnabled();
  app.rpcErrors.delete('skills.set_enabled');
  await toggle.click();
  await expect(toggle).toHaveAttribute('aria-checked', 'false');
  await expect(page.locator('.skill-detail-page .skills-notice')).toHaveCount(0);
  expect(app.pageErrors).toEqual([]);
});

for (const enabled of [true, false]) {
  test(`enablement remains independent while updating an initially ${enabled ? 'enabled' : 'disabled'} skill`, async ({ page }) => {
    const app = new SkillsHarness(page, true);
    app.installedSkills[0].enabled = enabled;
    app.catalogSkills[0].version = '0.1.1';
    const replyFor = app.replyFor.bind(app);
    let release;
    const update = new Promise(resolve => { release = resolve; });
    app.replyFor = request => request.method === 'skills.install'
      ? update.then(() => replyFor(request))
      : replyFor(request);
    await app.openDetails();
    const contentReads = app.requests.filter(r => r.method === 'skills.installed_content').length;
    await page.getByRole('button', { name: 'Manage skill', exact: true }).click();
    await page.getByRole('menuitem', { name: 'Update to 0.1.1', exact: true }).click();
    const management = page.locator('.skill-detail-action');
    await expect(management).toBeDisabled();
    const toggle = page.getByRole('switch');
    await expect(toggle).toBeEnabled();
    await toggle.click();
    await expect(toggle).toHaveAttribute('aria-checked', String(!enabled));
    await expect(management).toBeDisabled();
    expect(app.requests.filter(r => r.method === 'skills.installed_content')).toHaveLength(contentReads);
    expect(app.requests.filter(r => r.method === 'skills.set_enabled').map(r => r.params))
      .toEqual([{ id: installed.id, enabled: !enabled }]);
    release();
    await expect(management).toBeEnabled();
    await expect(page.locator('.skill-detail-meta')).toHaveText('Yoorkin/wayfinder@0.1.1');
    await expect.poll(() => app.requests.filter(r => r.method === 'skills.installed_content').length)
      .toBe(contentReads + 1);
    await expect(toggle).toHaveAttribute('aria-checked', String(!enabled));
    expect(app.pageErrors).toEqual([]);
  });
}
