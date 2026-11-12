import { appendFileSync, mkdirSync, readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { dirname } from 'node:path'
import { expect, type Browser, type Page } from '@playwright/test'

export type SimRole = 'admin' | 'admin2' | 'rh' | 'rh2' | 'paie' | 'paie2' | 'rhpaie' | 'mgr_1' | 'sal_1'
export const SIM_ROLES: SimRole[] = ['admin', 'admin2', 'rh', 'rh2', 'paie', 'paie2', 'rhpaie', 'mgr_1', 'sal_1']

const ENV_FILE = fileURLToPath(new URL('../../../tests/.env.qa-sim', import.meta.url))
const CAPTURES = fileURLToPath(new URL('../../../docs/guide-utilisateur/captures-sim/', import.meta.url))
const RESULTS = fileURLToPath(new URL('../../../docs/recette/simulation-200/resultats-playwright.jsonl', import.meta.url))

function env() {
  return Object.fromEntries(
    readFileSync(ENV_FILE, 'utf8').split(/\r?\n/).filter((l) => /^SIM_\w+=/.test(l)).map((l) => [l.slice(0, l.indexOf('=')), l.slice(l.indexOf('=') + 1)]),
  )
}
export const stateFile = (role: SimRole) => fileURLToPath(new URL(`../.auth/sim-${role}.json`, import.meta.url))

/** Connexion par le formulaire (une seule fois par rôle : l'API limite les connexions). */
export async function login(page: Page, role: SimRole) {
  const e = env()
  const key = role.toUpperCase()
  await page.goto('/')
  await page.getByLabel('Adresse e-mail').fill(e[`SIM_${key}_EMAIL`])
  await page.getByLabel('Mot de passe').fill(e[`SIM_${key}_PASSWORD`])
  await page.getByRole('button', { name: 'Se connecter' }).click()
  const menu = page.getByRole('navigation', { name: 'Navigation principale' })
  const refus = page.getByRole('alert')
  await menu.or(refus).first().waitFor()
  if (await refus.isVisible()) throw new Error(`Connexion refusée (${role}) : ${(await refus.innerText()).trim()}`)
}

/** Ouvre une page neuve avec la session enregistrée d'un rôle. */
export async function as(browser: Browser, role: SimRole): Promise<Page> {
  const ctx = await browser.newContext({ storageState: stateFile(role), locale: 'fr-FR', viewport: { width: 1280, height: 800 } })
  const page = await ctx.newPage()
  await page.goto('/')
  await expect(page.getByRole('navigation', { name: 'Navigation principale' })).toBeVisible()
  return page
}

/** Capture destinée au guide utilisateur. */
export async function shot(page: Page, name: string) {
  mkdirSync(CAPTURES, { recursive: true })
  await page.screenshot({ path: `${CAPTURES}${name}.png` })
}

/** Ajoute une ligne à la matrice des cas d'usage (VERT / ROUGE / ORANGE). */
export function record(uc: string, status: 'VERT' | 'ROUGE' | 'ORANGE', note = '') {
  mkdirSync(dirname(RESULTS), { recursive: true })
  appendFileSync(RESULTS, JSON.stringify({ uc, status, note, at: new Date().toISOString() }) + '\n')
}

/** Champ d'un formulaire retrouvé par le début de son libellé (les libellés enveloppent les champs). */
export const field = (page: Page, label: string) =>
  page.locator('label').filter({ hasText: new RegExp('^' + label.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')) }).locator('input,select,textarea').first()

async function token(page: Page): Promise<string> {
  return page.evaluate(() => JSON.parse(localStorage.getItem('sb-localhost-auth-token') ?? '{}').access_token as string)
}
export async function count(page: Page, table: string, filter = ''): Promise<number> {
  const t = await token(page)
  const r = await page.request.get(`/rest/v1/${table}?select=id${filter}`, { headers: { Authorization: `Bearer ${t}`, Prefer: 'count=exact', Range: '0-0' } })
  return Number((r.headers()['content-range'] ?? '*/0').split('/')[1])
}
export async function rows<T = Record<string, unknown>>(page: Page, path: string): Promise<T[]> {
  const t = await token(page)
  const r = await page.request.get(`/rest/v1/${path}`, { headers: { Authorization: `Bearer ${t}` } })
  return (await r.json()) as T[]
}

// ---- Données de simulation (déterministes) ----
const FN_M = ['Mamadou','Ousmane','Cheikh','Papa','Modou','Serigne','Babacar','Lamine','Pape','Idrissa','Samba','Moustapha','Daouda','Boubacar','Assane','Souleymane','Malick','Demba','Birame','Ismaila']
const FN_F = ['Aissatou','Mariama','Ndeye','Coumba','Rokhaya','Sokhna','Astou','Bineta','Dieynaba','Penda','Marieme','Yacine','Adama','Seynabou','Ramatoulaye','Codou','Maimouna','Nafissatou','Fama','Diarra']
const LN = ['Diallo','Ndiaye','Sy','Cissé','Seck','Gning','Camara','Niang','Samb','Tall','Diagne','Lô','Sène','Badji','Dione','Mendy','Faye','Sarr','Kébé','Thioune','Ndao','Wade','Bâ','Diouf','Fall','Mbow','Gaye','Toure','Sagna','Coly']

export type NewEmployee = { sex: 'M' | 'F'; fn: string; ln: string; dob: string; ms: string; kids: number; job: string; ag: string; cat: number; doj: string }

/** Secteurs de la simulation : convention, emplois proposés, nombre de catégories de la grille. */
export const SECTORS: { ag: string; jobs: string[]; cats: number }[] = [
  { ag: 'Commerce', jobs: ['Vendeur', 'Caissier', 'Commercial'], cats: 18 },
  { ag: 'Btp', jobs: ['Maçon', 'Électricien', 'Plombier', 'Chef de chantier'], cats: 31 },
  { ag: 'Industries Hotelieres', jobs: ['Serveur', 'Cuisinier', 'Réceptionniste', 'Femme de chambre'], cats: 16 },
  { ag: 'Securite Privee', jobs: ['Agent de sécurité', 'Chef de poste sécurité'], cats: 31 },
  { ag: 'Transports Publics Routiers', jobs: ['Chauffeur de bus'], cats: 27 },
  { ag: 'Transports Routiers Hydrocarbures', jobs: ['Chauffeur poids lourd', 'Mécanicien'], cats: 27 },
  { ag: 'Petrole Et Gaz', jobs: ['Opérateur de raffinerie', 'Technicien de maintenance', 'Ingénieur'], cats: 38 },
  { ag: 'Mecanique Generale', jobs: ['Soudeur', 'Mécanicien'], cats: 26 },
  { ag: 'Industries Alimentaires', jobs: ['Opérateur de production', 'Magasinier'], cats: 20 },
  { ag: 'Industries Chimiques Extratives', jobs: ['Technicien chimiste', 'Opérateur de production'], cats: 19 },
]

export function makeEmployee(i: number, sector: { ag: string; jobs: string[]; cats: number }, doj: string): NewEmployee {
  const sex = i % 3 === 0 ? 'F' : 'M'
  const fn = (sex === 'F' ? FN_F : FN_M)[(i * 7) % 20]
  const ln = LN[(i * 11 + 3) % 30]
  const y = 1975 + ((i * 5) % 25)
  const m = String(1 + ((i * 7) % 12)).padStart(2, '0')
  const d = String(1 + ((i * 3) % 27)).padStart(2, '0')
  return { sex, fn, ln, dob: `${y}-${m}-${d}`, ms: i % 2 ? 'Marié(e)' : 'Célibataire', kids: i % 2 ? i % 4 : 0, job: sector.jobs[i % sector.jobs.length], ag: sector.ag, cat: 1 + ((i * 5) % sector.cats), doj }
}

async function pick(page: Page, label: string, text: string) {
  const sel = field(page, label)
  const opt = sel.locator('option', { hasText: text }).first()
  const value = await opt.getAttribute('value')
  // certaines listes (situation de famille) n'ont pas d'attribut value : on choisit alors par le libellé
  if (value !== null) await sel.selectOption(value)
  else await sel.selectOption({ label: (await opt.innerText()).trim() })
}

/** Création d'un salarié par le formulaire, puis déclaration d'embauche et structure salariale (chaîne complète). */
export async function createEmployeeUI(page: Page, e: NewEmployee, assign = true): Promise<string> {
  await page.goto('/salaries/nouveau')
  await field(page, 'Sexe').selectOption(e.sex)
  await field(page, 'Prénom').fill(e.fn)
  await field(page, 'Nom').fill(e.ln)
  await field(page, 'Date de naissance').fill(e.dob)
  await field(page, 'Nationalité').fill('sénégalaise')
  await pick(page, 'Situation de famille', e.ms)
  await field(page, 'Enfants à charge').fill(String(e.kids))
  await pick(page, 'Emploi', e.job)
  await pick(page, 'Type de contrat', 'CDI')
  await pick(page, 'Convention collective', e.ag)
  await field(page, 'Catégorie').selectOption({ index: e.cat })
  await field(page, "Date d'entrée").fill(e.doj)
  await pick(page, 'Mode de paiement', 'Virement')
  await page.getByRole('button', { name: 'Créer le salarié' }).click()
  await page.waitForURL(/\/salaries\/[0-9a-f-]{36}$/)
  await field(page, "Référence de la déclaration d'embauche").fill(`DPAE-${e.doj.slice(0, 4)}-${e.ln.toUpperCase()}`)
  await field(page, "Date de la déclaration d'embauche").fill(e.doj)
  await page.getByRole('button', { name: 'Enregistrer la fiche' }).click()
  // le message de confirmation est fugace : on le consigne s'il manque, la preuve reste la base (déclaration d'embauche renseignée)
  await page.getByText('Fiche enregistrée').waitFor({ timeout: 10_000 }).catch(() => record('UC-FICHE-MSG', 'ORANGE', "message « Fiche enregistrée » non affiché après l'enregistrement"))
  const url = page.url()
  if (assign) await assignStructure(page, e.doj)
  return url
}

/** Affectation de la structure salariale (piège : la date par défaut est le mois courant). */
export async function assignStructure(page: Page, date: string) {
  const bloc = page.getByRole('heading', { name: 'Structure salariale' }).locator('xpath=../..')
  const champ = bloc.locator('input[type=date]').first()
  // la section est en lecture seule pour le rôle RH : l'affectation relève de la paie (ou de l'admin)
  await expect(champ, 'section « Structure salariale » non modifiable pour ce compte').toBeEnabled({ timeout: 20_000 })
  // piège constaté : si l'on enregistre avant la fin du chargement de la structure, la base répond
  // « null value in column structure_id … violates not-null constraint » (erreur brute affichée à l'utilisateur)
  await page.waitForLoadState('networkidle')
  for (let essai = 0; essai < 3; essai++) {
    await champ.fill(date)
    await bloc.getByRole('button', { name: 'Enregistrer', exact: true }).click()
    const ok = page.getByText('affectation existante')
    const erreur = page.getByRole('alert').filter({ hasText: 'structure_id' })
    await ok.or(erreur).first().waitFor({ timeout: 8000 })
    if (await ok.isVisible()) return
    record('UC-STRUCT-RACE', 'ROUGE', 'enregistrement de la structure avant chargement : erreur brute structure_id not-null')
    await page.waitForTimeout(2000)
  }
  throw new Error('Affectation de structure impossible après 3 essais')
}

/** Crée le traitement du mois et calcule les bulletins. Retourne le nombre de bulletins annoncé. */
export async function createAndCalculate(page: Page, ym: string): Promise<string> {
  await page.goto('/paie')
  await page.getByRole('button', { name: 'Nouveau traitement' }).click()
  await page.locator('input[type=month]').fill(ym)
  await page.locator('[role=dialog] select, .fixed select').first().selectOption({ label: 'Virement bancaire' })
  await page.getByRole('button', { name: 'Créer le traitement' }).click()
  await page.waitForURL(/\/paie\/[0-9a-f-]{36}$/)
  await page.getByRole('button', { name: 'Calculer les bulletins' }).click()
  const msg = page.getByText(/\d+ bulletin\(s\) calculé\(s\)/)
  await expect(msg).toBeVisible({ timeout: 120_000 })
  return (await msg.innerText()).trim()
}

/** Une étape de la gouvernance de paie ; renvoie le message de refus éventuel. */
export async function govStep(page: Page, label: string, motif = 'Simulation : dérogation tracée'): Promise<string | null> {
  await page.goto('/paie/gouvernance')
  await page.waitForLoadState('networkidle')
  const b = page.getByRole('button', { name: label, exact: true }).first()
  const present = await b.waitFor({ state: 'visible', timeout: 10_000 }).then(() => true, () => false)
  if (!present) return `bouton « ${label} » absent`
  await b.click()
  const dlg = page.getByRole('dialog')
  if (await dlg.isVisible({ timeout: 1500 }).catch(() => false)) {
    const motifBox = dlg.locator('input,textarea').first()
    if (await motifBox.isVisible().catch(() => false)) {
      await motifBox.fill(motif)
      await dlg.getByRole('button', { name: 'Déroger et poursuivre' }).click()
    }
  }
  await page.waitForTimeout(1500)
  const refus = page.getByText(/refusée[^\n]*/).first()
  if (await refus.isVisible().catch(() => false)) return (await refus.innerText()).slice(0, 200)
  const alerte = page.getByRole('alert').first()
  if (await alerte.isVisible().catch(() => false)) return (await alerte.innerText()).slice(0, 200)
  return null
}

/** Salariés sans structure salariale (reprise après une interruption) : la paie les complète par l'interface. */
export async function healStructures(paie: Page) {
  const emps = await rows<{ id: string; date_of_joining: string }>(paie, 'employees?select=id,date_of_joining')
  const aff = await rows<{ employee_id: string }>(paie, 'salary_structure_assignments?select=employee_id')
  const vus = new Set(aff.map((a) => a.employee_id))
  for (const e of emps.filter((x) => !vus.has(x.id))) {
    await paie.goto(`/salaries/${e.id}`)
    await assignStructure(paie, e.date_of_joining)
  }
}
