import { test, expect, type Page } from '@playwright/test'
import { as, count, createAndCalculate, field, govStep, record, rows, shot } from './sim-helpers'

// Palier 10 (octobre 2026, 200 salariés) : sortie, congé, prêt, heures supplémentaires, calcul et workflow.
// Idempotent : chaque test regarde l'état en base avant d'agir. Données fictives uniquement (S0291 à S0490).
const YM = '2026-10'
const SORTANT = 'S0450' // démission, sortie le 23/10/2026
const EMPRUNTEUR = 'S0455' // prêt de 300 000 F sur 6 échéances
const CONGE_SAL = 'S0295' // sal_1 (équipe de mgr_1)

test.describe.configure({ mode: 'serial' })

async function emp(page: Page, numero: string) {
  const r = await rows<{ id: string; status: string }>(page, `employees?select=id,status&employee_number=eq.${numero}`)
  return r[0]
}

/** Choisit dans une liste l'option dont le texte contient `text` (matricule, par exemple). */
async function choisir(page: Page, label: string, text: string) {
  const sel = field(page, label)
  const opt = (await sel.locator('option', { hasText: text }).first().innerText()).trim()
  await sel.selectOption({ label: opt })
}

test('sortie — démission avec date et motif (compte RH)', async ({ browser }) => {
  const rh = await as(browser, 'rh')
  const e = await emp(rh, SORTANT)
  await rh.goto(`/salaries/${e.id}`)
  await rh.waitForLoadState('networkidle')
  const avant = (await rows<{ exit_reason: string | null }>(rh, `employees?select=exit_reason&employee_number=eq.${SORTANT}`))[0]
  if (!avant.exit_reason) {
    await field(rh, 'Date de sortie').fill('2026-10-23')
    await field(rh, 'Motif de sortie').selectOption({ label: 'Démission' })
    await shot(rh, 'sortie-avant')
    await rh.getByRole('button', { name: 'Enregistrer la fiche' }).click()
    await rh.getByText('Fiche enregistrée').waitFor({ timeout: 15_000 }).catch(() => record('UC-SORTIE-MSG', 'ORANGE', 'message « Fiche enregistrée » absent après saisie de la date de sortie'))
    await shot(rh, 'sortie-apres')
  }
  const apres = (await rows<{ status: string; exit_reason: string | null }>(rh, `employees?select=status,exit_reason&employee_number=eq.${SORTANT}`))[0]
  record('UC-SORTIE', apres.exit_reason ? 'VERT' : 'ROUGE', `statut ${apres.status}, motif ${apres.exit_reason}`)
  expect(apres.exit_reason).toBeTruthy()
})

test('congé — dotation (RH), demande (salarié), validation manager puis RH', async ({ browser }) => {
  const rh = await as(browser, 'rh')
  const sal = await as(browser, 'sal_1')
  const mgr = await as(browser, 'mgr_1')
  const e = await emp(rh, CONGE_SAL)

  const dot = await count(rh, 'leave_allocations', `&employee_id=eq.${e.id}`)
  if (dot === 0) {
    await rh.goto('/conges')
    await rh.getByRole('button', { name: 'Attribuer des jours', exact: true }).click()
    await choisir(rh, 'Salarié', CONGE_SAL)
    await field(rh, 'Type').selectOption({ label: 'Congé annuel payé' })
    await field(rh, 'Nombre de jours').fill('24')
    await field(rh, 'Valable du').fill('2026-01-01')
    await field(rh, 'Au').fill('2026-12-31')
    await shot(rh, 'conge-dotation')
    await rh.getByRole('button', { name: 'Attribuer', exact: true }).click()
    await rh.waitForTimeout(1500)
  }
  record('UC-CONGE-DOT', (await count(rh, 'leave_allocations', `&employee_id=eq.${e.id}`)) > 0 ? 'VERT' : 'ROUGE', 'dotation de 24 jours ouvrables')

  let appli = await rows<{ id: string; status: string }>(rh, `leave_applications?select=id,status&employee_id=eq.${e.id}&from_date=eq.2026-10-12`)
  if (appli.length === 0) {
    await sal.goto('/conges')
    await sal.getByRole('button', { name: 'Nouvelle demande', exact: true }).click()
    await field(sal, 'Type de congé').selectOption({ label: 'Congé annuel payé' })
    await field(sal, 'Du').fill('2026-10-12')
    await field(sal, 'Au (inclus)').fill('2026-10-14')
    await field(sal, 'Motif').fill('Congé de simulation')
    await shot(sal, 'conge-demande')
    await sal.getByRole('button', { name: 'Envoyer la demande' }).click()
    await sal.waitForTimeout(1500)
    appli = await rows(rh, `leave_applications?select=id,status&employee_id=eq.${e.id}&from_date=eq.2026-10-12`)
  }
  record('UC-CONGE-DEMANDE', appli.length > 0 ? 'VERT' : 'ROUGE', `état ${appli[0]?.status}`)
  expect(appli.length).toBeGreaterThan(0)

  for (const [page, route, role] of [[mgr, '/mon-equipe', 'manager'], [rh, '/conges', 'rh']] as const) {
    const etat = (await rows<{ status: string }>(rh, `leave_applications?select=status&id=eq.${appli[0].id}`))[0].status
    if (/approuv/i.test(etat)) break
    await page.goto(route)
    await page.waitForLoadState('networkidle')
    const bouton = page.getByRole('button', { name: 'Approuver' }).first()
    if (await bouton.isVisible().catch(() => false)) {
      await bouton.click()
      await page.waitForTimeout(1500)
      await shot(page, `conge-validation-${role}`)
    } else record(`UC-CONGE-VALID-${role.toUpperCase()}`, 'ORANGE', 'bouton Approuver introuvable pour cette demande')
  }
  const fin = (await rows<{ status: string }>(rh, `leave_applications?select=status&id=eq.${appli[0].id}`))[0].status
  record('UC-CONGE-VALIDATION', /approuv/i.test(fin) ? 'VERT' : 'ORANGE', `état final : ${fin}`)
})

