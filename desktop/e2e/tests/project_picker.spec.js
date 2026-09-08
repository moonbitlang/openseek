import { test, expect } from '@playwright/test';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';

// End-to-end coverage of the project picker's path editor against the real
// browser bundle: filtering, per-directory completion browses, deletion
// climbing, fences for superseded requests, quiet completion failures, and
// the inline new-folder composer. The harness's path-keyed `browseTree` and
// hold/release controls make every scenario deterministic — where a reply
// racing the keyboard would blur an assertion, the test holds `fs.browse`
// until the typing is done and releases the replies afterwards.

// One coherent POSIX tree. Every directory the tests walk exists, so a
// missing-fixture refusal is always an intentional part of a scenario.
function posixTree() {
  return {
    '': { path: '/Users/test', parent: '/Users', entries: ['Projects', 'Workspace'] },
    '/': { path: '/', entries: ['Users'] },
    '/Users': { path: '/Users', parent: '/', entries: ['test'] },
    '/Users/test': { path: '/Users/test', parent: '/Users', entries: ['Projects', 'Workspace'] },
    '/Users/test/Projects': {
      path: '/Users/test/Projects',
      parent: '/Users/test',
      entries: ['openseek', 'openpilot'],
    },
    '/Users/test/Workspace': {
      path: '/Users/test/Workspace',
      parent: '/Users/test',
      entries: ['moonbit'],
    },
  };
}

async function openPicker(page, app) {
  await app.install();
  await app.goto();
  await page.getByRole('button', { name: 'Add a project' }).click();
  const picker = page.getByRole('dialog', { name: 'Add a project' });
  await expect(picker).toBeVisible();
  await expect(picker.getByLabel('Open folder Projects')).toBeVisible();
  return picker;
}

async function editPath(page, picker) {
  const shortcut = await page.evaluate(() =>
    navigator.platform.includes('Mac') ? 'Meta+L' : 'Control+L');
  await page.keyboard.press(shortcut);
  const input = picker.getByRole('combobox', { name: 'Folder path' });
  await expect(input).toBeFocused();
  return input;
}

async function selectAll(page) {
  const shortcut = await page.evaluate(() =>
    navigator.platform.includes('Mac') ? 'Meta+A' : 'Control+A');
  await page.keyboard.press(shortcut);
}

function browses(app, path) {
  return app.requests.filter(request =>
    request.method === 'fs.browse' && (request.params?.path ?? '') === path);
}

test('path editing filters rows, wraps its selection, and completes', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  app.browseTree = posixTree();
  const picker = await openPicker(page, app);

  const input = await editPath(page, picker);
  await expect(input).toHaveValue('/Users/test');
  // Typing replaces the selected path; 'o' hits both children, prefix first.
  await page.keyboard.type('/Users/test/o');
  await expect(picker.getByText('2 matches')).toBeVisible();
  const projects = picker.getByRole('option', { name: 'Open folder Projects' });
  const workspace = picker.getByRole('option', { name: 'Open folder Workspace' });
  await expect(projects).toHaveAttribute('aria-selected', 'true');
  await input.press('ArrowDown');
  await expect(workspace).toHaveAttribute('aria-selected', 'true');
  await input.press('ArrowDown');
  await expect(projects).toHaveAttribute('aria-selected', 'true');
  await input.press('ArrowUp');
  await expect(workspace).toHaveAttribute('aria-selected', 'true');
  // Tab completes locally; the separator then enters the completed child.
  await input.press('Tab');
  await expect(input).toHaveValue('/Users/test/Workspace');
  await page.keyboard.type('/');
  await expect(picker.getByLabel('Open folder moonbit')).toBeVisible();
  await expect(input).toHaveValue('/Users/test/Workspace/');
  expect(browses(app, '/Users/test/Workspace/')).toHaveLength(1);
  expect(app.pageErrors).toEqual([]);
});

test('folder actions follow whether the draft names the listed directory', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  app.browseTree = posixTree();
  const picker = await openPicker(page, app);
  const newFolder = picker.getByRole('button', { name: 'New folder' });
  const addProject = picker.getByRole('button', { name: 'Add project', exact: true });

  // An untouched editor still names the listed directory.
  await editPath(page, picker);
  await expect(newFolder).toBeEnabled();
  await expect(addProject).toBeEnabled();
  // A draft naming a child waits.
  await page.keyboard.type('/Users/test/Pro');
  await expect(newFolder).toBeDisabled();
  await expect(addProject).toBeDisabled();
  // Back to the directory itself: Add project registers it directly.
  await page.keyboard.type('jects/');
  await expect(picker.getByLabel('Open folder openseek')).toBeVisible();
  await expect(addProject).toBeEnabled();
  await addProject.click();
  await expect.poll(() => app.requests.find(request =>
    request.method === 'workspace.add')).toMatchObject({
    params: { path: '/Users/test/Projects' },
  });
  await expect(picker).toBeHidden();
  expect(app.pageErrors).toEqual([]);
});

