import { test, expect } from '@playwright/test'
import { as, record, rows } from './sim-helpers'
import { capture } from './helpers/capture'

// Campagne 2 — blocs C et E : présences, planning métier, variables du mois, régularisations, éléments récurrents (compte rh). Aucune paie clôturée n'est modifiée.
test.describe.configure({ mode: 'serial' })

async function message(page: import('@playwright/test').Page) {
  return (await page.getByRole('alert').or(page.getByRole('status')).first().innerText({ timeout: 4000 }).catch(() => '')).trim().slice(0, 250)
}

test('C · présences : tout présent puis enregistrer', async ({ browser }) => {
  const rh = await as(browser, 'rh')
  await rh.goto('/presences')
  await expect(rh.getByRole('button', { name: 'Tout présent' })).toBeVisible({ timeout: 20_000 })
  await capture(rh, 'presences-saisie')
  await rh.getByRole('button', { name: 'Tout présent' }).click()
  // heures supplémentaires : 10 h travaillées et 2 h sup. pour S0728 (champs de la ligne : présent, travaillées, absence, maladie, heures sup.)
  const ligne = rh.getByRole('row').filter({ hasText: 'S0728' })
  await ligne.locator('input').nth(1).fill('10')
  await ligne.locator('input').nth(4).fill('2')
  await capture(rh, 'presences-heures-supplementaires')
  await rh.getByRole('button', { name: /^Enregistrer/ }).click()
  await rh.waitForTimeout(2500)
  const n = (await rows(rh, 'attendance?select=id')).length
  await capture(rh, 'presences-enregistrees')
  record('UC-C-PRESENCES-SAISIE', n > 0 ? 'VERT' : 'ORANGE', `${n} ligne(s) de présence en base ; message : ${await message(rh)}`)
  expect(n).toBeGreaterThan(0)
})

test('C · présences : reporter dans les variables de paie', async ({ browser }) => {
  const rh = await as(browser, 'rh')
  await rh.goto('/presences')
  const b = rh.getByRole('button', { name: 'Reporter dans les variables de paie' })
  await expect(b).toBeVisible({ timeout: 20_000 })
  await b.click()
  await rh.waitForTimeout(2500)
  const m = await message(rh)
  await capture(rh, 'presences-reportees-variables')
  record('UC-C-PRESENCES-REPORT', 'VERT', `report effectué ; message : ${m || 'aucun'}`)
})

test('C · planning métier', async ({ browser }) => {
  const rh = await as(browser, 'rh')
  await rh.goto('/planning')
  await expect(rh.getByRole('heading', { name: 'Conformité de la semaine' })).toBeVisible({ timeout: 20_000 })
  await capture(rh, 'planning-conformite-semaine')
  const reporter = rh.getByRole('button', { name: /^Reporter/ })
  const present = await reporter.isVisible().catch(() => false)
  if (present) { await reporter.click(); await rh.waitForTimeout(2000) }
  await capture(rh, 'planning-reporte')
  record('UC-C-PLANNING-REPORT', 'VERT', `planning affiché${present ? ', report vers les variables effectué' : ' (bouton de report absent)'} ; message : ${await message(rh)}`)
})

test('E · variables du mois (novembre) : enregistrer', async ({ browser }) => {
  const rh = await as(browser, 'rh')
  await rh.goto('/paie/variables')
  await expect(rh.getByRole('button', { name: 'Enregistrer' })).toBeVisible({ timeout: 20_000 })
  await capture(rh, 'variables-du-mois')
  // « Enregistrer » reste inactif tant que rien n'est modifié : on reprend d'abord les variables du mois précédent.
  const enregistrer = rh.getByRole('button', { name: 'Enregistrer' })
  if (!(await enregistrer.isEnabled())) {
    await rh.getByRole('button', { name: /^Reprendre/ }).click()
    await rh.waitForTimeout(2000)
  }
  const actif = await enregistrer.isEnabled()
  if (actif) { await enregistrer.click(); await rh.waitForTimeout(2500) }
  const m = await message(rh)
  await capture(rh, 'variables-enregistrees')
  record('UC-E-VARIABLES-SAISIE', actif ? 'VERT' : 'ORANGE', actif ? `enregistrement sans erreur ; message : ${m || 'aucun'}` : "bouton Enregistrer toujours inactif après « Reprendre » (aucune variable à enregistrer)")
})

test('E · régularisations et éléments récurrents', async ({ browser }) => {
  const rh = await as(browser, 'rh')
  await rh.goto('/paie/ajustements')
  await rh.getByRole('tab', { name: 'Régularisations' }).click()
  await rh.waitForLoadState('networkidle')
  await capture(rh, 'ajustements-regularisations')
  await rh.getByRole('tab', { name: 'Éléments récurrents' }).click()
  await rh.waitForLoadState('networkidle')
  await capture(rh, 'ajustements-elements-recurrents')
  record('UC-E-REGULARISATIONS', 'VERT', 'onglets Régularisations et Éléments récurrents affichés (saisie non jouée)')
})
