import { test, expect } from './support/test.js';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';

const details = page => page.getByRole('dialog', { name: 'Skill details', exact: true });
const library = page => page.getByRole('dialog', { name: 'Skills', exact: true });

const market = {
  name: 'wayfinder', module_name: 'Yoorkin/wayfinder', package_path: '',
  version: '0.1.0', description: 'Plan uncertain work.', author: 'Yoorkin', repository: '',
};
const installed = {
  id: 'yoorkin-wayfinder', name: 'wayfinder', description: market.description,
  source: 'Yoorkin/wayfinder@0.1.0',
  registry: { module_name: 'Yoorkin/wayfinder', package_path: '' },
  enabled: true,
  builtin: false,
};

class SkillsHarness extends DesktopBrowserHarness {
  constructor(page, alreadyInstalled = false) {
    super(page);
    this.installedSkills = alreadyInstalled ? [structuredClone(installed)] : [];
    this.catalogSkills = [structuredClone(market)];
    this.builtin = false;
    this.catalogError = null;
  }

  replyFor(request) {
    switch (request.method) {
      case 'skills.catalog': return this.catalogError
        ? { error: this.catalogError }
        : { skills: this.catalogSkills };
      case 'skills.content':
      case 'skills.installed_content':
        return { kind: 'content', content: '# Wayfinder\n\nPlan uncertain work.', absolute: '', sig: '' };
      case 'skills.install': {
        const previous = this.installedSkills.find(skill => skill.id === installed.id);
        const updated = {
          ...structuredClone(installed),
          source: `${request.params.module_name}@${request.params.version}`,
          enabled: previous?.enabled ?? true,
          builtin: this.builtin,
        };
        this.installedSkills = [updated];
        this.builtinSkillErrors = [];
        return { installed: updated };
      }
      case 'skills.uninstall':
        if (request.params.id !== installed.id) throw new Error('Wrong library id');
        this.installedSkills = [];
        return { removed: true };
      default: return super.replyFor(request);
    }
  }

  // Skills reads its catalog once, when it opens. Before the host socket is
  // open that read fails as "connection is down" and is not repeated, so open
  // Skills only once the page has sent a request over a new socket.
  async openSkills(previousRequests = 0) {
    await expect.poll(() => this.requests.length).toBeGreaterThan(previousRequests);
    await this.page.getByRole('button', { name: 'Skills', exact: true }).click();
  }

  async openDetails() {
    await this.install();
    await this.goto();
    await this.openSkills();
    await library(this.page).locator('.skill-summary').filter({ hasText: installed.name }).first().click();
    await expect.poll(() => this.requests.some(request =>
      request.method === 'skills.content' || request.method === 'skills.installed_content')).toBe(true);
  }
}

test('skill enablement comes from the host and survives list/detail navigation and reload', async ({ page }) => {
  const app = new SkillsHarness(page, true);
  await app.openDetails();
  const toggle = details(page).getByRole('switch');
  const contentReads = app.requests.filter(r => r.method === 'skills.installed_content').length;
  await expect(toggle).toHaveAttribute('aria-checked', 'true');
  await toggle.click();
  await expect(toggle).toHaveAttribute('aria-checked', 'false');
  expect(app.requests.filter(r => r.method === 'skills.installed_content')).toHaveLength(contentReads);
  expect(app.requests.filter(r => r.method === 'skills.set_enabled').map(r => r.params))
    .toEqual([{ id: installed.id, enabled: false }]);
  await details(page).getByRole('button', { name: 'Dismiss', exact: true }).click();
  const listToggle = library(page).getByRole('switch');
  await expect(listToggle).toHaveAttribute('aria-checked', 'false');
  const beforeReload = app.requests.length;
  await page.reload();
  await app.openSkills(beforeReload);
  await expect(listToggle).toHaveAttribute('aria-checked', 'false');
  await listToggle.click();
  await expect(listToggle).toHaveAttribute('aria-checked', 'true');
  expect(app.requests.filter(r => r.method === 'skills.set_enabled').map(r => r.params))
    .toEqual([{ id: installed.id, enabled: false }, { id: installed.id, enabled: true }]);
  expect(app.pageErrors).toEqual([]);
});
