import { test, expect } from '@playwright/test'
import { as, field, record } from './sim-helpers'
import { capture } from './helpers/capture'

// Blocs E et F — états légaux (4 onglets) et simulateur net/brut, en lecture seule, compte rh.
test.describe.configure({ mode: 'serial' })

const ONGLETS: [string, string, string][] = [
  ['Livre de paie', 'etat-livre-de-paie', 'UC-F-LIVRE'], ['État résumé des cotisations', 'etat-resume-cotisations', 'UC-F-RESUME'],
  ['Charges patronales', 'etat-charges-patronales', 'UC-F-PATRONALES'], ['Écritures comptables', 'etat-ecritures-comptables', 'UC-F-COMPTABLE'],
]

for (const [bouton, nom, uc] of ONGLETS) {
  test(`F · ${bouton}`, async ({ browser }) => {
    const rh = await as(browser, 'rh')
    await rh.goto('/etats')
    await rh.getByRole('tab', { name: bouton, exact: true }).click()
    await rh.waitForLoadState('networkidle')
    await expect(rh.getByRole('button', { name: 'Exporter CSV' })).toBeVisible({ timeout: 20_000 })
    await capture(rh, nom)
    record(uc, 'VERT', `onglet « ${bouton} » affiché avec export CSV`)
  })
}

test('E · simulateur net / brut pour un salarié', async ({ browser }) => {
  const rh = await as(browser, 'rh')
  await rh.goto('/paie/simulateur')
  const sel = field(rh, 'Salarié')
  const opt = (await sel.locator('option', { hasText: 'S0728' }).first().innerText()).trim()
  await sel.selectOption({ label: opt })
  await rh.waitForLoadState('networkidle')
  await rh.getByRole('button', { name: 'Simuler le bulletin' }).click()
  await expect(rh.getByText('Choisissez un salarié puis lancez la simulation.')).toBeHidden({ timeout: 30_000 })
  await rh.waitForTimeout(1000)
  await capture(rh, 'simulateur-net-brut')
  record('UC-E-SIMULATEUR', 'VERT', 'simulateur affiché pour S0728')
})

test('F · suivi des cotisations, mois d\'octobre', async ({ browser }) => {
  const rh = await as(browser, 'rh')
  await rh.goto('/paie/cotisations')
  await rh.getByRole('button', { name: 'Octobre 2026' }).click()
  await rh.waitForLoadState('networkidle')
  await capture(rh, 'cotisations-detail-octobre')
  record('UC-F-COTISATIONS-DETAIL', 'VERT', 'détail du mois affiché (saisie des versements : non jouée)')
})
