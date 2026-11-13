import { execFileSync } from 'node:child_process'
import { test, expect, type Page } from '@playwright/test'
import { as, record } from './sim-helpers'

// Assistant de saisie : noms mis en forme, nom de jeune fille, mère, n° de CNI/passeport unique, mise en attente et reprise.
// Modifie la base (brouillon et salarié synthétiques) : tout est supprimé à la fin.
test.describe.configure({ mode: 'serial' })

const SUFFIX = String(Date.now()).slice(-6)
const CNI = `E2E-CNI-${SUFFIX}`
const CNI_EXISTANT = `E2E-DUP-${SUFFIX}`
const psql = (sql: string) =>
  execFileSync('docker', ['exec', 'soma-rh-local-postgres-1', 'psql', '-U', 'soma', '-d', 'soma_rh', '-tAc', sql], { encoding: 'utf8' }).trim()
const dlgOf = (p: Page) => p.getByRole('dialog', { name: /assistant de saisie/ })
const nettoyer = () => {
  psql(`delete from public.employee_drafts where data->'draft'->>'id_document_number' = '${CNI}'`)
  psql(`delete from public.employees where id_document_number in ('${CNI_EXISTANT}', '${CNI}')`)
}

test.beforeAll(() => {
  nettoyer()
  const company = psql('select id from public.companies order by created_at limit 1')
  psql(`insert into public.employees (company_id, employee_number, first_name, last_name, employment_type, date_of_joining, id_document_number) values ('${company}', '', 'Existant', 'E2e', 'CDI', '2020-01-01', '${CNI_EXISTANT}')`)
})
test.afterAll(() => nettoyer())

test('identité : noms mis en forme, nom de jeune fille pour les femmes, prénom et nom de la mère', async ({ browser }) => {
  const p = await as(browser, 'rh')
  await p.goto('/salaries/nouveau')
  await p.getByRole('button', { name: 'Avec l’assistant' }).click()
  const d = dlgOf(p)
  await expect(d).toBeVisible()
  await expect(d.getByLabel('Nom de jeune fille')).toHaveCount(0) // seulement pour les femmes
  await d.getByLabel('Sexe').selectOption('F')
  await expect(d.getByLabel('Nom de jeune fille')).toBeVisible()
  await d.getByLabel('Prénom', { exact: true }).fill('  MAME   fatou ')
  await d.getByLabel('Nom', { exact: true }).fill("n'DIAYE-sow")
  await d.getByLabel('Nom de jeune fille').fill('ba')
  await d.getByLabel('Prénom de la mère', { exact: true }).fill('KHADY')
  await d.getByLabel('Nom de la mère', { exact: true }).fill('fall')
  await d.getByLabel(/^N° CNI ou passeport/).fill(CNI)
  await d.getByLabel('Date de naissance').click() // sortie des champs : mise en forme
  await expect(d.getByLabel('Prénom', { exact: true })).toHaveValue('Mame Fatou')
  await expect(d.getByLabel('Nom', { exact: true })).toHaveValue("N'Diaye-Sow")
  await expect(d.getByLabel('Nom de jeune fille')).toHaveValue('Ba')
  await expect(d.getByLabel('Prénom de la mère', { exact: true })).toHaveValue('Khady')
  await expect(d.getByLabel('Nom de la mère', { exact: true })).toHaveValue('Fall')
  record('UC-SAISIE-NOMS', 'VERT', 'Prénom et Nom mis en forme, nom de jeune fille (F), prénom et nom de la mère')
})

test('n° de CNI ou passeport : obligatoire et déjà attribué refusé (espaces et casse ignorés)', async ({ browser }) => {
  const p = await as(browser, 'rh')
  await p.goto('/salaries/nouveau')
  await p.getByRole('button', { name: 'Avec l’assistant' }).click()
  const d = dlgOf(p)
  await d.getByLabel('Prénom', { exact: true }).fill('Doublon')
  await d.getByLabel('Nom', { exact: true }).fill('Test')
  await d.getByRole('button', { name: 'Valider et continuer' }).click()
  await expect(d.getByRole('alert').filter({ hasText: /CNI ou de passeport est obligatoire/ })).toBeVisible()
  await d.getByLabel(/^N° CNI ou passeport/).fill(` ${CNI_EXISTANT.toLowerCase().replace('-', ' - ')} `)
  await expect(d.getByRole('alert').filter({ hasText: /déjà attribué au salarié/ })).toBeVisible({ timeout: 15_000 })
  await d.getByRole('button', { name: 'Valider et continuer' }).click()
  await expect(d.getByRole('heading', { name: /1\. Identité/ })).toBeVisible() // bloqué à l'étape Identité
  await d.getByRole('button', { name: 'Annuler' }).click()
  await d.getByRole('button', { name: 'Abandonner' }).click()
  record('UC-SAISIE-CNI', 'VERT', 'n° de pièce obligatoire ; doublon refusé à l’écran')
})

test('mise en attente, liste des saisies en cours avec avancement et points manquants, reprise', async ({ browser }) => {
  const p = await as(browser, 'rh')
  await p.goto('/salaries/nouveau')
  await p.getByRole('button', { name: 'Avec l’assistant' }).click()
  const d = dlgOf(p)
  await d.getByLabel('Sexe').selectOption('F')
  await d.getByLabel('Prénom', { exact: true }).fill('mame fatou')
  await d.getByLabel('Nom', { exact: true }).fill("n'diaye-sow")
  await d.getByLabel(/^N° CNI ou passeport/).fill(CNI)
  await d.getByRole('button', { name: 'Mettre en attente' }).click()
  await expect(p).toHaveURL(/\/salaries\/en-cours$/)

  const carte = p.getByRole('listitem').filter({ hasText: "Mame Fatou N'Diaye-Sow" })
  await expect(carte).toBeVisible({ timeout: 15_000 })
  const pct = Number(await carte.getByRole('progressbar').getAttribute('aria-valuenow'))
  expect(pct, 'avancement partiel').toBeGreaterThan(0)
  expect(pct).toBeLessThan(100)
  await expect(carte.getByText('Points à déterminer')).toBeVisible()
  await expect(carte.getByText(/Contrat et classification/).first()).toBeVisible() // un point manquant d'une autre étape

  await carte.getByRole('link', { name: 'Continuer la saisie' }).click()
  const reprise = dlgOf(p)
  await expect(reprise).toBeVisible()
  await expect(reprise.getByLabel('Prénom', { exact: true })).toHaveValue('Mame Fatou')
  await expect(reprise.getByLabel(/^N° CNI ou passeport/)).toHaveValue(CNI)
  await reprise.getByRole('button', { name: 'Annuler' }).click()
  await reprise.getByRole('button', { name: 'Abandonner' }).click()
  // la saisie reste en attente tant qu'elle n'est pas supprimée ou terminée
  await p.goto('/salaries/en-cours')
  await expect(p.getByRole('listitem').filter({ hasText: "Mame Fatou N'Diaye-Sow" })).toBeVisible()
  record('UC-SAISIE-ATTENTE', 'VERT', 'saisie mise en attente, listée avec avancement et points manquants, reprise à l’identique')

  // suppression depuis la liste
  const c2 = p.getByRole('listitem').filter({ hasText: "Mame Fatou N'Diaye-Sow" })
  await c2.getByRole('button', { name: /Supprimer la saisie/ }).click()
  await c2.getByRole('button', { name: 'Confirmer la suppression' }).click()
  await expect(p.getByRole('listitem').filter({ hasText: "Mame Fatou N'Diaye-Sow" })).toHaveCount(0)
})
