import { mkdirSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import type { Page } from '@playwright/test'
import { maskSecrets } from './mask.mjs'

const DIR = fileURLToPath(new URL('../../../../docs/guide-utilisateur/captures/', import.meta.url))
const used = new Set<string>()

/**
 * Capture destinée au guide : masque les champs sensibles, attend un écran stable, enregistre en 1280×800.
 * Refuse un nom sans tiret, hors [a-z0-9-], ou déjà utilisé pendant cette exécution.
 */
export async function capture(page: Page, name: string): Promise<string> {
  if (!/^[a-z0-9]+(-[a-z0-9]+)+$/.test(name)) throw new Error(`Nom de capture invalide « ${name} » : minuscules, chiffres et au moins un tiret`)
  if (used.has(name)) throw new Error(`Nom de capture en double « ${name} »`)
  used.add(name)
  await page.setViewportSize({ width: 1280, height: 800 })
  await page.waitForLoadState('networkidle')
  await page.locator('[role=progressbar], [aria-busy=true], .animate-spin').first().waitFor({ state: 'hidden', timeout: 15_000 }).catch(() => undefined)
  await maskSecrets(page)
  mkdirSync(DIR, { recursive: true })
  const path = `${DIR}${name}.png`
  await page.screenshot({ path })
  return path
}
