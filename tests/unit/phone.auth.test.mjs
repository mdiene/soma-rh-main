import test from 'node:test'
import assert from 'node:assert/strict'
import { passwordProblem, parseBirthDate, phoneToEmail, isPhoneEmail, emailToPhone, createLoginLimiter, hashToken } from '../../api/phone.mjs'

const ctx = { phone: '+221771234567', firstName: 'Awa', lastName: 'Diop', employeeNumber: 'S0042', birthDate: '1990-03-15' }

test('mot de passe : 5 à 8 lettres ou chiffres', () => {
  assert.equal(passwordProblem('Kx9pQ', ctx), null)
  assert.equal(passwordProblem('Kx9pQ2zT', ctx), null)
  for (const bad of ['Kx9p', 'Kx9pQ2zTa', 'Kx9 pQ', 'Kx9p!Q', 'Kéx9pQ', '', null, undefined]) {
    assert.match(passwordProblem(bad, ctx), /invalide/, String(bad))
  }
})

test('mot de passe : refus des mots de passe triviaux', () => {
  for (const bad of ['12345', '123456', '00000', 'aaaaaa', '98765', 'qwerty', '71234', '15031990', 'awadiop', 'S0042']) {
    const r = passwordProblem(bad, ctx)
    assert.ok(r, `${bad} devrait être refusé`)
  }
  assert.equal(passwordProblem('Diop1', ctx), null) // pas identique au nom : accepté
})

test('adresse technique du compte téléphone', () => {
  const e = phoneToEmail('+221771234567')
  assert.equal(e, '221771234567@tel.soma-rh.invalid')
  assert.ok(isPhoneEmail(e) && isPhoneEmail(e.toUpperCase()))
  assert.ok(!isPhoneEmail('rh@soma.sn') && !isPhoneEmail(undefined))
  assert.equal(emailToPhone(e), '+221771234567')
})

test('date de naissance', () => {
  assert.equal(parseBirthDate('1990-03-15'), '1990-03-15')
  for (const bad of ['15/03/1990', '', null, '1990-3-5']) assert.equal(parseBirthDate(bad), null)
})

test('verrouillage progressif par clé, sans effet sur les autres clés', () => {
  let t = 0
  const l = createLoginLimiter({ now: () => t })
  for (let i = 0; i < 4; i++) assert.equal(l.fail('a'), false)
  assert.equal(l.fail('a'), true)
  assert.equal(l.retryAfter('a'), 60)
  assert.equal(l.retryAfter('b'), 0)            // RPR-03 : pas de blocage collectif
  t += 61_000
  assert.equal(l.retryAfter('a'), 0)
  for (let i = 0; i < 5; i++) l.fail('a')
  assert.equal(l.retryAfter('a'), 120)          // palier suivant : 2 min
  l.success('a')
  assert.equal(l.retryAfter('a'), 0)
})

test('jeton haché de façon stable', () => {
  assert.equal(hashToken('x'), hashToken('x'))
  assert.notEqual(hashToken('x'), 'x')
})