test('deleting back across a separator climbs one level per request', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  app.browseTree = posixTree();
  const picker = await openPicker(page, app);
  await picker.getByLabel('Open folder Projects').click();
  await expect(picker.getByLabel('Open folder openseek')).toBeVisible();

  const input = await editPath(page, picker);
  await input.press('End');
  for (let i = 0; i < 7; i += 1) {
    await input.press('Backspace');
  }
  await expect(input).toHaveValue('/Users/test/P');
  // Seven deletions inside one level ask the host exactly once.
  await expect(picker.getByText('2 matches')).toBeVisible();
  await expect(picker.getByLabel('Open folder Projects')).toBeVisible();
  expect(browses(app, '/Users/test/')).toHaveLength(1);
  // Crossing the next separator climbs again.
  for (let i = 0; i < 3; i += 1) {
    await input.press('Backspace');
  }
  await expect(input).toHaveValue('/Users/tes');
  await expect(picker.getByLabel('Open folder test')).toBeVisible();
  expect(browses(app, '/Users/')).toHaveLength(1);
  expect(app.pageErrors).toEqual([]);
});

test('returning to the listed directory drops the pending parent browse', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  app.browseTree = posixTree();
  const picker = await openPicker(page, app);
  await picker.getByLabel('Open folder Projects').click();
  await expect(picker.getByLabel('Open folder openseek')).toBeVisible();

  const input = await editPath(page, picker);
  await input.press('End');
  app.hold('fs.browse');
  await input.press('Backspace');
  await expect(picker.getByText('Loading folders…')).toBeVisible();
  await expect.poll(() => app.heldCount('fs.browse')).toBe(1);
  // Retyping the deleted character returns to the listed directory before
  // the parent listing answered; its late reply must not move the picker.
  await page.keyboard.type('s');
  await expect(picker.getByLabel('Open folder openseek')).toBeVisible();
  expect(app.releaseHeld('fs.browse')).toBe(1);
  await expect(picker.getByLabel('Open folder openseek')).toBeVisible();
  await expect(picker.getByLabel('Open folder test')).toBeHidden();
  expect(app.pageErrors).toEqual([]);
});

test('escape fences a browse the editor started', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  app.browseTree = posixTree();
  const picker = await openPicker(page, app);

  const input = await editPath(page, picker);
  app.hold('fs.browse');
  await page.keyboard.type('/Users/test/Projects/');
  await expect.poll(() => app.heldCount('fs.browse')).toBeGreaterThan(0);
  await input.press('Escape');
  await expect(input).toBeHidden();
  // Every reply the edit had in flight is stale now.
  app.releaseHeld('fs.browse');
  await expect(picker.getByLabel('Open folder Projects')).toBeVisible();
  await expect(picker.getByLabel('Open folder openseek')).toBeHidden();
  expect(app.pageErrors).toEqual([]);
});

test('confirm waits for an in-flight navigation', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  app.browseTree = posixTree();
  const picker = await openPicker(page, app);

  app.hold('fs.browse');
  await picker.getByLabel('Open folder Projects').click();
  await expect(picker.getByText('Loading folders…')).toBeVisible();
  // The listing on screen is stale while the navigation is in flight, so
  // Enter must not register the previous directory.
  await page.keyboard.press('Enter');
  expect(app.releaseHeld('fs.browse')).toBe(1);
  await expect(picker.getByLabel('Open folder openseek')).toBeVisible();
  await page.keyboard.press('Enter');
  await expect.poll(() => app.requests.filter(request =>
    request.method === 'workspace.add')).toHaveLength(1);
  expect(app.requests.find(request =>
    request.method === 'workspace.add')).toMatchObject({
    params: { path: '/Users/test/Projects' },
  });
  expect(app.pageErrors).toEqual([]);
});

