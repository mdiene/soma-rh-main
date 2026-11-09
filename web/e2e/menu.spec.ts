import { expect, test, type Page } from '@playwright/test'
import { collectPageErrors, stateFile, start } from './helpers'

// Menu par rôle et gardes de route. Lecture seule : aucun clic ne modifie une donnée.
const nav = (page: Page) => page.getByRole('navigation', { name: 'Navigation principale' })

test.describe('administrateur', () => {
  test.use({ storageState: stateFile('admin') })
  test.beforeEach(({ page }) => start(page))

  test('les six espaces sont proposés', async ({ page }) => {
    for (const name of [/^Espace personnel/, /^Management/, /^Administration du personnel/, /^Paie et rémunération/, /^Pilotage et décision/, /^Configuration/]) {
      await expect(nav(page).getByRole('button', { name })).toBeVisible()
    }
  })

  test('Tableau de bord est épinglé en tête du menu', async ({ page }) => {
    await expect(nav(page).getByRole('link').first()).toHaveText('Tableau de bord')
  })

  test('accordéon à ouverture unique : ouvrir un espace referme le précédent', async ({ page }) => {
    const n = nav(page)
    const paie = page.locator('#space-paie')
    const rh = page.locator('#space-rh')
    await n.getByRole('button', { name: /^Paie et rémunération/ }).click()
    await expect(paie).not.toHaveAttribute('inert')
    await n.getByRole('button', { name: /^Administration du personnel/ }).click()
    await expect(rh).not.toHaveAttribute('inert')
    await expect(paie).toHaveAttribute('inert', '') // refermé : ses liens sortent de la navigation au clavier
  })

  test('Ctrl+K : « ipres » mène aux états légaux', async ({ page }) => {
    await page.keyboard.press('Control+k')
    await page.getByPlaceholder(/Aller à/).fill('ipres')
    await page.keyboard.press('Enter')
    await expect(page).toHaveURL(/\/etats$/)
  })

  test('aucune page principale ne plante', async ({ page }) => {
    const errors = collectPageErrors(page)
    for (const route of ['/', '/salaries', '/conges', '/presences', '/paie', '/etats', '/pilotage', '/modules', '/parametres', '/journal', '/mon-equipe', '/mon-espace']) {
      await page.goto(route)
      await page.waitForLoadState('networkidle')
      await expect(page.getByRole('heading', { level: 1 }).first(), `page ${route}`).toBeVisible()
    }
    expect(errors).toEqual([])
  })
})

test.describe('salarié', () => {
  test.use({ storageState: stateFile('salarie') })
  test.beforeEach(({ page }) => start(page))

  test('liste plate, sans espace de gestion', async ({ page }) => {
    const n = nav(page)
    await expect(n.getByRole('link', { name: 'Mes bulletins' })).toBeVisible()
    await expect(n.getByRole('link', { name: 'Mes congés' })).toBeVisible()
    await expect(n.getByRole('button', { name: /Paie et rémunération|Administration du personnel|Configuration/ })).toHaveCount(0)
    await expect(n.getByRole('link', { name: 'Tableau de bord' })).toHaveCount(0)
  })

  test('les pages de gestion le renvoient ailleurs', async ({ page }) => {
    for (const route of ['/paie', '/salaries', '/modules', '/journal']) {
      await page.goto(route)
      await expect(page, route).not.toHaveURL(new RegExp(`${route}$`))
    }
  })
})

test.describe('manager', () => {
  test.use({ storageState: stateFile('manager') })
  test.beforeEach(({ page }) => start(page))

  test('accède à son équipe mais pas à la gestion', async ({ page }) => {
    await page.goto('/mon-equipe')
    await expect(page.getByRole('heading', { level: 1, name: 'Mon équipe' })).toBeVisible()
    for (const route of ['/paie', '/modules']) {
      await page.goto(route)
      await expect(page, route).not.toHaveURL(new RegExp(`${route}$`))
    }
  })
})
