import AxeBuilder from '@axe-core/playwright'
import { expect, test, type Page } from '@playwright/test'
import { stateFile, start } from './helpers'

// Connexion par téléphone, côté interface : onglets, parcours en 3 étapes, accessibilité WCAG A/AA, écran de l'administrateur.
// Ne modifie aucune donnée (le parcours complet avec base est dans tests/api/phone.journey.test.mjs).
const scan = (page: Page) => new AxeBuilder({ page }).withTags(['wcag2a', 'wcag2aa'])
const resume = (v: { id: string; impact?: string | null; nodes: unknown[] }[]) => v.map((x) => `${x.id} (${x.impact}, ${x.nodes.length})`)

test.describe('écran de connexion (non connecté)', () => {
  test.use({ storageState: { cookies: [], origins: [] } })

  test('deux onglets, e-mail par défaut ; le parcours téléphone avance en 3 étapes', async ({ page }) => {
    await page.goto('/')
    await expect(page.getByRole('tab', { name: 'E-mail' })).toHaveAttribute('aria-selected', 'true')
    await expect(page.getByLabel('Adresse e-mail')).toBeVisible()

    await page.getByRole('tab', { name: 'Téléphone' }).click()
    await expect(page.getByLabel('Numéro de téléphone')).toBeVisible()
    await expect(page.getByRole('button', { name: 'Se connecter' })).toBeVisible()

    await page.getByRole('button', { name: 'Créer mon accès' }).click()
    await page.getByLabel('Numéro de téléphone').fill('78 000 00 00')
    await page.getByRole('button', { name: 'Envoyer ma demande' }).click()
    // numéro inconnu ou non : toujours le même message neutre
    await expect(page.getByText("L'administrateur doit l'autoriser")).toBeVisible()

    await page.getByRole('button', { name: /Ma demande est autorisée/ }).click()
    await expect(page.getByLabel('Date de naissance')).toBeVisible()
    await page.getByLabel('Numéro de téléphone').fill('78 000 00 00')
    await page.getByLabel('Date de naissance').fill('1990-01-01')
    await page.getByRole('button', { name: 'Continuer' }).click()
    await expect(page.getByText(/Impossible d'ouvrir l'activation/)).toBeVisible()
  })

  test('accessibilité : aucune violation WCAG A/AA sur les deux onglets', async ({ page }) => {
    await page.goto('/')
    expect(resume((await scan(page).analyze()).violations)).toEqual([])
    await page.getByRole('tab', { name: 'Téléphone' }).click()
    await expect(page.getByLabel('Numéro de téléphone')).toBeVisible()
    expect(resume((await scan(page).analyze()).violations)).toEqual([])
  })
})

test.describe('administrateur', () => {
  test.use({ storageState: stateFile('admin') })

  test("l'écran d'autorisation est dans Paramètres > Accès, sans violation critique", async ({ page }) => {
    await start(page, '/parametres?onglet=acces')
    await expect(page.getByText(/Accès des salariés par téléphone/)).toBeVisible()
    await expect(page.getByText(/Exiger la date de naissance/)).toBeVisible()
    await page.waitForLoadState('networkidle')
    expect(resume((await scan(page).analyze()).violations.filter((v) => v.impact === 'critical'))).toEqual([])
  })
})

test.describe('salarié', () => {
  test.use({ storageState: stateFile('salarie') })

  test("ne voit pas l'écran d'autorisation", async ({ page }) => {
    await start(page, '/parametres?onglet=acces')
    await expect(page.getByText(/Accès des salariés par téléphone/)).toHaveCount(0)
  })
})
