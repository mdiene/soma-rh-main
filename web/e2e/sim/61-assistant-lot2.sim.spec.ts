import { test, expect, type Page } from '@playwright/test'
import { as, record, rows } from './sim-helpers'
import { capture } from './helpers/capture'

// Assistant de création, lot 2 : doublons, brouillon dans le navigateur, plein écran sur téléphone, parts, alerte « structure à affecter » pour la paie.
test.describe.configure({ mode: 'serial' })

const SUFFIX = String(Date.now()).slice(-6)
const dlgOf = (p: Page) => p.getByRole('dialog', { name: /assistant de saisie/ })
const next = (p: Page) => dlgOf(p).getByRole('button', { name: 'Valider et continuer' }).click()
async function openWizard(p: Page) {
  await p.goto('/salaries/nouveau')
  await p.getByRole('button', { name: 'Avec l’assistant' }).click()
  await expect(dlgOf(p)).toBeVisible()
}

test('doublons : un homonyme existant est signalé sans bloquer', async ({ browser }) => {
  const p = await as(browser, 'rh')
  const [e] = await rows<{ first_name: string; last_name: string; date_of_birth: string; employee_number: string }>(p, 'employees?select=first_name,last_name,date_of_birth,employee_number&employee_number=eq.S0728')
  await openWizard(p)
  const d = dlgOf(p)
  await d.getByLabel('Prénom', { exact: true }).fill(e.first_name)
  await d.getByLabel('Nom', { exact: true }).fill(e.last_name)
  await d.getByLabel('Date de naissance').fill(e.date_of_birth)
  const note = d.getByText('Un salarié semble déjà exister :')
  await expect(note).toBeVisible({ timeout: 15_000 })
  await expect(d.getByText(new RegExp(e.employee_number)).first()).toBeVisible()
  await capture(p, 'assistant-doublon')
  await next(p) // avertissement, jamais bloquant
  await expect(d.getByRole('heading', { name: /Coordonnées/ })).toBeVisible()
  record('UC-B-ASSISTANT-DOUBLON', 'VERT', `homonyme ${e.employee_number} signalé, saisie non bloquée`)
})

test('brouillon : la croix garde la saisie, la reprise restaure l\'étape, l\'abandon l\'efface', async ({ browser }) => {
  const p = await as(browser, 'rh')
  await openWizard(p)
  const d = dlgOf(p)
  await d.getByLabel('Prénom', { exact: true }).fill('Brouillon')
  await d.getByLabel('Nom', { exact: true }).fill(`Test${SUFFIX}`)
  await next(p)
  await expect(d.getByRole('heading', { name: /Coordonnées/ })).toBeVisible()
  await p.waitForTimeout(900) // sauvegarde différée
  await d.getByRole('button', { name: 'Fermer' }).click()
  await expect(d).toBeHidden()
  await p.reload()
  await p.getByRole('button', { name: 'Avec l’assistant' }).click()
  await expect(d.getByText(/Un brouillon du .* est disponible/)).toBeVisible()
  await capture(p, 'assistant-brouillon')
  await d.getByRole('button', { name: 'Reprendre' }).click()
  await expect(d.getByRole('heading', { name: /Coordonnées/ })).toBeVisible()
  await d.getByRole('button', { name: 'Précédent' }).click()
  await expect(d.getByLabel('Prénom', { exact: true })).toHaveValue('Brouillon')
  // abandon : confirmation puis brouillon effacé
  await d.getByRole('button', { name: 'Annuler' }).click()
  await d.getByRole('button', { name: 'Abandonner' }).click()
  await expect(d).toBeHidden()
  await p.reload()
  await p.getByRole('button', { name: 'Avec l’assistant' }).click()
  await expect(d.getByLabel('Prénom', { exact: true })).toBeVisible()
  await expect(d.getByText(/Un brouillon du/)).toHaveCount(0)
  record('UC-B-ASSISTANT-BROUILLON', 'VERT', 'brouillon conservé, repris à la bonne étape, effacé à l\'abandon')
})

test('parts : aucune proposition tant que la règle n\'est pas définie', async ({ browser }) => {
  const p = await as(browser, 'rh')
  await openWizard(p)
  const d = dlgOf(p)
  await d.getByLabel('Prénom', { exact: true }).fill('Parts')
  await d.getByLabel('Nom', { exact: true }).fill(`Test${SUFFIX}`)
  await next(p)
  await next(p)
  await expect(d.getByRole('heading', { name: /Famille et fiscalité/ })).toBeVisible()
  await expect(d.getByText(/calcul automatique des parts n’est pas encore défini/)).toBeVisible()
  await capture(p, 'assistant-famille-parts')
  await d.getByRole('button', { name: 'Annuler' }).click()
  await d.getByRole('button', { name: 'Abandonner' }).click()
  record('UC-B-ASSISTANT-PARTS', 'VERT', 'note affichée : règle des parts non définie, saisie manuelle')
})

test('plein écran sur téléphone : la fenêtre occupe l\'écran et le pied de page reste visible', async ({ browser }) => {
  const p = await as(browser, 'rh')
  await p.setViewportSize({ width: 390, height: 800 })
  await p.goto('/salaries/nouveau')
  await p.getByRole('button', { name: 'Avec l’assistant' }).click()
  const d = dlgOf(p)
  await expect(d).toBeVisible()
  const box = await d.boundingBox()
  expect(box!.width).toBeGreaterThanOrEqual(388)
  expect(box!.x).toBeLessThanOrEqual(1)
  await expect(d.getByRole('button', { name: 'Valider et continuer' })).toBeInViewport()
  await p.screenshot({ path: '../docs/guide-utilisateur/captures/assistant-plein-ecran-telephone.png' })
  await d.getByRole('button', { name: 'Annuler' }).click()
  await d.getByRole('button', { name: 'Abandonner' }).click()
  record('UC-B-ASSISTANT-MOBILE', 'VERT', 'fenêtre en plein écran à 390 px, boutons visibles')
})

test('alerte pour la paie : le salarié créé sans structure apparaît sur le tableau de bord', async ({ browser }) => {
  const paie = await as(browser, 'paie')
  await paie.goto('/')
  await expect(paie.getByText(/Structure salariale à affecter par la paie/).first()).toBeVisible({ timeout: 20_000 })
  await capture(paie, 'tableau-de-bord-structure-a-affecter')
  record('UC-E-ALERTE-STRUCTURE', 'VERT', 'alerte « structure à affecter » visible pour le compte paie')
})
