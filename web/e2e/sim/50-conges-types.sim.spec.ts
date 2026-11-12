import { test, expect, type Page } from '@playwright/test'
import { as, field, record, rows } from './sim-helpers'
import { capture } from './helpers/capture'

// Campagne 2 — bloc D : maladie, maternité, permission exceptionnelle, absence non payée (salarié sim-sal-1 = S0728, manager sim-mgr-1, puis RH).
test.describe.configure({ mode: 'serial' })

const CAS: [libelle: string, du: string, au: string, nom: string, uc: string][] = [
  ['Congé maladie', '2026-11-16', '2026-11-17', 'conge-maladie', 'UC-D-MALADIE'],
  ['Permission exceptionnelle', '2026-11-23', '2026-11-24', 'conge-permission-exceptionnelle', 'UC-D-PERMISSION'],
  ['Absence non payée', '2026-11-26', '2026-11-26', 'conge-absence-non-payee', 'UC-D-ABSENCE-NON-PAYEE'],
  ['Congé de maternité', '2027-01-04', '2027-01-08', 'conge-maternite', 'UC-D-MATERNITE'],
]

async function approuver(page: Page, route: string) {
  await page.goto(route)
  await page.waitForLoadState('networkidle')
  const b = page.getByRole('button', { name: 'Approuver' }).first()
  if (!(await b.isVisible().catch(() => false))) return false
  await b.click()
  await page.waitForTimeout(1500)
  return true
}

for (const [libelle, du, au, nom, uc] of CAS) {
  test(`D · ${libelle}`, async ({ browser }) => {
    const rh = await as(browser, 'rh')
    const sal = await as(browser, 'sal_1')
    const mgr = await as(browser, 'mgr_1')
    const [e] = await rows<{ id: string }>(rh, 'employees?select=id&employee_number=eq.S0728')
    let appli = await rows<{ id: string; status: string }>(rh, `leave_applications?select=id,status&employee_id=eq.${e.id}&from_date=eq.${du}`)
    let message = ''
    if (appli.length === 0) {
      await sal.goto('/conges')
      await sal.getByRole('button', { name: 'Nouvelle demande', exact: true }).click()
      await field(sal, 'Type de congé').selectOption({ label: libelle })
      await field(sal, 'Du').fill(du)
      await field(sal, 'Au (inclus)').fill(au)
      await field(sal, 'Motif').fill('Simulation campagne 2')
      await capture(sal, nom)
      await sal.getByRole('button', { name: 'Envoyer la demande' }).click()
      await sal.waitForTimeout(2000)
      message = (await sal.getByRole('alert').first().innerText().catch(() => '')).trim().slice(0, 250)
      appli = await rows(rh, `leave_applications?select=id,status&employee_id=eq.${e.id}&from_date=eq.${du}`)
    }
    if (appli.length === 0) {
      await capture(sal, `${nom}-refus`)
      record(uc, 'ORANGE', `demande refusée : ${message || 'aucun message'}`)
      return
    }
    await approuver(mgr, '/mon-equipe')
    await approuver(rh, '/conges')
    const [fin] = await rows<{ status: string }>(rh, `leave_applications?select=status&id=eq.${appli[0].id}`)
    record(uc, /approuv/i.test(fin.status) ? 'VERT' : 'ORANGE', `état final : ${fin.status}`)
    expect(fin.status).toBeTruthy()
  })
}

test('D · soldes et écritures (RH)', async ({ browser }) => {
  const rh = await as(browser, 'rh')
  await rh.goto('/conges')
  await rh.getByRole('tab', { name: 'Soldes' }).click()
  await rh.waitForLoadState('networkidle')
  await capture(rh, 'conges-soldes')
  await rh.getByRole('tab', { name: 'Écritures' }).click()
  await rh.waitForLoadState('networkidle')
  await capture(rh, 'conges-ecritures')
  record('UC-D-SOLDES-ECRITURES', 'VERT', 'onglets Soldes et Écritures affichés')
})
