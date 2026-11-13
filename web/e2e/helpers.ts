import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { expect, type Page } from '@playwright/test'

export type QaRole = 'admin' | 'manager' | 'salarie'

/** Identifiants du compte de test d'un rôle, lus dans tests/.env.qa (hors Git) : jamais écrits dans le code. */
function credentials(role: QaRole) {
  const file = fileURLToPath(new URL('../../tests/.env.qa', import.meta.url))
  const env = Object.fromEntries(
    readFileSync(file, 'utf8').split(/\r?\n/).filter((l) => /^QA_\w+=/.test(l)).map((l) => [l.slice(0, l.indexOf('=')), l.slice(l.indexOf('=') + 1)]),
  )
  const email = env[`QA_${role.toUpperCase()}_EMAIL`]
  const password = env[`QA_${role.toUpperCase()}_PASSWORD`]
  if (!email || !password) throw new Error(`Compte QA « ${role} » introuvable dans tests/.env.qa`)
  return { email, password }
}

/** Fichier de session enregistré par auth.setup.ts pour un rôle. */
export const stateFile = (role: QaRole) => fileURLToPath(new URL(`./.auth/${role}.json`, import.meta.url))

/** Connexion par le formulaire (réservée à auth.setup.ts : l'API limite les connexions). */
export async function login(page: Page, role: QaRole) {
  const { email, password } = credentials(role)
  await page.goto('/')
  await page.getByLabel('Adresse e-mail').fill(email)
  await page.getByLabel('Mot de passe').fill(password)
  await page.getByRole('button', { name: 'Se connecter' }).click()
  const menu = page.getByRole('navigation', { name: 'Navigation principale' })
  const refus = page.getByRole('alert')
  await menu.or(refus).first().waitFor()
  if (await refus.isVisible()) throw new Error(`Connexion refusée pour « ${role} » : ${(await refus.innerText()).trim()}`)
  await expect(menu).toBeVisible()
}

/** Ouvre l'application avec la session enregistrée du rôle (`test.use({ storageState: stateFile(role) })`). */
export async function start(page: Page, route = '/') {
  // menu épinglé ouvert par défaut pour des tests déterministes (par défaut l'application le replie : volet au survol) ; un test peut le changer
  await page.addInitScript(() => { try { if (localStorage.getItem('nav-rail') === null) localStorage.setItem('nav-rail', '0') } catch { /* stockage indisponible */ } })
  await page.goto(route)
  await expect(page.getByRole('navigation', { name: 'Navigation principale' })).toBeVisible()
}

/** Erreurs JavaScript non rattrapées pendant le test (ex. page qui plante sur une donnée vide). */
export function collectPageErrors(page: Page): string[] {
  const errors: string[] = []
  page.on('pageerror', (e) => errors.push(e.message))
  return errors
}
