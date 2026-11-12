import { execFileSync } from 'node:child_process'
import { test, expect, type Browser, type Page } from '@playwright/test'
import { as, record } from './sim-helpers'

// Connexion par téléphone, parcours complet dans l'interface (étape 6 du prompt de reprise) :
// demande, autorisation par l'administrateur (pas par rh), ouverture, mot de passe, connexion, accès limité,
// réutilisation refusée, révocation, réinitialisation, refus. Salarié synthétique « Tel E2E », supprimé à la fin.
test.describe.configure({ mode: 'serial' })

const psql = (sql: string) =>
  execFileSync('docker', ['exec', 'soma-rh-local-postgres-1', 'psql', '-U', 'soma', '-d', 'soma_rh', '-tAc', sql], { encoding: 'utf8' }).trim()
const DOB = '1991-02-03'
const PWD1 = 'Zk7q2xw'
const PWD2 = 'Mn4pv8ty'

let phone = ''
let matricule = ''
let admin: Page, rh: Page

const nettoyer = () => {
  psql(`delete from auth.users where email like '221${phone}@%'`)
  psql(`delete from public.phone_access_requests where employee_id in (select id from public.employees where last_name='E2E' and first_name='Tel')`)
  psql(`delete from public.phone_access_attempts where phone_e164 = '+221${phone}' or phone_e164 is null`)
  psql(`delete from public.employees where last_name='E2E' and first_name='Tel'`)
}

async function anonyme(browser: Browser): Promise<Page> {
  const ctx = await browser.newContext({ storageState: { cookies: [], origins: [] }, locale: 'fr-FR', viewport: { width: 1280, height: 800 } })
  const page = await ctx.newPage()
  await page.goto('/')
  await page.getByRole('tab', { name: 'Téléphone' }).click()
  return page
}
const envoi = (p: Page) => p.locator('form[aria-label] button[type=submit]')

async function demander(browser: Browser, lien: 'Créer mon accès' | 'Mot de passe oublié') {
  const p = await anonyme(browser)
  await p.getByRole('button', { name: lien }).click()
  await p.getByLabel('Numéro de téléphone').fill(phone)
  await p.getByRole('button', { name: 'Envoyer ma demande' }).click()
  await expect(p.getByText("L'administrateur doit l'autoriser")).toBeVisible()
  await p.context().close()
}
const ligne = (p: Page) => p.getByRole('row').filter({ hasText: `Matricule ${matricule}` })
async function ouvrirEcranAcces(p: Page) {
  await p.goto('/parametres?onglet=acces')
  await expect(p.getByText(/Accès des salariés par téléphone/)).toBeVisible({ timeout: 20_000 })
}
async function activer(browser: Browser, motDePasse: string): Promise<Page> {
  const p = await anonyme(browser)
  await p.getByRole('button', { name: 'Mot de passe oublié' }).click()
  await p.getByRole('button', { name: /Ma demande est autorisée/ }).click()
  await p.getByLabel('Numéro de téléphone').fill(phone)
  await p.getByLabel('Date de naissance').fill(DOB)
  await envoi(p).click()
  await p.getByLabel('Nouveau mot de passe').fill(motDePasse)
  await envoi(p).click()
  return p
}

test.beforeAll(async ({ browser }) => {
  phone = psql(`select n from generate_series(700004100, 700004199) n where not exists (select 1 from public.employees where public.phone_normalize(phone_personal) = '+221' || n::text) limit 1`)
  nettoyer()
  matricule = psql(`insert into public.employees (company_id, employee_number, first_name, last_name, employment_type, date_of_joining, status, phone_personal, date_of_birth)
    select id, 'TEL-E1', 'Tel', 'E2E', 'CDI', '2020-01-01', 'Active', '${phone}', '${DOB}' from public.companies limit 1 returning employee_number`).split('\n')[0]
  admin = await as(browser, 'admin')
  rh = await as(browser, 'rh')
})
test.afterAll(() => { if (phone) nettoyer() })