test('prêt — plafond de retenue puis accord de 300 000 F sur 12 échéances (compte paie)', async ({ browser }) => {
  const paie = await as(browser, 'paie')
  const e = await emp(paie, EMPRUNTEUR)
  if ((await count(paie, 'loans', `&employee_id=eq.${e.id}`)) === 0) {
    await paie.goto('/paie/ajustements')
    await choisir(paie, 'Salarié', EMPRUNTEUR)
    await field(paie, 'Libellé').fill('Avance de simulation')
    await field(paie, 'Montant (F)').fill('300000')
    await field(paie, 'Échéances').fill('6')
    await field(paie, 'Première retenue').fill('2026-10') // champ de type « mois »
    await shot(paie, 'pret-formulaire')
    // 1re tentative : 50 000 F par mois dépasse le plafond (1/3 du brut) → refus attendu avec message explicite
    await paie.getByRole('button', { name: 'Accorder le prêt' }).click()
    const refus = paie.getByText(/Retenue mensuelle trop élevée/)
    await expect(refus).toBeVisible({ timeout: 10_000 })
    record('UC-PRET-PLAFOND', 'VERT', (await refus.innerText()).slice(0, 160))
    await shot(paie, 'pret-plafond-refus')
    // 2e tentative : 12 échéances de 25 000 F, sous le plafond
    await field(paie, 'Échéances').fill('12')
    await paie.getByRole('button', { name: 'Accorder le prêt' }).click()
    await paie.waitForTimeout(2000)
    await shot(paie, 'pret-accorde')
  }
  const n = await count(paie, 'loans', `&employee_id=eq.${e.id}`)
  record('UC-PRET', n > 0 ? 'VERT' : 'ROUGE', `${n} prêt(s) pour ${EMPRUNTEUR}`)
  expect(n).toBeGreaterThan(0)
})

test('calcul d’octobre et workflow jusqu’à la clôture', async ({ browser }) => {
  const paie = await as(browser, 'paie')
  const rhpaie = await as(browser, 'rhpaie')
  const admin = await as(browser, 'admin')
  const existant = await rows<{ status: string }>(admin, `payroll_entries?select=status&period_start=eq.${YM}-01&status=neq.Annulée`)
  if (existant.length === 0) {
    await paie.goto('/paie/variables', { waitUntil: 'domcontentloaded', timeout: 120_000 })
    await field(paie, 'Mois de paie').fill(YM)
    await paie.waitForTimeout(1500)
    const lignes = paie.locator('tbody tr')
    const nb = await lignes.count()
    const ligne = (i: number) => lignes.nth(Math.min(i, nb - 1)).locator('input')
    await ligne(3).nth(4).fill('10') // heures sup. à 15 %
    await ligne(4).nth(0).fill('8') // heures d'absence
    await ligne(7).nth(10).fill('50000') // prime de performance
    const save = paie.getByRole('button', { name: /Enregistrer/ })
    if (await save.isEnabled()) {
      await save.click()
      await expect(paie.getByText(/enregistrées/)).toBeVisible({ timeout: 60_000 })
    }
    await shot(paie, 'variables-octobre')
    const t0 = Date.now()
    const calc = await createAndCalculate(paie, YM)
    record('UC-CALC-OCT', /\d+ bulletin/.test(calc) ? 'VERT' : 'ROUGE', `${calc} en ${Math.round((Date.now() - t0) / 1000)} s`)
    await shot(paie, 'calcul-octobre')
  }
  const refus: string[] = []
  for (const [page, label] of [[paie, 'Envoyer en revue'], [rhpaie, 'Approuver la paie'], [paie, 'Valider la paie'], [paie, 'Marquer comme payée'], [admin, 'Clôturer la période']] as const) {
    const r = await govStep(page, label)
    if (r) refus.push(`${label}: ${r}`)
  }
  await shot(admin, 'gouvernance-octobre')
  const etat = (await rows<{ status: string }>(admin, `payroll_entries?select=status&period_start=eq.${YM}-01&status=neq.Annulée`))[0]?.status
  record('UC-WORKFLOW-OCT', etat === 'Clôturée' ? 'VERT' : 'ROUGE', refus.length ? refus.join(' | ') : `état ${etat}`)
  expect.soft(etat, refus.join(' | ')).toBe('Clôturée')
})