test('a directory the host cannot list stays quiet until Enter', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  app.browseTree = posixTree();
  const picker = await openPicker(page, app);

  const input = await editPath(page, picker);
  await page.keyboard.type('/gone/');
  await expect(picker.getByText('Cannot list this folder')).toBeVisible();
  // The host's own reason shows in place, not a generic hint.
  await expect(picker.getByText('no such directory: /gone')).toBeVisible();
  await expect(page.getByText('Cannot open folder', { exact: false })).toBeHidden();
  // Typing inside the refused directory does not ask again.
  await page.keyboard.type('x');
  expect(browses(app, '/gone/')).toHaveLength(1);
  await expect(picker.getByText('Cannot list this folder')).toBeVisible();
  await expect(picker.getByText('no such directory: /gone')).toBeVisible();
  // Enter navigates for real and surfaces the host's reason as a toast.
  await input.press('Enter');
  await expect(
    page.getByText('Cannot open folder: no such directory: /gone/x'),
  ).toBeVisible();
  await expect(picker.getByLabel('Open folder Users')).toBeVisible();
  expect(app.pageErrors).toEqual([]);
});

test('home-relative drafts are expanded by the host', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  app.browseTree = posixTree();
  app.browseTree['~'] = app.browseTree['/Users/test'];
  const picker = await openPicker(page, app);

  const input = await editPath(page, picker);
  // Hold the replies so the whole draft is typed before any of them lands;
  // only the last request — the parent `~/` — survives its fence.
  app.hold('fs.browse');
  await page.keyboard.type('~/Pro');
  await expect.poll(() => app.heldCount('fs.browse')).toBe(2);
  app.releaseHeld('fs.browse');
  // The host answered `~/` with the expanded home; the reply rewrote the
  // directory part and kept the typed segment.
  await expect(input).toHaveValue('/Users/test/Pro');
  await expect(picker.getByText('1 match')).toBeVisible();
  await expect(picker.getByRole('option', { name: 'Open folder Projects' })).toBeVisible();
  expect(browses(app, '~/')).toHaveLength(1);
  expect(app.pageErrors).toEqual([]);
});

test('a tilde-named child completes locally instead of going to the host', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  const tree = posixTree();
  tree[''] = { path: '/Users/test', parent: '/Users', entries: ['~archive', 'git'] };
  tree['/Users/test'] = tree[''];
  tree['/Users/test/~archive'] = {
    path: '/Users/test/~archive',
    parent: '/Users/test',
    entries: [],
  };
  app.browseTree = tree;
  await app.install();
  await app.goto();
  await page.getByRole('button', { name: 'Add a project' }).click();
  const picker = page.getByRole('dialog', { name: 'Add a project' });
  await expect(picker.getByLabel('Open folder ~archive')).toBeVisible();

  const input = await editPath(page, picker);
  await page.keyboard.type('~arch');
  await expect(picker.getByText('1 match')).toBeVisible();
  await expect(picker.getByRole('option', { name: 'Open folder ~archive' })).toBeVisible();
  await page.keyboard.type('ive/');
  await expect(picker.getByText('No folders here')).toBeVisible();
  await expect(input).toHaveValue('/Users/test/~archive/');
  expect(app.pageErrors).toEqual([]);
});

test('an alias of the listed directory is asked again after canonicalization', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  app.hostPlatform = 'windows';
  const canonical = { path: '/C:/', entries: ['Users'] };
  app.browseTree = {
    '': { path: '/C:/', entries: ['Users'] },
    '/': { drives: ['C:', 'D:'] },
    '/C:': canonical,
    '/c:': canonical,
  };
  await app.install();
  await app.goto();
  await page.getByRole('button', { name: 'Add a project' }).click();
  const picker = page.getByRole('dialog', { name: 'Add a project' });
  await expect(picker.getByLabel('Open folder Users')).toBeVisible();

  const input = await editPath(page, picker);
  // Typed at a human cadence: rabbita's value patch compares against the
  // vnode it last painted, so a burst faster than the frame rate whose
  // rewritten result equals the pre-burst value never reaches the DOM.
  // The per-keystroke delay keeps one paint per key, which is also what
  // real typing produces.
  app.hold('fs.browse');
  await page.keyboard.type('/c:/', { delay: 60 });
  await expect.poll(() => app.heldCount('fs.browse')).toBe(2);
  app.releaseHeld('fs.browse');
  await expect(input).toHaveValue('/C:/');
  await expect(picker.getByLabel('Open folder Users')).toBeVisible();
  // Retyping the alias is not a known miss: the host resolves it once more.
  await selectAll(page);
  app.hold('fs.browse');
  await page.keyboard.type('/c:/', { delay: 60 });
  await expect.poll(() => app.heldCount('fs.browse')).toBe(2);
  app.releaseHeld('fs.browse');
  await expect(input).toHaveValue('/C:/');
  await expect(picker.getByLabel('Open folder Users')).toBeVisible();
  expect(browses(app, '/c:/')).toHaveLength(2);
  expect(app.pageErrors).toEqual([]);
});

