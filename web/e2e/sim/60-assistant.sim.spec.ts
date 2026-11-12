import { test, expect, type Page } from '@playwright/test'
import { as, record, rows } from './sim-helpers'
import { capture } from './helpers/capture'

// Assistant de création d'un salarié : parcours complet (RH + paie, avec calcul du net), RH seul (sans rémunération), champ obligatoire, saisie complète.
test.describe.configure({ mode: 'serial' })

const SUFFIX = String(Date.now()).slice(-6)
const dlgOf = (p: Page) => p.getByRole('dialog', { name: /assistant de saisie/ })
const next = (p: Page) => dlgOf(p).getByRole('button', { name: 'Valider et continuer' }).click()

async function openWizard(p: Page) {
  await p.goto('/salaries/nouveau')
  await p.getByRole('button', { name: 'Avec l’assistant' }).click()
  await expect(dlgOf(p)).toBeVisible()
}
async function identite(p: Page, prenom: string) {
  const d = dlgOf(p)
  await d.getByLabel('Sexe').selectOption('F')
  await d.getByLabel('Prénom', { exact: true }).fill(prenom)
  await d.getByLabel('Nom', { exact: true }).fill(`Assistant${SUFFIX}`)
  await d.getByLabel('Date de naissance').fill('1990-05-12')
  await next(p)
}
async function coordonneesFamille(p: Page) {
  const d = dlgOf(p)
  await d.getByLabel('Téléphone personnel').fill('77 123 45 67')
  await next(p)
  await d.getByLabel('Situation de famille').selectOption('Célibataire')
  await next(p)
}
async function contrat(p: Page, type: string, extra = false) {
  const d = dlgOf(p)
  await d.getByLabel('Type de contrat').selectOption(type)
  await d.getByLabel('Date d\'entrée').fill('2026-12-01')
  if (extra) { await d.getByLabel('Début du contrat en cours').fill('2026-12-01'); await d.getByLabel('Fin du contrat en cours').fill('2027-05-31') }
  await d.getByLabel('Emploi').selectOption({ index: 1 })
  await d.getByLabel('Convention collective').selectOption({ index: 1 })
  await d.getByLabel('Catégorie').selectOption({ index: 1 })
}

test('RH + paie : parcours complet avec calcul du net et pièces reçues', async ({ browser }) => {
  const p = await as(browser, 'rhpaie')
  await p.goto('/salaries/nouveau')
  await capture(p, 'assistant-choix-saisie')
  await p.getByRole('button', { name: 'Avec l’assistant' }).click()
  await expect(dlgOf(p)).toBeVisible()
  await capture(p, 'assistant-identite')
  await identite(p, 'Wiz')
  await coordonneesFamille(p)
  await contrat(p, 'CDD', true)
  await capture(p, 'assistant-contrat-cdd')
  await next(p)
  await dlgOf(p).getByLabel('Mode de paiement').selectOption({ index: 1 })
  await next(p)
  await dlgOf(p).getByLabel('Référence de la déclaration d\'embauche').fill(`DPAE-${SUFFIX}`)
  await dlgOf(p).getByLabel('Date de la déclaration d\'embauche').fill('2026-11-25')
  await next(p)
  // rémunération : calcul du sursalaire à partir du net
  await expect(dlgOf(p).getByRole('heading', { name: /Rémunération/ })).toBeVisible()
  await capture(p, 'assistant-remuneration')
  await dlgOf(p).getByRole('button', { name: /Calculer le sursalaire à partir du net/ }).click()
  const calc = p.getByRole('dialog', { name: 'Calcul du salaire à partir du net' })
  await calc.getByLabel('Net à payer souhaité (F CFA)').fill('250000')
  await calc.getByRole('button', { name: 'Calculer', exact: true }).click()
  await expect(calc.getByRole('status')).toBeVisible({ timeout: 30_000 })
  await capture(p, 'assistant-calcul-net')
  await calc.getByRole('button', { name: 'Valider et reprendre dans la saisie' }).click()
  await expect(calc).toBeHidden()
  await next(p)
  // pièces : on coche la première
  await dlgOf(p).getByRole('checkbox').first().check()
  await capture(p, 'assistant-pieces')
  await next(p)
  // revue
  await expect(dlgOf(p).getByRole('heading', { name: /Revue et sauvegarde/ })).toBeVisible()
  await capture(p, 'assistant-revue')
  await dlgOf(p).getByRole('button', { name: 'Créer le salarié' }).click()
  await expect(p.getByRole('dialog', { name: 'Salarié créé' })).toBeVisible({ timeout: 30_000 })
  await capture(p, 'assistant-salarie-cree')
  const [e] = await rows<{ id: string; employee_number: string; employment_type: string }>(p, `employees?select=id,employee_number,employment_type&last_name=eq.Assistant${SUFFIX}`)
  expect(e?.employee_number).toBeTruthy()
  expect(e.employment_type).toBe('CDD')
  const aff = await rows(p, `salary_structure_assignments?select=sursalaire&employee_id=eq.${e.id}`)
  expect(aff.length).toBe(1)
  record('UC-B-ASSISTANT-COMPLET', 'VERT', `salarié ${e.employee_number} créé par l'assistant avec structure et calcul du net`)
})

test('RH seul : pas d\'étape rémunération, structure à affecter par la paie', async ({ browser }) => {
  const p = await as(browser, 'rh')
  await openWizard(p)
  await expect(dlgOf(p).getByRole('button', { name: /Rémunération/ })).toHaveCount(0)
  await identite(p, 'WizRh')
  await coordonneesFamille(p)
  await contrat(p, 'CDI')
  await next(p)
  await dlgOf(p).getByLabel('Mode de paiement').selectOption({ index: 1 })
  await next(p)
  await next(p) // déclarations (facultatives)
  await next(p) // pièces
  await capture(p, 'assistant-revue-rh-seul')
  await dlgOf(p).getByRole('button', { name: 'Créer le salarié' }).click()
  const fin = p.getByRole('dialog', { name: 'Salarié créé' })
  await expect(fin).toBeVisible({ timeout: 30_000 })
  await expect(fin.getByText(/reste à affecter par le service paie/)).toBeVisible()
  await capture(p, 'assistant-cree-sans-structure')
  record('UC-B-ASSISTANT-RH-SEUL', 'VERT', 'création sans structure, message de délégation à la paie')
})

test('champ obligatoire : le prénom bloque la validation de l\'étape', async ({ browser }) => {
  const p = await as(browser, 'rh')
  await openWizard(p)
  await next(p)
  await expect(dlgOf(p).getByRole('alert')).toContainText('Le prénom est obligatoire.')
  await capture(p, 'assistant-champ-obligatoire')
  await dlgOf(p).getByRole('button', { name: 'Annuler' }).click()
  await expect(dlgOf(p).getByText('Abandonner la saisie ?')).toBeVisible()
  await dlgOf(p).getByRole('button', { name: 'Abandonner' }).click()
  await expect(dlgOf(p)).toBeHidden()
  record('UC-B-ASSISTANT-OBLIGATOIRE', 'VERT', 'étape bloquée sans prénom ; abandon avec confirmation')
})

test('saisie complète conservée', async ({ browser }) => {
  const p = await as(browser, 'rh')
  await p.goto('/salaries/nouveau')
  await p.getByRole('button', { name: 'Saisie complète' }).click()
  await expect(p.getByLabel('Prénom', { exact: true })).toBeVisible()
  await expect(p.getByRole('button', { name: 'Utiliser l’assistant' })).toBeVisible()
  record('UC-B-SAISIE-COMPLETE', 'VERT', 'choix de la saisie complète, formulaire sur une page')
})
