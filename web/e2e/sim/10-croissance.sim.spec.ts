import { test, expect } from '@playwright/test'
import { as, assignStructure, healStructures, count, createAndCalculate, createEmployeeUI, field, govStep, makeEmployee, record, rows, SECTORS, shot } from './sim-helpers'

// Paliers 5 à 9 : de 75 à 200 salariés, un mois de paie par palier, avec séparation des tâches réelle.
// Reprise : chaque palier ne crée que les salariés manquants et saute un mois déjà clôturé.
const PALIERS = [
  { n: 5, ym: '2026-05', cible: 100 },
  { n: 6, ym: '2026-06', cible: 125 },
  { n: 7, ym: '2026-07', cible: 150 },
  { n: 8, ym: '2026-08', cible: 175 },
  { n: 9, ym: '2026-09', cible: 200 },
]

test.describe.configure({ mode: 'serial' })

for (const p of PALIERS) {
  test(`palier ${p.n} — ${p.ym}, ${p.cible} salariés`, async ({ browser }) => {
    const rh = await as(browser, 'rh')
    const paie = await as(browser, 'paie')
    const approbateur = await as(browser, 'paie2') // RPR-02 : approuvent l'administrateur et le rôle paie (pas rh)
    const admin = await as(browser, 'admin')
    const doj = `${p.ym}-01`

    // 0. Reprise : compléter les structures manquantes d'une exécution interrompue
    await healStructures(paie)

    // 1. Embauches par l'interface (compte RH)
    const avant = await count(rh, 'employees')
    const manquants = Math.max(0, p.cible - avant)
    for (let k = 0; k < manquants; k++) {
      const i = 1000 + p.n * 100 + k
      const emp = makeEmployee(i, SECTORS[i % SECTORS.length], doj)
      const url = await createEmployeeUI(rh, emp, false) // le RH crée la fiche et la déclaration d'embauche
      await paie.goto(url) // la paie affecte la structure salariale
      await assignStructure(paie, doj)
    }
    record(`UC-EMB-P${p.n}`, (await count(rh, 'employees')) >= p.cible ? 'VERT' : 'ROUGE', `${manquants} embauches créées par le compte RH`)
    await shot(rh, `palier-${p.n}-liste-salaries`)

    // Reprise : si le traitement du mois existe déjà (calculé lors d'une exécution précédente), on passe directement au workflow
    const existant = await rows<{ status: string }>(admin, `payroll_entries?select=status&period_start=eq.${p.ym}-01&status=neq.Annulée`)
    if (existant.length === 0) {
      // 2. Variables du mois saisies par le compte paie (heures supplémentaires et absence sur 3 salariés)
      await paie.goto('/paie/variables', { waitUntil: 'domcontentloaded', timeout: 120_000 })
      await field(paie, 'Mois de paie').fill(p.ym)
      await paie.waitForTimeout(1500)
      const lignes = paie.locator('tbody tr')
      const nb = await lignes.count()
      const ligne = (i: number) => lignes.nth(Math.min(i, nb - 1)).locator('input')
      await ligne(2).nth(4).fill('8') // HS 15 %
      await ligne(5).nth(0).fill('16') // heures d'absence
      await ligne(8).nth(10).fill('30000') // prime de performance
      const btnSave = paie.getByRole('button', { name: /Enregistrer/ })
      // Bouton désactivé = rien à enregistrer (valeurs déjà sauvegardées lors d'un run précédent)
      if (await btnSave.isEnabled()) {
        await btnSave.click()
        await expect(paie.getByText(/enregistrées/)).toBeVisible({ timeout: 60_000 })
      }
      await shot(paie, `palier-${p.n}-variables`)

      // 3. Calcul par le compte paie
      const calc = await createAndCalculate(paie, p.ym)
      record(`UC-CALC-P${p.n}`, new RegExp(`${p.cible} bulletin`).test(calc) ? 'VERT' : 'ROUGE', calc)
      await shot(paie, `palier-${p.n}-calcul`)

    }

    // 4. Séparation des tâches : paie envoie en revue, paie2 approuve (RPR-02 : l'approbation revient au rôle paie ou à l'admin, pas à rh), paie valide et paye, admin clôture
    const refus: string[] = []
    for (const [page, label] of [[paie, 'Envoyer en revue'], [approbateur, 'Approuver la paie'], [paie, 'Valider la paie'], [paie, 'Marquer comme payée'], [admin, 'Clôturer la période']] as const) {
      const r = await govStep(page, label)
      if (r) refus.push(`${label}: ${r}`)
    }
    await shot(admin, `palier-${p.n}-gouvernance`)
    const etat = (await rows<{ status: string }>(admin, `payroll_entries?select=status&period_start=eq.${p.ym}-01`))[0]?.status
    record(`UC-WORKFLOW-P${p.n}`, etat === 'Clôturée' ? 'VERT' : 'ROUGE', refus.length ? refus.join(' | ') : `état ${etat}`)
    expect.soft(etat, refus.join(' | ')).toBe('Clôturée')
  })
}
