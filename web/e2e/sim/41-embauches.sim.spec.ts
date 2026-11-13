import { test, expect, type Page } from '@playwright/test'
import { as, field, record, rows, makeEmployee, SECTORS } from './sim-helpers'
import { capture } from './helpers/capture'

// Bloc B — embauche par type de contrat (CDD, stage, prestation, journalier), RIB, certificat de travail. Données fictives (matricules attribués par l'application).
test.describe.configure({ mode: 'serial' })

async function choisir(page: Page, label: string, texte: string) {
  const sel = field(page, label)
  const opt = (await sel.locator('option', { hasText: texte }).first().innerText()).trim()
  await sel.selectOption({ label: opt })
}

const TYPES: [code: string, libelle: string, nom: string][] = [
  ['CDD', 'CDD', 'embauche-cdd'], ['STAGE', 'Stage', 'embauche-stage'], ['PRESTATION', 'Prestation', 'embauche-prestation'], ['COD', 'journalier', 'embauche-journalier'],
]

for (const [i, [code, libelle, nom]] of TYPES.entries()) {
  test(`B · embauche ${code}`, async ({ browser }) => {
    const rh = await as(browser, 'rh')
    const deja = await rows<{ employment_type: string }>(rh, `employees?select=employment_type&first_name=eq.Sim${code}`)
    if (deja.length) {
      record(`UC-B-EMBAUCHE-${code}`, deja[0].employment_type === code ? 'VERT' : 'ROUGE', "déjà créé lors d'une exécution précédente")
      return
    }
    const e = makeEmployee(5000 + i, SECTORS[0], '2026-11-02')
    await rh.goto('/salaries/nouveau')
    await rh.getByRole('button', { name: 'Saisie complète' }).click()
    await field(rh, 'Sexe').selectOption(e.sex)
    await field(rh, 'Prénom').fill(`Sim${code}`)
    await field(rh, 'Nom').fill(e.ln)
    await field(rh, 'Date de naissance').fill(e.dob)
    await field(rh, 'Nationalité').fill('sénégalaise')
    await field(rh, 'N° CNI ou passeport').fill(e.cni) // obligatoire et unique
    await choisir(rh, 'Emploi', 'Vendeur')
    await choisir(rh, 'Type de contrat', libelle)
    await choisir(rh, 'Convention collective', e.ag)
    await field(rh, 'Catégorie').selectOption({ index: 3 })
    await field(rh, "Date d'entrée").fill('2026-11-02')
    await choisir(rh, 'Mode de paiement', 'Virement')
    await capture(rh, nom)
    await rh.getByRole('button', { name: 'Créer le salarié' }).click()
    const ok = rh.waitForURL(/\/salaries\/[0-9a-f-]{36}$/, { timeout: 15_000 }).then(() => true, () => false)
    const alerte = rh.getByRole('alert').first()
    const cree = await ok
    if (!cree) {
      const msg = ((await alerte.innerText().catch(() => '')) || 'aucune création, aucun message').trim().slice(0, 300)
      await capture(rh, `${nom}-refus`)
      record(`UC-B-EMBAUCHE-${code}`, 'ORANGE', `refus : ${msg}`)
      test.info().annotations.push({ type: 'orange', description: msg })
      return
    }
    await expect(rh.getByRole('heading', { name: 'Structure salariale' })).toBeVisible({ timeout: 20_000 })
    const [row] = await rows<{ employment_type: string }>(rh, `employees?select=employment_type&first_name=eq.Sim${code}`)
    record(`UC-B-EMBAUCHE-${code}`, row?.employment_type === code ? 'VERT' : 'ROUGE', `type enregistré : ${row?.employment_type}`)
    expect(row?.employment_type).toBe(code)
  })
}

test('B · RIB et certificat de travail', async ({ browser }) => {
  const rh = await as(browser, 'rh')
  const [e] = await rows<{ id: string }>(rh, 'employees?select=id&employee_number=eq.S0729')
  await rh.goto(`/salaries/${e.id}`)
  await field(rh, 'RIB').fill('SN08 SN010 01234 00000000001 25')
  await rh.getByRole('button', { name: 'Enregistrer la fiche' }).click()
  await expect(rh.getByText('Fiche enregistrée')).toBeVisible({ timeout: 10_000 })
  await capture(rh, 'salarie-rib-enregistre')
  record('UC-B-RIB', 'VERT', 'RIB enregistré sur la fiche')
})

// Le bouton « Certificat de travail » n'existe que pour un salarié sorti (statut Left + date de sortie) : on sort le stagiaire d'essai.
test('B · sortie du stagiaire puis certificat de travail', async ({ browser }) => {
  const rh = await as(browser, 'rh')
  const [e] = await rows<{ id: string }>(rh, 'employees?select=id&first_name=eq.SimSTAGE')
  await rh.goto(`/salaries/${e.id}`)
  await expect(rh.getByRole('heading', { name: 'Structure salariale' })).toBeVisible({ timeout: 20_000 })
  await field(rh, 'Date de sortie').fill('2026-11-10')
  await choisir(rh, 'Motif de sortie', 'Fin')
  await choisir(rh, 'État', 'Sorti') // la date de sortie ne change pas l'état toute seule (constaté au 12/11/2026)
  await capture(rh, 'salarie-sortie-saisie')
  await rh.getByRole('button', { name: 'Enregistrer la fiche' }).click()
  await expect(rh.getByText('Fiche enregistrée')).toBeVisible({ timeout: 10_000 })
  const [s] = await rows<{ status: string }>(rh, `employees?select=status&id=eq.${e.id}`)
  const btn = rh.getByRole('button', { name: 'Certificat de travail' })
  if (!(await btn.isVisible({ timeout: 5000 }).catch(() => false))) {
    record('UC-B-CERTIFICAT', 'ORANGE', `bouton absent après une sortie au 10/11/2026 (statut ${s?.status})`)
    return
  }
  await btn.click()
  await expect(rh.getByRole('dialog')).toBeVisible()
  await capture(rh, 'salarie-certificat-de-travail')
  record('UC-B-CERTIFICAT', 'VERT', `certificat affiché, statut ${s?.status}`)
})
