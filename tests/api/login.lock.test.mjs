// RPR-03 : le verrouillage de la connexion par e-mail est par couple compte + adresse, jamais collectif.
// Deux comptes synthétiques sont créés puis supprimés. Prérequis : base locale, passerelle à jour.
// Lancer : node --test tests/api/login.lock.test.mjs   (LOGIN_TEST_API pour viser une autre passerelle, défaut http://localhost:8001)
import { test, after } from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { createRequire } from 'node:module'

const read = (p) => Object.fromEntries(readFileSync(new URL(p, import.meta.url), 'utf8').split(/\r?\n/)
  .filter((l) => /^[A-Z_0-9]+=/.test(l)).map((l) => [l.slice(0, l.indexOf('=')), l.slice(l.indexOf('=') + 1).trim()]))
const API = process.env.LOGIN_TEST_API ?? 'http://localhost:8001'
const { Client } = createRequire(new URL('../../api/package.json', import.meta.url))('pg')
const db = new Client({ connectionString: `postgres://soma:${read('../../.env').POSTGRES_PASSWORD}@127.0.0.1:5432/soma_rh` })
await db.connect()

// identifiants uniques à chaque exécution : le verrou de la passerelle est en mémoire et survit entre deux exécutions
const RUN = Date.now().toString(36)
const A = `ve${RUN}a@verrou.test.invalid`, B = `ve${RUN}b@verrou.test.invalid`, PW = 'Mot-de-passe-de-test-1'
const cleanup = async () => {
  await db.query('delete from auth.users where email = any($1)', [[A, B]])
  await db.query(`delete from public.audit_events where action = 'verrouillage_connexion' and after_data->>'account' like '%@verrou.test.invalid'`)
}
await cleanup()
for (const email of [A, B]) {
  await db.query(`insert into auth.users (id, email, encrypted_password, email_confirmed_at) values (gen_random_uuid(), $1, crypt($2, gen_salt('bf')), now())`, [email, PW])
}
after(async () => { await cleanup(); await db.end() })

const login = async (email, password) => {
  const r = await fetch(`${API}/auth/v1/token?grant_type=password`, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ email, password }) })
  return { status: r.status, body: await r.json().catch(() => ({})) }
}

test('cinq échecs sur le compte A le verrouillent, même avec le bon mot de passe', async () => {
  for (let i = 0; i < 5; i++) assert.equal((await login(A, 'mauvais')).status, 400)
  const r = await login(A, PW)
  assert.equal(r.status, 429)
  assert.match(r.body.message, /réessayez dans \d+ secondes/)
  // le verrouillage est journalisé (compte masqué) pour l'alerte de l'administrateur
  const n = (await db.query(`select count(*)::int n from public.audit_events where action = 'verrouillage_connexion' and after_data->>'account' = 've***@verrou.test.invalid'`)).rows[0].n
  assert.ok(n >= 1, 'verrouillage non journalisé')
})

test('le compte B, depuis la même adresse, se connecte normalement', async () => {
  assert.equal((await login(B, PW)).status, 200)
})

test('un identifiant inconnu est traité comme un compte réel (même réponse, même verrou)', async () => {
  const inconnu = `in${RUN}@verrou.test.invalid`
  for (let i = 0; i < 5; i++) assert.equal((await login(inconnu, 'x')).status, 400)
  assert.equal((await login(inconnu, 'x')).status, 429)
})

test('une connexion réussie remet le compteur à zéro', async () => {
  for (let i = 0; i < 3; i++) await login(B, 'mauvais')
  assert.equal((await login(B, PW)).status, 200)
  for (let i = 0; i < 3; i++) assert.equal((await login(B, 'mauvais')).status, 400) // 3 échecs seulement : pas de verrou
})