test('demande, alerte visible, rh ne peut pas autoriser, l’administrateur autorise', async ({ browser }) => {
  await demander(browser, 'Créer mon accès')
  await rh.goto('/parametres?onglet=acces')
  await expect(rh.getByRole('tab', { name: 'Accès' })).toBeVisible({ timeout: 20_000 })
  await expect(rh.getByText(/Accès des salariés par téléphone/), 'rh ne doit pas voir l’écran d’autorisation').toHaveCount(0)

  await ouvrirEcranAcces(admin)
  await expect(ligne(admin)).toContainText('Matricule ' + matricule)
  await ligne(admin).getByRole('checkbox', { name: /Autoriser l'accès par téléphone/ }).click()
  await expect(ligne(admin)).toContainText(/Autoris/i)
  record('UC-TEL-AUTORISATION', 'VERT', 'demande visible chez l’administrateur ; rh sans case d’autorisation')
})

test('ouverture, mot de passe, connexion : le compte téléphone ne voit ni paie, ni salariés, ni paramètres', async ({ browser }) => {
  const p = await anonyme(browser)
  await p.getByRole('button', { name: 'Créer mon accès' }).click()
  await p.getByRole('button', { name: /Ma demande est autorisée/ }).click()
  await p.getByLabel('Numéro de téléphone').fill(phone)
  await p.getByLabel('Date de naissance').fill(DOB)
  await envoi(p).click()
  await p.getByLabel('Nouveau mot de passe').fill(PWD1)
  await envoi(p).click()
  await expect(p.getByRole('navigation', { name: 'Navigation principale' })).toBeVisible({ timeout: 30_000 })
  for (const chemin of ['/paie', '/salaries', '/parametres']) {
    await p.goto(chemin)
    await expect.poll(() => new URL(p.url()).pathname, { message: `${chemin} accessible au compte téléphone`, timeout: 15_000 }).not.toBe(chemin)
  }
  await p.context().close()
  record('UC-TEL-CONNEXION', 'VERT', 'activation et connexion ; /paie, /salaries, /parametres inaccessibles')
})

test('autorisation à usage unique : la réutilisation est refusée', async ({ browser }) => {
  const p = await anonyme(browser)
  await p.getByRole('button', { name: 'Mot de passe oublié' }).click()
  await p.getByRole('button', { name: /Ma demande est autorisée/ }).click()
  await p.getByLabel('Numéro de téléphone').fill(phone)
  await p.getByLabel('Date de naissance').fill(DOB)
  await envoi(p).click()
  await expect(p.getByText(/Impossible d'ouvrir l'activation|pas encore autorisé/)).toBeVisible()
  await p.context().close()
  record('UC-TEL-REUTILISATION', 'VERT', 'seconde ouverture sans nouvelle autorisation refusée')
})

test('cinq mauvaises dates de naissance : toujours le même message neutre', async ({ browser }) => {
  await demander(browser, 'Mot de passe oublié')
  await ouvrirEcranAcces(admin)
  await ligne(admin).getByRole('checkbox', { name: /Autoriser/ }).click()
  const p = await anonyme(browser)
  await p.getByRole('button', { name: 'Mot de passe oublié' }).click()
  await p.getByRole('button', { name: /Ma demande est autorisée/ }).click()
  for (let i = 0; i < 5; i++) {
    await p.getByLabel('Numéro de téléphone').fill(phone)
    await p.getByLabel('Date de naissance').fill(`199${i}-01-01`)
    await envoi(p).click()
    await expect(p.getByText(/Impossible d'ouvrir l'activation/)).toBeVisible()
  }
  // la bonne date juste après les échecs : on constate le comportement sans le supposer
  await p.getByLabel('Date de naissance').fill(DOB)
  await envoi(p).click()
  const ouvert = await p.getByLabel('Nouveau mot de passe').isVisible({ timeout: 5000 }).catch(() => false)
  record('UC-TEL-MAUVAISES-DATES', ouvert ? 'ORANGE' : 'VERT', ouvert ? 'après 5 mauvaises dates, la bonne date ouvre encore l’activation' : 'après 5 mauvaises dates, la bonne date est refusée')
  await p.context().close()
})

test('réinitialisation, puis révocation : la connexion est refusée', async ({ browser }) => {
  // on repart d'une demande propre pour ne pas dépendre du test précédent
  psql(`delete from public.phone_access_attempts where phone_e164 = '+221${phone}'`)
  psql(`update public.phone_access_requests set status='revoked' where employee_id in (select id from public.employees where last_name='E2E') and status in ('pending','authorized')`)
  await demander(browser, 'Mot de passe oublié')
  await ouvrirEcranAcces(admin)
  await ligne(admin).getByRole('checkbox', { name: /Autoriser/ }).click()
  const p = await activer(browser, PWD2)
  await expect(p.getByRole('navigation', { name: 'Navigation principale' })).toBeVisible({ timeout: 30_000 })
  await p.context().close()
  record('UC-TEL-REINIT', 'VERT', 'mot de passe réinitialisé par une nouvelle demande autorisée')

  await ouvrirEcranAcces(admin)
  await admin.getByRole('listitem').filter({ hasText: `Matricule ${matricule}` }).getByRole('button', { name: "Révoquer l'accès" }).click()
  const q = await anonyme(browser)
  await q.getByLabel('Numéro de téléphone').fill(phone)
  await q.locator('#panel-phone').getByLabel('Mot de passe', { exact: true }).fill(PWD2)
  await envoi(q).click()
  await expect(q.getByRole('alert')).toBeVisible({ timeout: 15_000 })
  await expect(q.getByRole('navigation', { name: 'Navigation principale' })).toHaveCount(0)
  await q.context().close()
  record('UC-TEL-REVOCATION', 'VERT', 'après révocation, la connexion est refusée')
})

test('refus : l’administrateur refuse une demande, l’activation reste fermée', async ({ browser }) => {
  await demander(browser, 'Créer mon accès')
  await ouvrirEcranAcces(admin)
  await ligne(admin).getByRole('button', { name: 'Refuser' }).first().click()
  const p = await anonyme(browser)
  await p.getByRole('button', { name: 'Créer mon accès' }).click()
  await p.getByRole('button', { name: /Ma demande est autorisée/ }).click()
  await p.getByLabel('Numéro de téléphone').fill(phone)
  await p.getByLabel('Date de naissance').fill(DOB)
  await envoi(p).click()
  await expect(p.getByLabel('Nouveau mot de passe')).toHaveCount(0)
  await p.context().close()
  record('UC-TEL-REFUS', 'VERT', 'demande refusée : activation fermée')
})
