// Tests des garde-fous de saisie de paie (web/src/lib/payrollGuards.ts) — Node, sans navigateur.
// Usage : node --test tests/unit/payroll.guards.test.mjs
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { execFileSync } from 'node:child_process'
import { mkdtempSync, rmSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join, resolve } from 'node:path'
import { pathToFileURL } from 'node:url'

const root = resolve(import.meta.dirname, '..', '..')
const dir = mkdtempSync(join(tmpdir(), 'payroll-guards-'))
const out = join(dir, 'guards.mjs')
execFileSync(process.execPath, [join(root, 'web/node_modules/esbuild/bin/esbuild'), join(root, 'web/src/lib/payrollGuards.ts'), '--bundle', '--platform=node', '--format=esm', `--outfile=${out}`, '--log-level=error'], { stdio: 'inherit' })
const g = await import(pathToFileURL(out).href)
process.on('exit', () => rmSync(dir, { recursive: true, force: true }))

// Valeurs fictives de test, volontairement sans rapport avec les paramètres légaux réels.
const ok = () => ({
  monthly_hours: 170, smig_hourly: 100, cfce_rate: 0.03,
  ipres_rg_ceiling: 400000, ipres_rg_rate: 0.14, ipres_rg_employee_share: 0.4,
  ipres_rc_ceiling: 1200000, ipres_rc_rate: 0.06, ipres_rc_employee_share: 0.4,
  css_ceiling: 60000, css_af_rate: 0.07, css_at_rate: 0.05,
  ipm_ceiling: 10000, ipm_rate: 0.05, ipm_employee_share: 0.5,
})

test('SMIG mensuel = taux horaire × heures ; 0 si une valeur manque', () => {
  assert.equal(g.monthlyMinimumWage({ smig_hourly: 100, monthly_hours: 170 }), 17000)
  assert.equal(g.monthlyMinimumWage({ smig_hourly: null, monthly_hours: 170 }), 0)
})

test('salaire de base : sous le SMIG = alerte ; égal ou au-dessus, vide ou nul = rien ; négatif = erreur', () => {
  const s = { smig_hourly: 100, monthly_hours: 170 }
  assert.equal(g.checkBaseSalary(16999, s)[0].level, 'alerte')
  assert.deepEqual(g.checkBaseSalary(17000, s), [])
  assert.deepEqual(g.checkBaseSalary(null, s), [])
  assert.deepEqual(g.checkBaseSalary(0, s), [])
  assert.equal(g.checkBaseSalary(-1, s)[0].level, 'erreur')
})

test('paramètres cohérents : aucun avertissement', () => {
  assert.deepEqual(g.checkRateSettings(ok(), ok()), [])
})

test('un taux saisi en pourcentage (3 au lieu de 0,03) est refusé', () => {
  const r = g.checkRateSettings({ ...ok(), cfce_rate: 3 })
  assert.equal(r.length, 1); assert.equal(r[0].field, 'cfce_rate'); assert.equal(r[0].level, 'erreur')
})

test('un plafond nul ou négatif, ou un champ manquant, est une erreur', () => {
  assert.equal(g.checkRateSettings({ ...ok(), css_ceiling: 0 })[0].field, 'css_ceiling')
  assert.equal(g.checkRateSettings({ ...ok(), ipm_rate: null })[0].field, 'ipm_rate')
})

test('plafond cadres inférieur ou égal au régime général : erreur', () => {
  const r = g.checkRateSettings({ ...ok(), ipres_rc_ceiling: 400000 })
  assert.ok(r.some((w) => w.field === 'ipres_rc_ceiling' && w.level === 'erreur'))
})

test('baisse d\'un taux ou d\'un plafond par rapport à la version précédente : alerte, pas erreur', () => {
  const r = g.checkRateSettings({ ...ok(), css_ceiling: 50000 }, ok())
  assert.equal(r.length, 1); assert.equal(r[0].level, 'alerte'); assert.equal(r[0].field, 'css_ceiling')
})

test('mode d\'enregistrement : date postérieure = nouvelle version, même date = correction, antérieure = refus', () => {
  assert.equal(g.settingsSaveMode('2027-01-01', '2026-01-01'), 'nouvelle_version')
  assert.equal(g.settingsSaveMode('2026-01-01', '2026-01-01'), 'correction')
  assert.equal(g.settingsSaveMode('2025-12-31', '2026-01-01'), 'refus')
})
