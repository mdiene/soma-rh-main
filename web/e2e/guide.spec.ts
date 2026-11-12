import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { expect, test } from '@playwright/test'
import { collectPageErrors, stateFile } from './helpers'

// Onglet « Documentation utilisateur » (Paramètres) : sommaire complet, pages lisibles, images chargées, liens internes. Lecture seule.
// Rôle : administrateur (can() lui ouvre les Paramètres, comme à rh et paie).
const docs = JSON.parse(readFileSync(fileURLToPath(new URL('../../docs/docs.json', import.meta.url)), 'utf8'))
const slugs: string[] = docs.navigation.groups.find((g: { group: string }) => g.group === 'Guide utilisateur').pages.map((p: string) => p.replace(/^guide-utilisateur\//, ''))

test.use({ storageState: stateFile('admin') })

test('le sommaire affiche toutes les pages de docs.json et chaque page s\'ouvre avec ses images', async ({ page }) => {
  test.setTimeout(240_000)
  const erreurs = collectPageErrors(page)
  await page.goto('/parametres?onglet=documentation')
  const sommaire = page.getByRole('navigation', { name: 'Pages du guide' })
  await expect(sommaire.getByRole('button')).toHaveCount(slugs.length, { timeout: 30_000 })

  for (let i = 0; i < slugs.length; i++) {
    const bouton = sommaire.getByRole('button').nth(i)
    const titre = (await bouton.innerText()).trim()
    await bouton.click()
    const article = page.locator('article')
    await expect(article.getByRole('heading', { level: 2 }).first(), `page ${slugs[i]}`).toHaveText(titre)
    const images = article.locator('img')
    const n = await images.count()
    for (let k = 0; k < n; k++) {
      const img = images.nth(k)
      await img.scrollIntoViewIfNeeded()
      await expect.poll(() => img.evaluate((el: HTMLImageElement) => el.complete && el.naturalWidth > 0), { message: `image ${k + 1} de ${slugs[i]} cassée`, timeout: 15_000 }).toBe(true)
    }
  }
  expect(erreurs).toEqual([])
})

test('un lien interne change de page', async ({ page }) => {
  await page.goto('/parametres?onglet=documentation')
  const sommaire = page.getByRole('navigation', { name: 'Pages du guide' })
  await expect(sommaire.getByRole('button').first()).toBeVisible({ timeout: 30_000 })
  await sommaire.getByRole('button', { name: 'Premiers pas', exact: true }).click()
  const article = page.locator('article')
  await expect(article.getByRole('heading', { level: 2 }).first()).toHaveText('Premiers pas')
  await article.getByRole('button', { name: 'Rôles et droits' }).first().click()
  await expect(article.getByRole('heading', { level: 2 }).first()).toHaveText('Rôles et droits')
})

// Le guide est ouvert à tous les rôles par « Aide et guide utilisateur » (le salarié et le manager n'ont pas les Paramètres).
for (const role of ['salarie', 'manager'] as const) {
  test.describe(`aide · ${role}`, () => {
    test.use({ storageState: stateFile(role) })
    test('le menu propose l\'aide, la page s\'ouvre et les images se chargent', async ({ page }) => {
      await page.goto('/')
      await page.getByRole('navigation', { name: 'Navigation principale' }).getByRole('link', { name: 'Aide et guide utilisateur' }).click()
      await expect(page).toHaveURL(/\/aide$/)
      await expect(page.getByRole('heading', { level: 1, name: 'Aide et guide utilisateur' })).toBeVisible()
      const sommaire = page.getByRole('navigation', { name: 'Pages du guide' })
      await expect(sommaire.getByRole('button')).toHaveCount(slugs.length, { timeout: 30_000 })
      await sommaire.getByRole('button', { name: 'Parcours du salarié', exact: true }).click()
      const img = page.locator('article img').first()
      await expect.poll(() => img.evaluate((el: HTMLImageElement) => el.complete && el.naturalWidth > 0)).toBe(true)
    })
  })
}
