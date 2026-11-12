import { test, expect } from '@playwright/test'
import { as, record, rows, SECTORS } from './sim-helpers'
import { capture } from './helpers/capture'

// Bloc A — Démarrer (base remise à zéro : le référentiel « Emplois » est vide, il faut le remplir avant la première embauche).
test.describe.configure({ mode: 'serial' })

test('palier 11 · A — créer les emplois dans Paramètres › Référentiels RH', async ({ browser }) => {
  const page = await as(browser, 'rh')
  await page.goto('/parametres?onglet=referentiels')
  await expect(page.getByRole('heading', { name: 'Emplois' }).first()).toBeVisible()
  await capture(page, 'referentiels-emplois-vide')
  const jobs = [...new Set(SECTORS.flatMap((s) => s.jobs))]
  for (const job of jobs) {
    await page.getByRole('button', { name: 'Ajouter' }).first().click()
    const dlg = page.getByRole('dialog')
    if (job === jobs[0]) await capture(page, 'referentiels-emplois-ajouter')
    await dlg.getByLabel('Emploi').fill(job)
    await dlg.getByRole('button', { name: 'Créer', exact: true }).click()
    await expect(dlg).toBeHidden()
  }
  await expect(page.getByText(jobs[jobs.length - 1], { exact: true }).first()).toBeVisible()
  await capture(page, 'referentiels-emplois-liste')
  const n = (await rows(page, 'designations?select=id')).length
  expect(n).toBe(jobs.length)
  record('UC-A-EMPLOIS', 'VERT', `${n} emplois créés par l'interface`)
})
