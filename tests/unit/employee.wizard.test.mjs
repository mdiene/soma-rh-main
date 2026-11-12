// Tests des règles de l'assistant de création d'un salarié (web/src/lib/employeeWizard.ts) — Node, sans navigateur.
// Usage : node --test tests/unit/employee.wizard.test.mjs
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { execFileSync } from 'node:child_process'
import { mkdtempSync, rmSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join, resolve } from 'node:path'
import { pathToFileURL } from 'node:url'

const root = resolve(import.meta.dirname, '..', '..')
const dir = mkdtempSync(join(tmpdir(), 'employee-wizard-'))
const out = join(dir, 'wizard.mjs')
execFileSync(process.execPath, [join(root, 'web/node_modules/esbuild/bin/esbuild'), join(root, 'web/src/lib/employeeWizard.ts'), '--bundle', '--platform=node', '--format=esm', `--outfile=${out}`, '--log-level=error'])
const w = await import(pathToFileURL(out).href)
process.on('exit', () => rmSync(dir, { recursive: true, force: true }))

const fields = (issues) => issues.map((i) => i.field).sort()

test('la rémunération n\'est proposée qu\'au service paie', () => {
  assert.ok(!w.stepsFor(false).some((s) => s.id === 'remuneration'))
  assert.ok(w.stepsFor(true).some((s) => s.id === 'remuneration'))
  assert.equal(w.stepsFor(false).at(-1).id, 'revue')
  assert.equal(w.stepsFor(true).length, w.stepsFor(false).length + 1)
})

test('identité : prénom et nom obligatoires, dates cohérentes', () => {
  assert.deepEqual(fields(w.validateStep('identite', {})), ['first_name', 'last_name'])
  assert.deepEqual(w.validateStep('identite', { first_name: 'A', last_name: 'B' }), [])
  assert.deepEqual(fields(w.validateStep('identite', { first_name: 'A', last_name: 'B', date_of_birth: '2999-01-01' })), ['date_of_birth'])
  assert.deepEqual(fields(w.validateStep('identite', { first_name: 'A', last_name: 'B', id_issue_date: '2024-05-01', id_expiry_date: '2024-01-01' })), ['id_expiry_date'])
})

test('contrat : CDD, stage et apprentissage exigent début et fin ; CDI et journalier non', () => {
  const base = { employment_type: 'CDI', date_of_joining: '2026-11-02' }
  assert.deepEqual(w.validateStep('contrat', base), [])
  assert.deepEqual(w.validateStep('contrat', { ...base, employment_type: 'COD' }), [])
  for (const t of ['CDD', 'STAGE', 'APPRENTISSAGE']) {
    assert.deepEqual(fields(w.validateStep('contrat', { ...base, employment_type: t })), ['contract_end', 'contract_start'], t)
    assert.deepEqual(w.validateStep('contrat', { ...base, employment_type: t, contract_start: '2026-11-02', contract_end: '2027-05-02' }), [], t)
  }
  assert.deepEqual(fields(w.validateStep('contrat', { ...base, employment_type: 'CDD', contract_start: '2026-11-02', contract_end: '2026-10-01' })), ['contract_end'])
  assert.deepEqual(fields(w.validateStep('contrat', { employment_type: '', date_of_joining: '' })), ['date_of_joining', 'employment_type'])
})

test('questions selon le contrat', () => {
  assert.equal(w.contractQuestions('CDD').fixedTerm, true)
  assert.equal(w.contractQuestions('PRESTATION').fees, true)
  assert.equal(w.contractQuestions('CDI').fixedTerm, false)
  assert.equal(w.contractQuestions('CDI').note, '')
})

test('famille, paiement et rémunération', () => {
  assert.deepEqual(fields(w.validateStep('famille', { marital_status: '' })), ['marital_status'])
  assert.deepEqual(fields(w.validateStep('famille', { marital_status: 'Marié(e)', children_count: -1 })), ['children_count'])
  assert.deepEqual(fields(w.validateStep('paiement', { payment_mode: '' })), ['payment_mode'])
  assert.deepEqual(w.validateStep('remuneration', {}, { payrollRequested: false }), [])
  assert.deepEqual(fields(w.validateStep('remuneration', {}, { payrollRequested: true })), ['from_date'])
  assert.deepEqual(fields(w.validateStep('remuneration', { from_date: '2026-11-02', sursalaire: -5 }, { payrollRequested: true })), ['sursalaire'])
})

