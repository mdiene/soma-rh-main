import { defineConfig, devices } from '@playwright/test'

// Simulation 10 -> 200 salariés (rejeu Playwright de la simulation menée au navigateur).
// Lancer : npx playwright test -c playwright.sim.config.ts
// Un seul worker, une connexion par rôle, tests enchaînés dans l'ordre des fichiers.
export default defineConfig({
  testDir: './e2e/sim',
  timeout: 20 * 60_000,
  workers: 1,
  fullyParallel: false,
  reporter: [['list'], ['html', { open: 'never', outputFolder: 'playwright-report-sim' }]],
  use: {
    baseURL: process.env.E2E_URL ?? 'http://localhost:5173',
    locale: 'fr-FR',
    viewport: { width: 1280, height: 800 },
    actionTimeout: 15_000,
    navigationTimeout: 120_000,
    trace: 'retain-on-failure',
    screenshot: 'only-on-failure',
  },
  projects: [
    { name: 'sim-setup', testMatch: /sim\.setup\.ts/ },
    { name: 'sim', use: { ...devices['Desktop Chrome'], viewport: { width: 1280, height: 800 } }, dependencies: ['sim-setup'], testIgnore: /sim\.setup\.ts/ },
  ],
  webServer: { command: 'npm run dev', url: 'http://localhost:5173', reuseExistingServer: true, timeout: 60_000 },
})
