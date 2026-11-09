import { existsSync, readFileSync } from 'node:fs'
import { test as setup } from '@playwright/test'
import { login, SIM_ROLES, stateFile, type SimRole } from './sim-helpers'

/** Session enregistrée encore valable (au moins 10 minutes) : on évite une nouvelle connexion (quota et verrouillage de l'API). */
function sessionValide(role: SimRole): boolean {
  const f = stateFile(role)
  if (!existsSync(f)) return false
  try {
    const st = JSON.parse(readFileSync(f, 'utf8'))
    const item = st.origins?.flatMap((o: { localStorage: { name: string; value: string }[] }) => o.localStorage).find((x: { name: string }) => x.name === 'sb-localhost-auth-token')
    const exp = Number(JSON.parse(item.value).expires_at)
    return exp - Date.now() / 1000 > 600
  } catch {
    return false
  }
}

// Une connexion par rôle, et seulement si la session enregistrée a expiré.
// L'API limite à 30 connexions par 15 minutes et par adresse, et verrouille toute l'adresse pendant 30 minutes après les échecs.
for (const role of SIM_ROLES) {
  setup(`connexion sim ${role}`, async ({ page }) => {
    if (sessionValide(role)) return
    await login(page, role)
    await page.context().storageState({ path: stateFile(role) })
  })
}
