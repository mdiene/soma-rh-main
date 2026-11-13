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

test('sidebar non épinglée avec flyout ouvert au survol : aucune violation', async ({ page }) => {
  await start(page)
  await page.getByRole('button', { name: 'Désépingler le menu (le replier)' }).click()
  await page.getByRole('button', { name: /^Administration du personnel/ }).hover()
  await expect(page.getByRole('group', { name: 'Administration du personnel' })).toBeVisible()
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

for (const [role, route] of [['admin', '/'], ['admin', '/modules'], ['admin', '/centre-conformite'], ['salarie', '/mon-espace'], ['salarie', '/aide'], ['admin', '/salaries/en-cours'], ['admin', '/a-propos'], ['admin', '/tarification'], ['salarie', '/conditions-utilisation'], ['salarie', '/confidentialite'], ['admin', '/sauvegardes-versions']] as const) {
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

test('assistant de création d\'un salarié : aucune violation dans la fenêtre', async ({ page }) => {
  await start(page, '/salaries/nouveau')
  await page.getByRole('button', { name: 'Avec l’assistant' }).click()
  const dlg = page.getByRole('dialog', { name: /assistant de saisie/ })
  await expect(dlg).toBeVisible()
  expect(resume((await scan(page).include('[role="dialog"]').analyze()).violations)).toEqual([])
  await dlg.getByLabel('Prénom', { exact: true }).fill('Axe')
  await dlg.getByLabel('Nom', { exact: true }).fill('Test')
  await dlg.getByLabel(/^N° CNI ou passeport/).fill('AXE-TEST-A11Y')
  await dlg.getByRole('button', { name: 'Valider et continuer' }).click()
  await expect(dlg.getByRole('heading', { name: /Coordonnées/ })).toBeVisible()
  expect(resume((await scan(page).include('[role="dialog"]').analyze()).violations)).toEqual([])
})
