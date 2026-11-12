import { test, expect, type Page } from '@playwright/test'
import { as, field, makeEmployee, record, rows, SECTORS } from './sim-helpers'
import { capture } from './helpers/capture'

// Campagne 2 — blocs H, B et I : demande d'un salarié traitée par la RH, embauche en apprentissage, simulation de réorganisation.
test.describe.configure({ mode: 'serial' })

async function choisir(page: Page, label: string, texte: string) {
  const sel = field(page, label)
  const opt = (await sel.locator('option', { hasText: texte }).first().innerText()).trim()
  await sel.selectOption({ label: opt })
}
const alerte = async (p: Page) => (await p.getByRole('alert').first().innerText({ timeout: 3000 }).catch(() => '')).trim().slice(0, 250)

test('H · le salarié envoie une demande, la RH l\'approuve', async ({ browser }) => {
  const sal = await as(browser, 'sal_1')
  const rh = await as(browser, 'rh')
  const avant = (await rows(rh, 'employee_requests?select=id')).length
  await sal.goto('/mon-espace')
  await sal.getByRole('button', { name: 'Nouvelle demande' }).click()
  const sel = field(sal, 'Type de demande')
  const options = await sel.locator('option').allInnerTexts()
  const type = options.find((o) => !/montant|avance|prêt|pret/i.test(o)) ?? options[0]
  await sel.selectOption({ label: type.trim() })
  await field(sal, 'Précisions (facultatif)').fill('Demande de simulation campagne 2')
  await capture(sal, 'profil-nouvelle-demande')
  await sal.getByRole('button', { name: 'Envoyer', exact: true }).click()
  await sal.waitForTimeout(2000)
  const apres = (await rows(rh, 'employee_requests?select=id')).length
  if (apres <= avant) { record('UC-H-DEMANDE', 'ORANGE', `aucune demande créée : ${await alerte(sal)}`); return }
  await capture(sal, 'profil-demande-envoyee')
  await rh.goto('/demandes')
  await rh.waitForLoadState('networkidle')
  await capture(rh, 'demandes-a-traiter')
  await rh.getByRole('button', { name: /Approuver/ }).first().click()
  const dlg = rh.getByRole('dialog')
  await expect(dlg).toBeVisible()
  await dlg.getByRole('button', { name: 'Confirmer' }).click()
  await rh.waitForTimeout(2000)
  const [r] = await rows<{ status: string }>(rh, 'employee_requests?select=status&order=created_at.desc&limit=1')
  record('UC-H-DEMANDE', /approuv/i.test(r?.status ?? '') ? 'VERT' : 'ORANGE', `type « ${type.trim()} », état final : ${r?.status}`)
})

test('B · embauche en apprentissage', async ({ browser }) => {
  const rh = await as(browser, 'rh')
  const deja = await rows<{ employment_type: string }>(rh, 'employees?select=employment_type&first_name=eq.SimAPPRENTISSAGE')
  if (deja.length) { record('UC-B-EMBAUCHE-APPRENTISSAGE', deja[0].employment_type === 'APPRENTISSAGE' ? 'VERT' : 'ROUGE', 'déjà créé'); return }
  const e = makeEmployee(5010, SECTORS[0], '2026-11-02')
  await rh.goto('/salaries/nouveau')
  await field(rh, 'Sexe').selectOption(e.sex)
  await field(rh, 'Prénom').fill('SimAPPRENTISSAGE')
  await field(rh, 'Nom').fill(e.ln)
  await field(rh, 'Date de naissance').fill(e.dob)
  await field(rh, 'Nationalité').fill('sénégalaise')
  await choisir(rh, 'Emploi', 'Vendeur')
  await choisir(rh, 'Type de contrat', 'Apprentissage')
  await choisir(rh, 'Convention collective', e.ag)
  await field(rh, 'Catégorie').selectOption({ index: 3 })
  await field(rh, "Date d'entrée").fill('2026-11-02')
  await choisir(rh, 'Mode de paiement', 'Virement')
  await capture(rh, 'embauche-apprentissage')
  await rh.getByRole('button', { name: 'Créer le salarié' }).click()
  const cree = await rh.waitForURL(/\/salaries\/[0-9a-f-]{36}$/, { timeout: 15_000 }).then(() => true, () => false)
  if (!cree) { record('UC-B-EMBAUCHE-APPRENTISSAGE', 'ORANGE', `refus : ${await alerte(rh)}`); return }
  const [row] = await rows<{ employment_type: string }>(rh, 'employees?select=employment_type&first_name=eq.SimAPPRENTISSAGE')
  record('UC-B-EMBAUCHE-APPRENTISSAGE', row?.employment_type === 'APPRENTISSAGE' ? 'VERT' : 'ROUGE', `type enregistré : ${row?.employment_type}`)
})

test('I · simulation de réorganisation', async ({ browser }) => {
  const rh = await as(browser, 'rh')
  await rh.goto('/equipes/simulation')
  await expect(rh.getByRole('button', { name: 'Ajouter à la simulation' })).toBeVisible({ timeout: 20_000 })
  await capture(rh, 'simulation-reorganisation')
  await field(rh, 'Salarié concerné').selectOption({ index: 5 })
  await field(rh, 'Nouveau manager direct').selectOption({ index: 1 })
  await rh.waitForTimeout(500)
  const ajouter = rh.getByRole('button', { name: 'Ajouter à la simulation' })
  if (!(await ajouter.isEnabled())) {
    await capture(rh, 'simulation-reorganisation-refus')
    record('UC-I-SIMULATION-AJOUT', 'ORANGE', `bouton inactif ; message : ${(await rh.locator('main').innerText()).match(/(cycle|boucle|impossible|déjà)[^\n]*/i)?.[0] ?? 'aucun'}`)
    return
  }
  await ajouter.click()
  await rh.waitForTimeout(2000)
  await capture(rh, 'simulation-reorganisation-ajout')
  const erreur = await alerte(rh)
  record('UC-I-SIMULATION-AJOUT', erreur ? 'ORANGE' : 'VERT', erreur ? `message : ${erreur}` : 'changement ajouté à la simulation')
})
