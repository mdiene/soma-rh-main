import { test, expect } from '@playwright/test'
import { as, govStep, record, rows, shot } from './sim-helpers'

// Réouverture motivée d'octobre 2026 (admin), recalcul (RPR-05) avec le prorata de sortie (RPR-09), puis nouvelle clôture.
// Idempotent : si octobre est déjà recalculé avec prorata, le test se limite à la vérification.
const SORTANT = 'S0883'

test('réouverture d’octobre, recalcul et nouvelle clôture', async ({ browser }) => {
  const admin = await as(browser, 'admin')
  const paie = await as(browser, 'paie')
  const approbateur = await as(browser, 'paie2') // RPR-02 : approuvent l'administrateur et le rôle paie (pas rh)

  const entree = (await rows<{ id: string; status: string }>(admin, 'payroll_entries?select=id,status&period_start=eq.2026-10-01&status=neq.Annulée'))[0]
  const prorata = async () => rows<{ id: string }>(admin, `salary_slip_details?select=id,salary_slips!inner(employee_number,period_start,status)&component_code=eq.RET_PRORATA&salary_slips.employee_number=eq.${SORTANT}&salary_slips.period_start=eq.2026-10-01&salary_slips.status=neq.Annulé`)

  if ((await prorata()).length === 0) {
    // 1. réouverture par l'administrateur, avec motif (sautée si la paie a déjà été rouverte)
    if (entree.status === 'Clôturée') {
    await admin.goto('/paie/gouvernance')
    await admin.waitForLoadState('networkidle')
    const section = admin.locator('section, div').filter({ hasText: /^Octobre 2026/ }).filter({ has: admin.getByRole('button', { name: 'Rouvrir' }) }).last()
    await section.getByRole('button', { name: 'Rouvrir' }).click()
    const dlg = admin.getByRole('dialog')
    await dlg.getByLabel(/Motif/).fill('Prorata de sortie D-56 (S0883) non appliqué au premier calcul')
    await shot(admin, 'reouverture-motif')
    await dlg.getByRole('button', { name: 'Rouvrir', exact: true }).click()
    await expect.poll(async () => (await rows<{ status: string }>(admin, `payroll_entries?select=status&id=eq.${entree.id}`))[0].status, { timeout: 30_000 }).toBe('Réouverte')
    record('UC-REOUVERTURE', 'VERT', 'octobre 2026 : Clôturée → Réouverte avec motif (admin)')
    }

    // 2. recalcul (RPR-05 : bouton disponible sur une paie Réouverte ; libellé « Calculer » tant que la liste des bulletins est vide)
    await paie.goto(`/paie/${entree.id}`)
    const bouton = paie.getByRole('button', { name: /^(Recalculer|Calculer les bulletins)$/ })
    await expect(bouton, 'RPR-05 : pas de bouton Recalculer sur une paie rouverte').toBeVisible({ timeout: 20_000 })
    await bouton.click()
    await expect(paie.getByText(/200 bulletin\(s\) calculé\(s\)/)).toBeVisible({ timeout: 120_000 })
    await shot(paie, 'reouverture-recalcul')
  }

  // 3. nouvelle clôture avec séparation des tâches
  const refus: string[] = []
  const etat = async () => (await rows<{ status: string }>(admin, `payroll_entries?select=status&id=eq.${entree.id}`))[0].status
  if ((await etat()) !== 'Clôturée') {
    for (const [page, label] of [[paie, 'Envoyer en revue'], [approbateur, 'Approuver la paie'], [paie, 'Valider la paie'], [paie, 'Marquer comme payée'], [admin, 'Clôturer la période']] as const) {
      const r = await govStep(page, label)
      if (r) refus.push(`${label}: ${r}`)
    }
  }
  expect.soft(await etat(), refus.join(' | ')).toBe('Clôturée')

  // 4. le bulletin du sortant porte la retenue de prorata
  const n = (await prorata()).length
  record('UC-RECALCUL-PRORATA', n === 1 ? 'VERT' : 'ROUGE', `ligne RET_PRORATA du bulletin d'octobre de ${SORTANT} : ${n}`)
  expect(n).toBe(1)
})