test('the Windows drive list lists drives and refuses Add project', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  app.hostPlatform = 'windows';
  app.browseTree = {
    '': { path: '/C:/Users/test', parent: '/C:/Users', entries: ['code'] },
    '/': { drives: ['C:', 'D:'] },
  };
  await app.install();
  await app.goto();
  await page.getByRole('button', { name: 'Add a project' }).click();
  const picker = page.getByRole('dialog', { name: 'Add a project' });
  await expect(picker.getByLabel('Open folder code')).toBeVisible();

  const input = await editPath(page, picker);
  await page.keyboard.type('/');
  await expect(picker.getByLabel('Open folder C:')).toBeVisible();
  await expect(picker.getByLabel('Open folder D:')).toBeVisible();
  // The level above the drive roots is not a directory to register.
  await expect(
    picker.getByRole('button', { name: 'Add project', exact: true }),
  ).toBeDisabled();
  await page.keyboard.type('C');
  await expect(picker.getByText('1 match')).toBeVisible();
  await expect(input).toHaveValue('/C');
  // A native drive-letter spelling is the host's to resolve, never a child
  // of the listed directory.
  app.browseTree['C:'] = { path: '/C:/', entries: ['Users'] };
  app.browseTree['C:/Users'] = { path: '/C:/Users', parent: '/C:/', entries: ['test'] };
  await selectAll(page);
  app.hold('fs.browse');
  await page.keyboard.type('C:/Users/');
  await expect.poll(() => app.heldCount('fs.browse')).toBe(2);
  app.releaseHeld('fs.browse');
  await expect(input).toHaveValue('/C:/Users/');
  await expect(picker.getByLabel('Open folder test')).toBeVisible();
  expect(browses(app, 'C:/')).toHaveLength(1);
  expect(browses(app, 'C:/Users/')).toHaveLength(1);
  expect(app.pageErrors).toEqual([]);
});

test('a child named like a drive letter completes locally on POSIX', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  const tree = posixTree();
  tree['/Users/test'] = { path: '/Users/test', parent: '/Users', entries: ['C:', 'git'] };
  tree[''] = tree['/Users/test'];
  tree['/Users/test/C:'] = {
    path: '/Users/test/C:',
    parent: '/Users/test',
    entries: ['inner'],
  };
  app.browseTree = tree;
  await app.install();
  await app.goto();
  await page.getByRole('button', { name: 'Add a project' }).click();
  const picker = page.getByRole('dialog', { name: 'Add a project' });
  await expect(picker.getByLabel('Open folder C:')).toBeVisible();

  // Without Windows semantics on display, `C:` is an ordinary directory
  // name; the drive-letter spelling completes under the listed directory.
  const input = await editPath(page, picker);
  await page.keyboard.type('C:/');
  await expect(picker.getByLabel('Open folder inner')).toBeVisible();
  await expect(input).toHaveValue('/Users/test/C:/');
  expect(browses(app, '/Users/test/C:/')).toHaveLength(1);
  expect(app.pageErrors).toEqual([]);
});

test('New folder focuses its input, creates on Enter, and enters the directory', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  app.browseTree = posixTree();
  const picker = await openPicker(page, app);

  await picker.getByRole('button', { name: 'New folder' }).click();
  const name = picker.getByLabel('New folder name');
  // The click leaves the button focused; the composer must claim focus.
  await expect(name).toBeFocused();
  await page.keyboard.type('openseek');
  await name.press('Enter');
  await expect.poll(() => app.requests.find(request =>
    request.method === 'fs.create_directory')).toMatchObject({
    params: { parent: '/Users/test', name: 'openseek' },
  });
  // Creation enters the created directory, which starts empty.
  await expect(picker.getByText('No folders here')).toBeVisible();
  await expect(picker.getByText('/Users/test/openseek')).toBeVisible();
  expect(app.pageErrors).toEqual([]);
});

test('a failed create keeps its name editable and focused', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  app.browseTree = posixTree();
  app.rpcErrors.set('fs.create_directory', 'already exists');
  const picker = await openPicker(page, app);

  await picker.getByRole('button', { name: 'New folder' }).click();
  const name = picker.getByLabel('New folder name');
  await expect(name).toBeFocused();
  await page.keyboard.type('taken');
  await name.press('Enter');
  await expect(page.getByText('Cannot create folder: already exists')).toBeVisible();
  await expect(name).toHaveValue('taken');
  // The input was disabled while the request was in flight; the failure
  // hands focus back so the name can be corrected without another click.
  await expect(name).toBeFocused();
  expect(app.pageErrors).toEqual([]);
});