test('avertissements non bloquants : téléphone, e-mail, RIB', () => {
  assert.deepEqual(fields(w.softWarnings('coordonnees', { phone_personal: '123', email_personal: 'pas-un-mail' })), ['email_personal', 'phone_personal'])
  assert.deepEqual(w.softWarnings('coordonnees', { phone_personal: '77 123 45 67', email_personal: 'a@b.sn' }), [])
  assert.deepEqual(fields(w.softWarnings('paiement', { payment_mode: 'virement', bank_account: '' })), ['bank_account'])
  assert.deepEqual(fields(w.softWarnings('paiement', { payment_mode: 'virement', bank_account: 'SN123' })), ['bank_account'])
  assert.deepEqual(w.softWarnings('paiement', { payment_mode: 'espèces' }), [])
})

test('revue : erreurs regroupées par étape', () => {
  const r = w.reviewIssues({ employment_type: 'CDD', date_of_joining: '2026-11-02' }, ['identite', 'contrat', 'revue'])
  assert.deepEqual(r.map((x) => x.step), ['identite', 'contrat'])
  assert.deepEqual(w.reviewIssues({ first_name: 'A', last_name: 'B', employment_type: 'CDI', date_of_joining: '2026-11-02', marital_status: 'Célibataire', payment_mode: 'espèces' }, ['identite', 'famille', 'contrat', 'paiement', 'revue']), [])
})

test('charge utile sans champs vides', () => {
  assert.deepEqual(w.toPayload({ a: 'x', b: '', c: null, d: undefined, e: 0, f: false }), { a: 'x', e: 0, f: false })
})

test('premier mois complet pour la simulation du net', () => {
  assert.equal(w.firstFullMonth('2026-11-01'), '2026-11-01')
  assert.equal(w.firstFullMonth('2026-11-02'), '2026-12-01')
  assert.equal(w.firstFullMonth('2026-12-15'), '2027-01-01')
})

test('parts : aucune proposition sans règle ; calcul plafonné avec une règle d’essai', () => {
  assert.equal(w.PARTS_RULE, null)
  assert.equal(w.proposeParts(null, 'Marié(e)', 2), null)
  const rule = { base: 1, married: 1, perChild: 0.5, max: 5, trimfFollowsIr: true } // valeurs d'essai, sans rapport avec la loi
  assert.deepEqual(w.proposeParts(rule, 'Célibataire', 0), { ir: 1, trimf: 1 })
  assert.deepEqual(w.proposeParts(rule, 'Marié(e)', 3), { ir: 3.5, trimf: 3.5 })
  assert.equal(w.proposeParts(rule, 'Marié(e)', 20).ir, 5)
  assert.equal(w.proposeParts({ ...rule, trimfFollowsIr: false }, 'Marié(e)', 1).trimf, null)
})

test('doublons : nom, prénom et date de naissance, ou numéro de pièce', () => {
  const a = { first_name: 'Aïssatou', last_name: 'CISSÉ', date_of_birth: '1990-05-12', id_document_number: '1 234 567' }
  assert.ok(w.isLikelyDuplicate(a, { first_name: 'aissatou', last_name: 'Cissé', date_of_birth: '1990-05-12' }))
  assert.ok(w.isLikelyDuplicate(a, { first_name: 'Aissatou', last_name: 'Cissé', date_of_birth: null }))
  assert.ok(!w.isLikelyDuplicate(a, { first_name: 'Aissatou', last_name: 'Cissé', date_of_birth: '1985-01-01' }))
  assert.ok(!w.isLikelyDuplicate(a, { first_name: 'Mariama', last_name: 'Cissé', date_of_birth: '1990-05-12' }))
  assert.ok(w.isLikelyDuplicate({ id_document_number: '1234567' }, { first_name: 'X', last_name: 'Y', id_document_number: '1 234 567' }))
  assert.ok(!w.isLikelyDuplicate({ first_name: '', last_name: '' }, { first_name: '', last_name: '' }))
})

test('brouillon : contenu minimal, expiration et formes invalides', () => {
  assert.equal(w.draftHasContent({ employment_type: 'CDI' }), false)
  assert.equal(w.draftHasContent({ first_name: 'A' }), true)
  const base = { draft: { first_name: 'A' }, assign: {}, receipts: ['x'], index: 2, reached: 3, withPayroll: true }
  const now = 1_000_000_000_000
  const raw = w.serializeDraft(base, now)
  assert.deepEqual(w.parseDraft(raw, now + 1000)?.draft, { first_name: 'A' })
  assert.equal(w.parseDraft(raw, now + w.DRAFT_TTL_MS + 1), null)
  assert.equal(w.parseDraft('pas du json', now), null)
  assert.equal(w.parseDraft(null, now), null)
  assert.equal(w.parseDraft(JSON.stringify({ v: 2 }), now), null)
  assert.equal(w.parseDraft(raw, now - 10 * 60_000), null)
})
