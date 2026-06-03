import { expect, type Locator, test } from '@playwright/test';

test('sign-in gate is visible, editable, and console-clean', async ({ page }, testInfo) => {
  const runtimeErrors: string[] = [];
  page.on('pageerror', (error) => runtimeErrors.push(error.message));
  page.on('console', (message) => {
    if (message.type() === 'error') runtimeErrors.push(message.text());
  });

  await page.goto('/');

  await expect(page.getByRole('heading', { name: 'Capture' })).toBeVisible();
  const email = page.getByPlaceholder('Email');
  const password = page.getByPlaceholder('Password');
  await expect(email).toBeEditable();
  await expect(password).toBeEditable();
  await assertUsableBox(email, 'email input');
  await assertUsableBox(password, 'password input');
  await email.fill('ui-smoke@example.com');
  await expect(email).toHaveValue('ui-smoke@example.com');

  await page.getByRole('button', { name: 'Email me a sign-in code' }).click();
  await expect(page.getByRole('button', { name: 'Send me a code' })).toBeVisible();
  await expect(page.getByPlaceholder('Email')).toBeEditable();

  await page.getByRole('button', { name: 'Back to password sign-in' }).click();
  await page.getByRole('button', { name: 'Forgot password?' }).click();
  await expect(page.getByRole('button', { name: 'Send reset code' })).toBeVisible();

  await page.screenshot({ path: testInfo.outputPath('signin-gate.png'), fullPage: true });
  expect(runtimeErrors).toEqual([]);
});

async function assertUsableBox(locator: Locator, label: string) {
  const box = await locator.boundingBox();
  expect(box, `${label} should have a rendered box`).not.toBeNull();
  expect(box!.width, `${label} should not be collapsed`).toBeGreaterThan(120);
  expect(box!.height, `${label} should not be collapsed`).toBeGreaterThan(24);
}
