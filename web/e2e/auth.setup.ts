import { test as setup } from '@playwright/test'
import { login, stateFile, type QaRole } from './helpers'

// Une seule connexion par rôle et par exécution : l'API limite les connexions à 30 par 15 minutes et par IP.
// Les sessions sont enregistrées dans e2e/.auth (hors Git) et réutilisées par tous les tests.
for (const role of ['admin', 'manager', 'salarie'] as QaRole[]) {
  setup(`connexion ${role}`, async ({ page }) => {
    await login(page, role)
    await page.context().storageState({ path: stateFile(role) })
  })
}
