import { execFileSync } from 'node:child_process'
import { test, expect, type Page } from '@playwright/test'
import { as, createAndCalculate, field, govStep, record, rows } from './sim-helpers'

// Parcours Playwright des fiches RPR (docs/recette/PROMPT_REPRISE_2026-11-11.md, étape 2).
// Crée la paie de novembre 2026 (aucune paie clôturée n'est touchée), joue RPR-01, 02, 04, 12, puis la SUPPRIME.
// RPR-06, 10 et 14 passent par les écrans de fiche et de paramètres ; le département de test est supprimé.
test.describe.configure({ mode: 'serial' })

const MOIS = '2026-11'
const psql = (sql: string) =>
  execFileSync('docker', ['exec', 'soma-rh-local-postgres-1', 'psql', '-U', 'soma', '-d', 'soma_rh', '-tAc', sql], { encoding: 'utf8' }).trim()

let admin: Page, rh: Page, paie: Page, paie2: Page
let entryId = ''

async function supprimerNovembre(page: Page) {
  const e = (await rows<{ id: string }>(page, `payroll_entries?select=id&period_start=eq.${MOIS}-01`))[0]
  if (!e) return
  await page.goto(`/paie/${e.id}`)
  // une paie en revue ou approuvée ne se supprime qu'après retour à « Calculée », avec motif (règle de la base)
  const retour = page.getByRole('button', { name: 'Remettre en Calculée', exact: true })
  if (await retour.waitFor({ state: 'visible', timeout: 8000 }).then(() => true, () => false)) {
    await retour.click()
    const r = page.getByRole('dialog')
    await r.getByLabel(/Motif/).fill('Nettoyage de la paie d’essai de novembre 2026')
    await r.getByRole('button', { name: 'Remettre en Calculée', exact: true }).click()
    await expect(r).toHaveCount(0, { timeout: 60_000 })
  }
  await page.getByRole('button', { name: 'Supprimer', exact: true }).click()
  const dlg = page.getByRole('dialog')
  await dlg.getByLabel(/Je confirme la suppression/).check()
  await dlg.getByRole('button', { name: 'Supprimer définitivement' }).click()
  await expect(page.getByRole('dialog')).toHaveCount(0, { timeout: 90_000 }) // le dialogue se ferme une fois la paie supprimée
  await expect(page).toHaveURL(/\/paie$/)
}

test.beforeAll(async ({ browser }) => {
  admin = await as(browser, 'admin')
  rh = await as(browser, 'rh')
  paie = await as(browser, 'paie')
  paie2 = await as(browser, 'paie2')
  await supprimerNovembre(admin) // reste d'une exécution interrompue
})

test.afterAll(async () => {
  if (admin) await supprimerNovembre(admin) // nettoyage : la paie de novembre n'existe plus
})

test('RPR-01 / RPR-12 : paie incomplète signalée, envoi en revue refusé avec la liste des salariés', async () => {
  const annonce = await createAndCalculate(paie, MOIS)
  entryId = paie.url().split('/').pop()!
  record('UC-NOVEMBRE-CALCUL', 'VERT', `paie de novembre créée pour les parcours RPR : ${annonce}`)

  // un bulletin devient « Annulé » : le salarié est attendu mais n'a plus de bulletin
  const cible = psql(`select s.id||'|'||s.employee_number||'|'||s.status from salary_slips s where s.payroll_entry_id='${entryId}' and s.status<>'Annulé' order by s.employee_number limit 1`).split('|')
  const [slipId, matricule, ancien] = cible
  psql(`update salary_slips set status='Annulé' where id='${slipId}'`)
  try {
    await paie.goto(`/paie/${entryId}`)
    await expect(paie.getByRole('alert').filter({ hasText: /sans bulletin/ }), 'RPR-01 : pas de bandeau de paie incomplète').toContainText(matricule, { timeout: 20_000 })

    await paie.goto('/paie/gouvernance')
    await paie.waitForLoadState('networkidle')
    await paie.getByRole('button', { name: 'Envoyer en revue', exact: true }).first().click()
    // RPR-12 : avertissement avant l'envoi, avec le salarié concerné ; puis refus de la base, avec la même liste
    const avert = paie.getByRole('dialog')
    await expect(avert, 'RPR-12 : pas d’avertissement avant l’envoi').toContainText(matricule, { timeout: 15_000 })
    await paie.getByRole('button', { name: 'Envoyer en revue quand même' }).click()
    const refus = paie.getByRole('alert').filter({ hasText: matricule })
    await expect(refus, 'RPR-01/12 : refus sans la liste des salariés').toBeVisible({ timeout: 15_000 })
    record('UC-RPR-01', 'VERT', `bandeau et refus d'envoi en revue citant ${matricule}`)
  } finally {
    psql(`update salary_slips set status='${ancien}' where id='${slipId}'`)
  }
})

