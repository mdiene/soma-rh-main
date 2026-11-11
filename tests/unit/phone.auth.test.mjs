// Connexion par téléphone : règle du mot de passe (5 à 8, lettres/chiffres, pas de trivial), adresse technique,
// verrouillage progressif par couple numéro + adresse, et accord entre la passerelle (api/phone.mjs) et l'écran (web/src/lib/phoneAuth.ts).
// Usage : node --test tests/unit/phone.auth.test.mjs
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { execFileSync } from 'node:child_process'
import { mkdtempSync, rmSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join, resolve } from 'node:path'
import { pathToFileURL } from 'node:url'
import * as srv from '../../api/phone.mjs'

const root = resolve(import.meta.dirname, '..', '..')
const dir = mkdtempSync(join(tmpdir(), 'phone-'))
const out = join(dir, 'phoneAuth.mjs')
execFileSync(process.execPath, [join(root, 'web/node_modules/esbuild/bin/esbuild'), join(root, 'web/src/lib/phoneAuth.ts'), '--bundle', '--platform=node', '--format=esm',
  '--define:import.meta.env={"VITE_API_URL":"http://x","VITE_API_PUBLIC_KEY":"k"}', '--banner:js=import {createRequire as cr} from "module"; const require = cr(import.meta.url);',
  `--outfile=${out}`, '--log-level=error'], { stdio: 'inherit' })
const web = await import(pathToFileURL(out).href)
process.on('exit', () => rmSync(dir, { recursive: true, force: true }))

const ctx = { phone: '+221771234567', firstName: 'Awa', lastName: 'Diop', employeeNumber: 'EMP0042', birthDate: '1990-05-17' }

test('mot de passe : 5 à 8 lettres ou chiffres, sans espace ni caractère spécial', () => {
  for (const ok of ['Kx7mP', 'abcde9', 'Zz9yQ1x2', 'a1b2c']) assert.equal(srv.passwordProblem(ok, ctx), null, ok)
  for (const bad of ['abcd', 'abcdefghi', 'ab cde', 'ab-cde', 'abcdé', 'abc_de', '', null, undefined, 12345])
    assert.match(srv.passwordProblem(bad, ctx) ?? '', /5 à 8/, String(bad))
  for (const p of ['Kx7mP', 'ab cde']) assert.equal(web.PASSWORD_PATTERN.test(p), srv.passwordProblem(p) === null)
})

test('mots de passe triviaux refusés : suites, répétitions, numéro, nom, matricule, date de naissance', () => {
  for (const t of ['12345', '123456', '00000', 'aaaaaa', '98765', 'azerty', '1234567', '12345678', '7123456', 'EMP0042', 'emp0042', 'AwaDiop', '17051990', '170590'])
    assert.match(srv.passwordProblem(t, ctx) ?? '', /trop facile/, t)
  assert.equal(srv.passwordProblem('Kx7mP', ctx), null)
})

test('adresse technique : même forme côté serveur et côté écran, numéros invalides refusés', () => {
  for (const n of ['77 123 45 67', '+221771234567', '00221 77 123 45 67', '771234567', '+221-77-123-45-67'])
    assert.equal(web.phoneToEmail(n), '221771234567@tel.soma-rh.invalid', n)
  assert.equal(srv.phoneToEmail('+221771234567'), '221771234567@tel.soma-rh.invalid')
  assert.equal(srv.emailToPhone('221771234567@tel.soma-rh.invalid'), '+221771234567')
  for (const n of ['331234567', '7712345', '+33612345678', '', 'abc']) assert.equal(web.phoneToEmail(n), null, n)
  assert.ok(srv.isPhoneEmail('221771234567@TEL.soma-rh.invalid') && !srv.isPhoneEmail('a@b.com'))
})

test('date de naissance saisie et hachages', () => {
  assert.equal(srv.parseBirthDate('1990-05-17'), '1990-05-17')
  for (const bad of ['17/05/1990', '', null, '1990-5-17']) assert.equal(srv.parseBirthDate(bad), null)
  assert.notEqual(srv.hashIp('1.2.3.4', 's'), '1.2.3.4')
  assert.equal(srv.hashIp('1.2.3.4', 's'), srv.hashIp('1.2.3.4', 's'))
  assert.notEqual(srv.hashIp('1.2.3.4', 's'), srv.hashIp('1.2.3.5', 's'))
  assert.match(srv.hashToken('abc'), /^[0-9a-f]{64}$/)
})

test('verrouillage progressif : 5 échecs = 1 min, puis 2, 4… plafonné ; par couple, jamais collectif', () => {
  let t = 0
  const l = srv.createLoginLimiter({ now: () => t })
  const A = '1.1.1.1|221771234567@x', B = '1.1.1.1|221770000000@x'
  for (let i = 0; i < 4; i++) assert.equal(l.fail(A), false)
  assert.equal(l.retryAfter(A), 0)
  assert.equal(l.fail(A), true)
  assert.equal(l.retryAfter(A), 60)
  assert.equal(l.retryAfter(B), 0, 'un autre numéro depuis la même adresse reste libre')
  t += 61_000
  assert.equal(l.retryAfter(A), 0)
  for (let i = 0; i < 4; i++) l.fail(A)
  assert.equal(l.fail(A), true)
  assert.equal(l.retryAfter(A), 120, 'deuxième palier : 2 minutes')
  for (let k = 0; k < 8; k++) { t += 3_600_000; for (let i = 0; i < 5; i++) l.fail(A) }
  assert.ok(l.retryAfter(A) <= 1800, 'plafond de 30 minutes')
  l.success(A)
  assert.equal(l.retryAfter(A), 0)
})

test('adresse du client : X-Forwarded-For ignoré sans proxy de confiance, entrée de droite sinon', () => {
  assert.equal(srv.clientAddress('10.0.0.1', '1.2.3.4', false), '10.0.0.1')
  assert.equal(srv.clientAddress('10.0.0.1', '6.6.6.6, 1.2.3.4', true), '1.2.3.4') // « 6.6.6.6 » vient du client
  assert.equal(srv.clientAddress('10.0.0.1', undefined, true), '10.0.0.1')
  assert.equal(srv.clientAddress(undefined, undefined, false), 'unknown')
})
