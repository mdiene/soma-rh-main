// Tests du remplacement des champs des modèles de documents (lib/documentTemplates.ts) — Node, sans navigateur.
// Usage : node tests/unit/document.templates.test.mjs
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { execFileSync } from 'node:child_process'
import { mkdtempSync, rmSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join, resolve } from 'node:path'
import { pathToFileURL } from 'node:url'

const root = resolve(import.meta.dirname, '..', '..')
const dir = mkdtempSync(join(tmpdir(), 'tpl-'))
const out = join(dir, 'tpl.mjs')
execFileSync(process.execPath, [join(root, 'web/node_modules/esbuild/bin/esbuild'), join(root, 'web/src/lib/documentTemplates.ts'), '--bundle', '--platform=node', '--format=esm', `--outfile=${out}`, '--log-level=error'], { stdio: 'inherit' })
const t = await import(pathToFileURL(out).href)
process.on('exit', () => rmSync(dir, { recursive: true, force: true }))

test('remplace les champs et retire les paragraphes vides', () => {
  const body = 'Bonjour {{prenom}} {{ nom }}.\n\n{{salaire}}\n\nFin{{e}}.'
  assert.deepEqual(t.renderTemplate(body, { prenom: 'Awa', nom: 'DIOP', salaire: '', e: 'e' }), ['Bonjour Awa DIOP.', 'Fine.'])
})

test('un champ inconnu reste visible, jamais effacé', () => {
  assert.deepEqual(t.renderTemplate('Salut {{prnom}}', { prenom: 'Awa' }), ['Salut {{prnom}}'])
})

test('unknownFields signale les fautes de frappe seulement', () => {
  assert.deepEqual(t.unknownFields('{{prenom}} {{prnom}} {{prnom}} {{nom}}'), ['prnom'])
})

test('espaces multiples réduits (champ vide au milieu d\'une phrase)', () => {
  assert.deepEqual(t.renderTemplate('A {{fonction}} depuis', { fonction: '' }), ['A depuis'])
})
