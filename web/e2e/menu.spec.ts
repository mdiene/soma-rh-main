import { expect, test, type Page } from '@playwright/test'
import { collectPageErrors, stateFile, start } from './helpers'

// Menu par rôle et gardes de route. Lecture seule : aucun clic ne modifie une donnée.
const nav = (page: Page) => page.getByRole('navigation', { name: 'Navigation principale' })

test.describe('administrateur', () => {
  test.use({ storageState: stateFile('admin') })
  test.beforeEach(({ page }) => start(page))

  test('les sept espaces sont proposés', async ({ page }) => {
    for (const name of [/^Espace personnel/, /^Management/, /^Administration du personnel/, /^Paie et rémunération/, /^Pilotage et décision/, /^Configuration/, /^À propos/]) {
      await expect(nav(page).getByRole('button', { name })).toBeVisible()
    }
  })

  test('Tableau de bord est épinglé en tête du menu', async ({ page }) => {
    await expect(nav(page).getByRole('link').first()).toHaveAccessibleName('Tableau de bord') // icône du rail
  })

  test('rail + volet : choisir un espace affiche ses pages et masque celles des autres', async ({ page }) => {
    const n = nav(page)
    await n.getByRole('button', { name: /^Paie et rémunération/ }).click()
    await expect(n.getByRole('link', { name: 'Variables du mois' })).toBeVisible()
    await expect(n.getByRole('link', { name: 'Salariés', exact: true })).toHaveCount(0)
    await n.getByRole('button', { name: /^Administration du personnel/ }).click()
    await expect(n.getByRole('link', { name: 'Salariés', exact: true })).toBeVisible()
    await expect(n.getByRole('link', { name: 'Variables du mois' })).toHaveCount(0)
  })

  test('menu non épinglé : un clic ouvre le panneau flottant, Échap le referme', async ({ page }) => {
    const n = nav(page)
    await n.getByRole('button', { name: 'Désépingler le menu (le replier)' }).click()
    await expect(n.getByRole('button', { name: 'Épingler le menu ouvert' })).toBeVisible()
    await n.getByRole('button', { name: /^Paie et rémunération/ }).click()
    await expect(page.getByRole('group', { name: 'Paie et rémunération' }).getByRole('link', { name: 'Variables du mois' })).toBeVisible()
    await page.keyboard.press('Escape')
    await expect(page.getByRole('group', { name: 'Paie et rémunération' })).toHaveCount(0)
    await n.getByRole('button', { name: 'Épingler le menu ouvert' }).click() // remet l'état mémorisé par défaut
  })

  test('menu non épinglé : le survol déploie le volet, la sortie de la souris et le clic le referment', async ({ page }) => {
    const n = nav(page)
    await n.getByRole('button', { name: 'Désépingler le menu (le replier)' }).click()
    const volet = page.getByRole('group', { name: 'Paie et rémunération' })
    await n.getByRole('button', { name: /^Paie et rémunération/ }).hover()
    await expect(volet.getByRole('link', { name: 'Variables du mois' })).toBeVisible()
    await page.mouse.move(700, 450) // la souris quitte la zone du menu
    await expect(volet).toHaveCount(0)
    await n.getByRole('button', { name: /^Paie et rémunération/ }).hover()
    await volet.getByRole('link', { name: 'Variables du mois' }).click() // un clic sur une page referme le volet
    await expect(page).toHaveURL(/\/paie\/variables/)
    await expect(volet).toHaveCount(0)
    await n.getByRole('button', { name: 'Épingler le menu ouvert' }).click() // épinglé : le panneau reste ouvert
    await expect(n.getByRole('button', { name: 'Désépingler le menu (le replier)' })).toBeVisible()
    await expect(n.getByRole('link', { name: 'Variables du mois' })).toBeVisible()
  })

  test('menu À propos : aide, informations, tarification, conditions, confidentialité, versions', async ({ page }) => {
    const n = nav(page)
    await n.getByRole('button', { name: /^À propos/ }).click()
    for (const name of ['Aide et guide utilisateur', 'À propos de SOMA-RH', 'Tarification et services', 'Conditions d’utilisation', 'Politique de confidentialité', 'Sauvegardes et versions']) {
      await expect(n.getByRole('link', { name })).toBeVisible()
    }
  })

  test('Ctrl+K : « ipres » mène aux états légaux', async ({ page }) => {
    await page.keyboard.press('Control+k')
    await page.getByPlaceholder(/Aller à/).fill('ipres')
    await page.keyboard.press('Enter')
    await expect(page).toHaveURL(/\/etats$/)
  })

  test('aucune page principale ne plante', async ({ page }) => {
    const errors = collectPageErrors(page)
    for (const route of ['/', '/salaries', '/salaries/en-cours', '/conges', '/presences', '/paie', '/etats', '/pilotage', '/modules', '/parametres', '/journal', '/mon-equipe', '/mon-espace', '/aide', '/a-propos', '/tarification', '/conditions-utilisation', '/confidentialite', '/sauvegardes-versions']) {
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

  test('espace personnel et À propos, sans espace de gestion', async ({ page }) => {
    const n = nav(page)
    await expect(n.getByRole('link', { name: 'Mes bulletins' })).toBeVisible()
    await expect(n.getByRole('link', { name: 'Mes congés' })).toBeVisible()
    await expect(n.getByRole('button', { name: /Paie et rémunération|Administration du personnel|Configuration/ })).toHaveCount(0)
    await expect(n.getByRole('link', { name: 'Tableau de bord' })).toHaveCount(0)
    await n.getByRole('button', { name: /^À propos/ }).click()
    await expect(n.getByRole('link', { name: 'Aide et guide utilisateur' })).toBeVisible()
    await expect(n.getByRole('link', { name: 'Politique de confidentialité' })).toBeVisible()
    await expect(n.getByRole('link', { name: 'Tarification et services' })).toHaveCount(0) // réservé aux rôles rh et paie
    await expect(n.getByRole('link', { name: 'Sauvegardes et versions' })).toHaveCount(0)
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
