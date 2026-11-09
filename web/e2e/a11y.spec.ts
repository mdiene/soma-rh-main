import AxeBuilder from '@axe-core/playwright'
import { expect, test, type Page } from '@playwright/test'
import { stateFile, start } from './helpers'

// Accessibilité WCAG 2 A/AA. La sidebar (notre composant) doit être sans violation ; les pages entières sont
// contrôlées sur les violations « critical » seulement, pour ne pas bloquer sur la dette existante des écrans.
test.use({ storageState: stateFile('admin') })
const scan = (page: Page) => new AxeBuilder({ page }).withTags(['wcag2a', 'wcag2aa'])
const resume = (v: { id: string; impact?: string | null; nodes: unknown[] }[]) => v.map((x) => `${x.id} (${x.impact}, ${x.nodes.length})`)

test('sidebar développée : aucune violation', async ({ page }) => {
  await start(page)
  const { violations } = await scan(page).include('aside').analyze()
  expect(resume(violations)).toEqual([])
})

test('sidebar réduite avec flyout ouvert : aucune violation', async ({ page }) => {
  await start(page)
  await page.getByRole('button', { name: 'Réduire le menu' }).click()
  await page.getByRole('button', { name: /^Administration du personnel/ }).click()
  const { violations } = await scan(page).include('aside').include('[role="group"]').analyze()
  expect(resume(violations)).toEqual([])
})

test('recherche rapide Ctrl+K : aucune violation', async ({ page }) => {
  await start(page)
  await page.keyboard.press('Control+k')
  await expect(page.getByRole('dialog', { name: 'Recherche rapide' })).toBeVisible()
  const { violations } = await scan(page).include('[role="dialog"]').analyze()
  expect(resume(violations)).toEqual([])
})

for (const [role, route] of [['admin', '/'], ['admin', '/modules'], ['salarie', '/mon-espace']] as const) {
  test.describe(`${role} ${route}`, () => {
    test.use({ storageState: stateFile(role) })
    test('aucune violation critique', async ({ page }) => {
      await start(page, route)
      await page.waitForLoadState('networkidle')
      const { violations } = await scan(page).analyze()
      expect(resume(violations.filter((v) => v.impact === 'critical'))).toEqual([])
      if (violations.length) test.info().annotations.push({ type: 'à corriger', description: resume(violations).join(' ; ') })
    })
  })
}
