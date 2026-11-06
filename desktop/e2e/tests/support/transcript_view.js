import { expect } from '@playwright/test';

export async function openTranscriptView(page) {
  await page.getByRole('button', { name: 'Settings', exact: true }).click();
  const dialog = page.getByRole('dialog', { name: 'Settings', exact: true });
  const control = dialog.getByRole('group', { name: 'Conversation view', exact: true });
  await expect(control).toBeVisible();
  return control;
}

export async function chooseTranscriptView(page, name) {
  const control = await openTranscriptView(page);
  await control.getByRole('button', { name, exact: true }).click();
  await expect(control.getByRole('button', { name, exact: true })).toHaveAttribute('aria-pressed', 'true');
  await page.getByRole('dialog', { name: 'Settings', exact: true }).getByRole('button', { name: 'Dismiss', exact: true }).click();
}
