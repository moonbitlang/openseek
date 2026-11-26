export const accountMenuTrigger = page => page.locator('#sidebar-account-menu-trigger');

export async function openAccountMenu(page, menuName = 'Account') {
  const trigger = accountMenuTrigger(page);
  if (await trigger.getAttribute('aria-expanded') !== 'true') await trigger.click();
  return page.getByRole('menu', { name: menuName, exact: true });
}

export async function selectAccountMenuItem(page, name, menuName) {
  const menu = await openAccountMenu(page, menuName);
  await menu.getByRole('menuitem', { name, exact: true }).click();
}
