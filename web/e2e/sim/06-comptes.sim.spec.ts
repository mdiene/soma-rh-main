import { test, expect, type Page } from '@playwright/test'
import { as, field, record, rows } from './sim-helpers'
import { capture } from './helpers/capture'

// Bloc A — relier les comptes aux fiches (admin) puis constituer l'équipe d'un manager (RH). Base remise à zéro : matricules S0724 à S0923.
test.describe.configure({ mode: 'serial' })
const LIENS: [string, string][] = [['sim-sal-1', 'S0728'], ['sim-sal-2', 'S0729'], ['sim-sal-3', 'S0730'], ['sim-mgr-1', 'S0726']]

async function choisir(sel: ReturnType<Page['locator']>, texte: string) {
  const opt = (await sel.locator('option', { hasText: texte }).first().innerText()).trim()
  await sel.selectOption({ label: opt })
}

test('A — relier les comptes sim aux fiches (Paramètres › Accès)', async ({ browser }) => {
  const admin = await as(browser, 'admin')
  await admin.goto('/parametres?onglet=acces')
  await expect(admin.getByRole('heading', { name: 'Comptes et rôles' })).toBeVisible()
  await capture(admin, 'acces-comptes-et-roles')
  for (const [compte, num] of LIENS) {
    const sel = admin.getByLabel(new RegExp(`Fiche liée à ${compte}@`))
    await choisir(sel, num)
    await expect(sel).not.toHaveValue('')
    await admin.waitForTimeout(600)
  }
  await capture(admin, 'acces-fiches-reliees')
  const liees = await rows<{ employee_number: string }>(admin, 'employees?select=employee_number&user_id=not.is.null')
  expect(liees.map((l) => l.employee_number).sort()).toEqual(expect.arrayContaining(LIENS.map(([, n]) => n)))
  record('UC-A-LIAISON-COMPTES', 'VERT', `${liees.length} comptes reliés à une fiche par l'interface`)
})

test('I — affecter deux salariés à l\'équipe du manager (Équipes et managers)', async ({ browser }) => {
  const rh = await as(browser, 'rh')
  await rh.goto('/equipes')
  await expect(rh.getByRole('heading', { name: 'Équipes et managers' })).toBeVisible()
  for (const num of ['S0728', 'S0729']) {
    await choisir(field(rh, 'Manager'), 'S0726')
    await choisir(field(rh, 'Salarié à affecter'), num)
    await field(rh, 'Début').fill('2026-01-01')
    if (num === 'S0728') await capture(rh, 'equipes-nouvelle-affectation')
    await rh.getByRole('button', { name: 'Affecter à l’équipe' }).click()
    await rh.waitForTimeout(1200)
  }
  await capture(rh, 'equipes-affectations-enregistrees')
  const n = (await rows(rh, 'employee_manager_assignments?select=id')).length
  expect(n).toBeGreaterThanOrEqual(2)
  record('UC-I-EQUIPE', 'VERT', `${n} affectation(s) manager enregistrée(s)`)
})
