import { test, expect } from '@playwright/test'
import { record } from './sim-helpers'
import { capture } from './helpers/capture'

// Bloc A — écran de connexion (sans session) : formulaire e-mail et onglet « Téléphone ». Aucun identifiant saisi.
test('A · écran de connexion et onglet Téléphone', async ({ browser }) => {
  const ctx = await browser.newContext({ locale: 'fr-FR', viewport: { width: 1280, height: 800 } })
  const page = await ctx.newPage()
  await page.goto('/')
  await expect(page.getByRole('button', { name: 'Se connecter' })).toBeVisible({ timeout: 20_000 })
  await capture(page, 'connexion-email')
  const tel = page.getByRole('tab', { name: /Téléphone/ }).or(page.getByRole('button', { name: /Téléphone/ })).first()
  await tel.click()
  await page.waitForTimeout(800)
  await capture(page, 'connexion-telephone')
  record('UC-A-CONNEXION', 'VERT', 'formulaire e-mail et onglet Téléphone affichés')
  await ctx.close()
})
