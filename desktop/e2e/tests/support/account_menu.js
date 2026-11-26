export const accountMenuTrigger = page => page.locator('#sidebar-account-menu-trigger');

export async function openAccountMenu(page) {
  const trigger = accountMenuTrigger(page);
  if (await trigger.getAttribute('aria-expanded') !== 'true') await trigger.click();
  return page.getByRole('menu', { name: 'Account', exact: true });
}

export async function selectAccountMenuItem(page, name) {
  const menu = await openAccountMenu(page);
  await menu.getByRole('menuitem', { name, exact: true }).click();
}
