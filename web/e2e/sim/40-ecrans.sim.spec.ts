import { test, expect } from '@playwright/test'
import { as, record, rows, type SimRole } from './sim-helpers'
import { capture } from './helpers/capture'

// Palier 11 — visite de chaque écran du menu avec le rôle qui y a droit (lecture seule) : capture + absence de plantage.
test.describe.configure({ mode: 'serial' })

type Ecran = [role: SimRole, route: string, nom: string, uc: string]
const ECRANS: Ecran[] = [
  ['rh', '/', 'tableau-de-bord-rh', 'UC-I-TABLEAU'], ['rh', '/pilotage', 'pilotage-rh', 'UC-I-PILOTAGE'],
  ['rh', '/salaries', 'salaries-liste', 'UC-B-LISTE'], ['rh', '/salaries/nouveau', 'salaries-nouveau', 'UC-B-NOUVEAU'],
  ['rh', '/dossiers-salaries', 'dossiers-administratifs', 'UC-B-DOSSIERS'], ['rh', '/demandes', 'demandes-des-salaries', 'UC-H-DEMANDES-RH'],
  ['rh', '/conges', 'conges-rh', 'UC-D-CONGES-RH'], ['rh', '/presences', 'presences-du-mois', 'UC-C-PRESENCES'], ['rh', '/planning', 'planning-metier', 'UC-C-PLANNING'],
  ['rh', '/equipes', 'equipes-et-managers', 'UC-I-EQUIPES'], ['rh', '/equipes/organigramme', 'organigramme-global', 'UC-I-ORGANIGRAMME'],
  ['rh', '/equipes/simulation', 'simulation-organisation', 'UC-I-SIMULATION'],
  ['rh', '/paie/variables', 'paie-variables', 'UC-E-VARIABLES'], ['rh', '/paie/ajustements', 'paie-prets-regularisations', 'UC-E-AJUSTEMENTS'],
  ['rh', '/paie', 'paie-traitements', 'UC-E-TRAITEMENTS'], ['rh', '/paie/cotisations', 'paie-suivi-cotisations', 'UC-F-COTISATIONS'],
  ['rh', '/paie/gouvernance', 'paie-gouvernance', 'UC-E-GOUVERNANCE'], ['rh', '/etats', 'etats-legaux', 'UC-F-ETATS'],
  ['rh', '/centre-conformite', 'centre-conformite', 'UC-G-CENTRE'], ['rh', '/modules', 'modules-metiers', 'UC-G-MODULES'],
  ['rh', '/journal', 'journal-des-modifications', 'UC-I-JOURNAL'], ['rh', '/mon-espace', 'mon-profil-rh', 'UC-H-PROFIL'],
  ['admin', '/parametres?onglet=acces', 'parametres-acces', 'UC-A-ACCES'], ['admin', '/parametres?onglet=paie', 'parametres-taux-et-plafonds', 'UC-A-TAUX'],
  ['admin', '/parametres?onglet=baremes', 'parametres-baremes', 'UC-A-BAREMES'], ['admin', '/parametres?onglet=rubriques', 'parametres-rubriques', 'UC-A-RUBRIQUES'],
  ['admin', '/parametres?onglet=grilles', 'parametres-grilles', 'UC-A-GRILLES'], ['admin', '/parametres?onglet=societe', 'parametres-societe', 'UC-A-SOCIETE'],
  ['admin', '/parametres?onglet=modeles', 'parametres-modeles-documents', 'UC-A-MODELES'], ['admin', '/parametres?onglet=journal', 'parametres-journal', 'UC-I-JOURNAL-PARAM'],
  ['paie', '/', 'tableau-de-bord-paie', 'UC-E-TABLEAU-PAIE'], ['paie', '/paie', 'paie-traitements-paie', 'UC-E-TRAITEMENTS-PAIE'], ['paie', '/etats', 'etats-legaux-paie', 'UC-F-ETATS-PAIE'],
  ['mgr_1', '/mon-equipe', 'mon-equipe', 'UC-D-MON-EQUIPE'], ['mgr_1', '/equipes/organigramme', 'organigramme-equipe', 'UC-I-ORGANIGRAMME-EQ'],
  ['mgr_1', '/conges', 'conges-manager', 'UC-D-CONGES-MGR'], ['mgr_1', '/mon-espace', 'mon-profil-manager', 'UC-H-PROFIL-MGR'],
  ['sal_1', '/mon-espace', 'mon-profil-salarie', 'UC-H-PROFIL-SAL'], ['sal_1', '/conges', 'mes-conges', 'UC-H-CONGES'], ['sal_1', '/mes-bulletins', 'mes-bulletins', 'UC-H-BULLETINS'],
]

for (const [role, route, nom, uc] of ECRANS) {
  test(`${role} · ${route}`, async ({ browser }) => {
    const page = await as(browser, role)
    const erreurs: string[] = []
    page.on('pageerror', (e) => erreurs.push(e.message))
    await page.goto(route)
    await expect(page.locator('h1').first()).toBeVisible({ timeout: 20_000 })
    const refus = await page.getByText(/accès refusé|n'avez pas accès|page introuvable/i).first().isVisible().catch(() => false)
    await capture(page, nom)
    record(uc, !refus && erreurs.length === 0 ? 'VERT' : 'ROUGE', `${role} ${route}${erreurs.length ? ' · ' + erreurs[0] : ''}${refus ? ' · accès refusé' : ''}`)
    expect(erreurs).toEqual([])
    expect(refus).toBe(false)
  })
}

test('rh · fiche salarié (identité, contrat, structure)', async ({ browser }) => {
  const rh = await as(browser, 'rh')
  const [e] = await rows<{ id: string }>(rh, 'employees?select=id&employee_number=eq.S0728')
  await rh.goto(`/salaries/${e.id}`)
  await expect(rh.getByRole('heading', { name: 'Structure salariale' })).toBeVisible({ timeout: 20_000 })
  await capture(rh, 'salarie-fiche')
  await rh.getByRole('heading', { name: 'Structure salariale' }).scrollIntoViewIfNeeded()
  await capture(rh, 'salarie-fiche-structure')
  record('UC-B-FICHE', 'VERT', 'fiche S0728')
})
