import { test, expect } from '@playwright/test'
import { as, record, rows, shot, type SimRole } from './sim-helpers'

// Droits par rôle à l'écran : pages accessibles et pages refusées, captures pour le guide.
const PAGES: Record<string, string[]> = {
  admin: ['/salaries', '/paie', '/paie/gouvernance', '/parametres', '/journal', '/centre-conformite'],
  rh: ['/salaries', '/conges', '/dossiers-salaries', '/equipes'],
  paie: ['/paie', '/paie/variables', '/paie/gouvernance', '/etats'],
  mgr_1: ['/mon-equipe', '/demandes', '/conges'],
  sal_1: ['/mon-espace', '/mes-bulletins'],
}
const INTERDITES: Record<string, string[]> = {
  mgr_1: ['/paie', '/parametres', '/journal'],
  sal_1: ['/salaries', '/paie', '/parametres', '/journal', '/mon-equipe'],
}

for (const role of Object.keys(PAGES) as SimRole[]) {
  test(`pages autorisées — ${role}`, async ({ browser }) => {
    const page = await as(browser, role)
    for (const route of PAGES[role]) {
      const erreurs: string[] = []
      page.on('pageerror', (e) => erreurs.push(e.message))
      await page.goto(route)
      await page.waitForLoadState('networkidle')
      const main = (await page.locator('main').innerText()).slice(0, 300)
      const ok = erreurs.length === 0 && !/accès refusé|non autorisé|introuvable/i.test(main)
      record(`UC-ROLE-${role}-${route}`, ok ? 'VERT' : 'ROUGE', ok ? '' : `${erreurs.join(';')} ${main.slice(0, 80)}`)
      await shot(page, `role-${role}${route.replace(/\//g, '-')}`)
    }
  })
}

for (const role of Object.keys(INTERDITES) as SimRole[]) {
  test(`pages refusées — ${role}`, async ({ browser }) => {
    const page = await as(browser, role)
    for (const route of INTERDITES[role]) {
      await page.goto(route)
      await page.waitForLoadState('networkidle')
      const main = (await page.locator('main').innerText().catch(() => '')).slice(0, 400)
      const refus = !page.url().endsWith(route) || /accès|refus|non autoris|droits/i.test(main)
      record(`UC-INTERDIT-${role}-${route}`, refus ? 'VERT' : 'ROUGE', refus ? '' : 'page affichée alors que le rôle ne devrait pas y accéder')
    }
  })
}

test('isolation salarié : un salarié ne voit que ses bulletins', async ({ browser }) => {
  const page = await as(browser, 'sal_1')
  const bulletins = await rows(page, 'salary_slips?select=id')
  record('UC-ISOLATION-sal_1', bulletins.length >= 1 && bulletins.length <= 12 ? 'VERT' : 'ROUGE', `${bulletins.length} bulletins visibles`)
  expect(bulletins.length).toBeLessThanOrEqual(12)
})