test('RPR-04 : la validation sans revue exige un motif', async () => {
  await admin.goto(`/paie/${entryId}`)
  await admin.getByRole('button', { name: 'Valider la paie', exact: true }).click()
  const dlg = admin.getByRole('dialog')
  await expect(dlg.getByLabel(/Motif de la dérogation/)).toHaveValue('')
  await expect(dlg.getByRole('button', { name: /^Valider \d+ bulletin/ })).toBeDisabled()
  await dlg.getByLabel(/Motif de la dérogation/).fill('essai')
  await expect(dlg.getByRole('button', { name: /^Valider \d+ bulletin/ })).toBeEnabled()
  await dlg.getByRole('button', { name: 'Revenir' }).click() // aucune validation
  record('UC-RPR-04', 'VERT', 'motif obligatoire, bouton désactivé tant que le champ est vide')
})

test('RPR-02 : approbation par un compte paie distinct ; refus de rh et de la même personne', async () => {
  const revue = await govStep(paie, 'Envoyer en revue')
  expect(revue, `envoi en revue : ${revue}`).toBeNull()

  const parRh = await govStep(rh, 'Approuver la paie')
  expect(parRh, 'le rôle rh ne doit pas pouvoir approuver').toMatch(/absent|refus|droits/i)

  const memePersonne = await govStep(paie, 'Approuver la paie')
  expect(memePersonne, 'la personne qui a préparé la paie ne doit pas pouvoir l’approuver').toMatch(/refus|séparation|préparé|même/i)

  const distinct = await govStep(paie2, 'Approuver la paie')
  expect(distinct, `approbation par paie2 : ${distinct}`).toBeNull()
  const statut = (await rows<{ status: string }>(admin, `payroll_entries?select=status&id=eq.${entryId}`))[0].status
  expect(statut).toBe('Approuvée')
  record('UC-RPR-02', 'VERT', 'approuvée par paie2 ; refus de rh et de la personne qui a préparé')
})

test('RPR-06 : rh voit la structure salariale en lecture seule', async () => {
  const emp = (await rows<{ id: string }>(rh, 'employees?select=id&limit=1'))[0]
  await rh.goto(`/salaries/${emp.id}`)
  await expect(rh.getByRole('note').filter({ hasText: 'Lecture seule : la structure salariale' })).toBeVisible({ timeout: 20_000 })
  record('UC-RPR-06', 'VERT', 'message de lecture seule pour rh')
})

test('RPR-10 : département créé, proposé sur la fiche, puis supprimé', async () => {
  const nom = 'ZZ Test RPR-10'
  await rh.goto('/parametres?onglet=referentiels')
  await field(rh, 'Nom du département').fill(nom)
  await rh.getByRole('button', { name: 'Ajouter' }).last().click()
  await expect(rh.getByRole('cell', { name: nom, exact: true })).toBeVisible()
  try {
    const emp = (await rows<{ id: string }>(rh, 'employees?select=id&limit=1'))[0]
    await rh.goto(`/salaries/${emp.id}`)
    await expect(field(rh, 'Département').locator('option', { hasText: nom })).toHaveCount(1, { timeout: 20_000 })
  } finally {
    await rh.goto('/parametres?onglet=referentiels')
    await rh.getByRole('button', { name: `Supprimer ${nom}` }).click()
    await expect(rh.getByRole('cell', { name: nom, exact: true })).toHaveCount(0)
  }
  record('UC-RPR-10', 'VERT', 'département créé, visible sur la fiche, supprimé')
})

test('RPR-14 : numérotation des matricules (modifiable par l’admin, lecture par rh)', async () => {
  await admin.goto('/parametres?onglet=societe')
  await expect(field(admin, 'Préfixe')).toBeEnabled({ timeout: 20_000 })
  await expect(admin.getByText(/Prochain matricule : S\d{4}/)).toBeVisible()
  await rh.goto('/parametres?onglet=societe')
  await expect(field(rh, 'Préfixe')).toBeDisabled({ timeout: 20_000 })
  record('UC-RPR-14', 'VERT', 'préfixe et chiffres paramétrables par l’admin, désactivés pour rh')
})
