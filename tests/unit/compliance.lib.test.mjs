// Tests de la logique pure du Centre de conformité (web/src/lib/compliance.ts) : conversions taux <-> pourcentage, bornes, lignes de barème.
// Usage : node --test tests/unit/compliance.lib.test.mjs
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { execFileSync } from 'node:child_process'
import { mkdtempSync, rmSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join, resolve } from 'node:path'
import { pathToFileURL } from 'node:url'

const root = resolve(import.meta.dirname, '..', '..')
const dir = mkdtempSync(join(tmpdir(), 'cmp-'))
const out = join(dir, 'cmp.mjs')
execFileSync(process.execPath, [join(root, 'web/node_modules/esbuild/bin/esbuild'), join(root, 'web/src/lib/compliance.ts'), '--bundle', '--platform=node', '--format=esm', `--outfile=${out}`, '--log-level=error'], { stdio: 'inherit' })
const c = await import(pathToFileURL(out).href)
process.on('exit', () => rmSync(dir, { recursive: true, force: true }))

test('un taux est saisi en pourcentage et stocké en fraction, sans erreur d\'arrondi', () => {
  for (const v of [0.07, 0.145, 0.33, 0.056, 0.6666666667, 0.0001]) {
    assert.equal(c.fromInput(c.toInput(v, 'taux'), 'taux'), v)
  }
  assert.equal(c.fromInput('14,5', 'taux'), 0.145)
  assert.equal(c.toInput(0.07, 'taux'), '7')
})

test('une saisie illisible donne NaN, une saisie vide donne null', () => {
  assert.ok(Number.isNaN(c.fromInput('abc')))
  assert.ok(Number.isNaN(c.fromInput('12,3,4')))
  assert.equal(c.fromInput('  '), null)
  assert.equal(c.fromInput('63 000'), 63000)
  assert.equal(c.fromInput('1,5'), 1.5)
})

test('checkValue applique les bornes du catalogue', () => {
  const k = { label: 'Taux', unit: 'taux', min_value: 0, max_value: 1 }
  assert.equal(c.checkValue(0.5, k), null)
  assert.match(c.checkValue(1.5, k), /ne peut dépasser/)
  assert.match(c.checkValue(-0.1, k), /au moins/)
  assert.match(c.checkValue(null, k), /nombre/)
  assert.match(c.checkValue(Number.NaN, k), /nombre/)
})

test('formatValue : taux en pourcentage, montants en francs', () => {
  assert.match(c.formatValue(0.07, 'taux'), /^7 %$/)
  assert.match(c.formatValue(63000, 'FCFA'), /63\s000 F$/)
  assert.equal(c.formatValue(null, 'taux'), '—')
})

test('monthToDate / dateToMonth', () => {
  assert.equal(c.monthToDate('2027-01'), '2027-01-01')
  assert.equal(c.monthToDate(''), undefined)
  assert.equal(c.dateToMonth('2027-01-01'), '2027-01')
})

const quotite = c.SCALE_GROUPS.QUOTITE_PRINCIPAL[0].cols

test('aller-retour des lignes d\'un barème : valeurs identiques, clés techniques conservées', () => {
  const lines = [
    { lower_bound: 0, upper_bound: 50000, rate: 0.1, source_code: 'CPC_381' },
    { lower_bound: 50000, upper_bound: null, rate: 0.25, source_code: 'CPC_381' },
  ]
  const { lines: back, errors } = c.fromRows(c.toRows(lines, quotite), quotite)
  assert.deepEqual(errors, [])
  assert.deepEqual(back, lines)
})

test('fromRows signale les saisies manquantes ou illisibles, ligne par ligne', () => {
  const rows = c.toRows([{ lower_bound: 0, upper_bound: null, rate: 0.1 }], quotite)
  rows[0].cells.rate = ''
  rows[0].cells.lower_bound = 'x'
  const { errors } = c.fromRows(rows, quotite)
  assert.equal(errors.length, 2)
  assert.match(errors.join(' '), /Ligne 1/)
})

test('l\'impôt a trois groupes et la majoration des heures supplémentaires ne propose que son taux à modifier', () => {
  assert.deepEqual(c.SCALE_GROUPS.IR.map((g) => g.key), ['brackets', 'reductions', 'trimf'])
  const hs = c.SCALE_GROUPS.HS[0]
  assert.ok(hs.fixedRows)
  assert.deepEqual(hs.cols.filter((x) => !x.readOnly).map((x) => x.key), ['rate_uplift'])
})

test('toutes les natures de barème du catalogue ont une mise en page', () => {
  for (const code of ['IR', 'HS', 'PREAVIS', 'QUOTITE_PRINCIPAL', 'QUOTITE_SUPPLEMENTAIRE', 'LICENCIEMENT', 'RETRAITE']) {
    assert.ok(c.SCALE_GROUPS[code]?.length, code)
  }
})
