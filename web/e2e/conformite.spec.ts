import { expect, test } from '@playwright/test'
import { collectPageErrors, stateFile, start } from './helpers'

// Centre de conformité : constantes, barèmes, file de validation. Lecture seule : les fenêtres de saisie sont ouvertes puis annulées.
test.describe('administrateur', () => {
  test.use({ storageState: stateFile('admin') })

  test('l\'entrée de menu mène au centre et la page s\'affiche sans erreur', async ({ page }) => {
    const errors = collectPageErrors(page)
    await start(page)
    await page.getByRole('navigation', { name: 'Navigation principale' }).getByRole('button', { name: /^Configuration/ }).click()
    await page.getByRole('navigation', { name: 'Navigation principale' }).getByRole('link', { name: /Centre de conformité/ }).click()
    await expect(page).toHaveURL(/\/centre-conformite$/)
    await expect(page.getByRole('heading', { level: 1, name: 'Centre de conformité' })).toBeVisible()
    await expect(page.getByRole('tab', { name: 'Cohérence' })).toHaveAttribute('aria-selected', 'true')
    await page.getByRole('tab', { name: 'Constantes et barèmes' }).click()
    await expect(page.getByText('Les modifications s’appliqueront uniquement aux paies non encore calculées.')).toBeVisible()
    expect(errors).toEqual([])
  })

  test('chaque constante affiche sa valeur d\'origine et le texte de loi', async ({ page }) => {
    await start(page, '/centre-conformite?onglet=constantes')
    await expect(page.getByRole('heading', { name: 'Cotisations sociales' })).toBeVisible()
    const row = page.getByRole('button', { name: 'Plafond CSS (mensuel)', exact: true })
    await row.click()
    await expect(row).toHaveAttribute('aria-expanded', 'true')
    await expect(page.getByText('Ce que prévoit la loi').first()).toBeVisible()
    await expect(page.getByRole('columnheader', { name: 'Valeur d’origine' }).first()).toBeVisible()
  })

  test('« Modifier » ouvre la saisie contrôlée, « Réinitialiser » est inactif sur une valeur d\'origine', async ({ page }) => {
    await start(page, '/centre-conformite?onglet=constantes')
    await page.getByRole('button', { name: 'Modifier Plafond CSS (mensuel)' }).click()
    const dialog = page.getByRole('dialog', { name: /Modifier : Plafond CSS/ })
    await expect(dialog).toBeVisible()
    await dialog.getByLabel(/Nouvelle valeur/).fill('abc')
    await expect(dialog.getByRole('button', { name: 'Appliquer' })).toBeDisabled()
    await dialog.getByRole('button', { name: 'Annuler' }).click()
    await expect(dialog).toHaveCount(0)
    await expect(page.getByRole('button', { name: 'Réinitialiser Plafond CSS (mensuel) à la valeur d’origine' })).toBeDisabled()
  })

  test('les barèmes sont listés avec leur version et leurs lignes', async ({ page }) => {
    await start(page, '/centre-conformite?onglet=constantes')
    await expect(page.getByRole('heading', { name: 'Barèmes' })).toBeVisible()
    const hs = page.getByRole('button', { name: 'Majorations des heures supplémentaires', exact: true })
    await hs.click()
    await expect(page.getByRole('table', { name: 'Lignes du barème en vigueur' })).toBeVisible()
    await expect(page.getByRole('table', { name: 'Versions datées du barème' })).toBeVisible()
    await page.getByRole('button', { name: /Modifier le barème : Majorations des heures supplémentaires/ }).click()
    const dialog = page.getByRole('dialog', { name: /Nouvelle version/ })
    await expect(dialog.getByLabel(/Majoration appliquée.*ligne 1/)).toBeVisible()
    await dialog.getByRole('button', { name: 'Annuler' }).click()
  })

  test('l\'onglet « À valider » s\'ouvre et se retrouve par son adresse', async ({ page }) => {
    const errors = collectPageErrors(page)
    await start(page, '/centre-conformite?onglet=validation')
    await expect(page.getByRole('tab', { name: /^À valider/ })).toHaveAttribute('aria-selected', 'true')
    await expect(page.getByRole('heading', { name: /^En attente de décision/ })).toBeVisible()
    await expect(page.getByRole('heading', { name: 'Historique' })).toBeVisible()
    expect(errors).toEqual([])
  })
})

for (const role of ['manager', 'salarie'] as const) {
  test.describe(role, () => {
    test.use({ storageState: stateFile(role) })
    test('le centre est inaccessible', async ({ page }) => {
      await start(page)
      await page.goto('/centre-conformite')
      await expect(page).not.toHaveURL(/\/centre-conformite/)
    })
  })
}
