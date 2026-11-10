// Parcours complet de la connexion par téléphone, contre la passerelle réelle : demande, alerte admin, autorisation,
// ouverture (seconde information), mot de passe, connexion, isolation, verrouillage, refus des rôles rh/paie.
// Données synthétiques (fiche TEL-J1), supprimées à la fin. Prérequis : base locale, passerelle, tests/.env.qa.
// Lancer : node --test tests/api/phone.journey.test.mjs   (PHONE_TEST_API pour viser une autre passerelle, défaut http://localhost:8001)
import { test, after } from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { createRequire } from 'node:module'

const read = (p) => Object.fromEntries(readFileSync(new URL(p, import.meta.url), 'utf8').split(/\r?\n/)
  .filter((l) => /^[A-Z_0-9]+=/.test(l)).map((l) => [l.slice(0, l.indexOf('=')), l.slice(l.indexOf('=') + 1).trim()]))
const qa = read('../.env.qa')
const API = process.env.PHONE_TEST_API ?? 'http://localhost:8001'
const APIKEY = read('../../web/.env.local').VITE_API_PUBLIC_KEY
const pgPass = read('../../.env').POSTGRES_PASSWORD
const { Client } = createRequire(new URL('../../api/package.json', import.meta.url))('pg')
const db = new Client({ connectionString: `postgres://soma:${pgPass}@127.0.0.1:5432/soma_rh` })
await db.connect()

// Numéro libre : les fiches de simulation portent déjà des numéros, un doublon créerait une alerte « numéro partagé »
const [free, free2] = (await db.query(`select n from generate_series(700003100, 700003199) n where not exists (select 1 from public.employees where public.phone_normalize(phone_personal) = '+221' || n::text) limit 2`)).rows.map((r) => r.n)
const PHONE = `${free}`, E164 = `+221${free}`, DOB = '1991-02-03', EMAIL = `221${free}@tel.soma-rh.invalid`
const post = async (path, body) => {
  const r = await fetch(`${API}${path}`, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(body) })
  return { status: r.status, body: await r.json().catch(() => ({})) }
}
const login = async (email, password) => post('/auth/v1/token?grant_type=password', { email, password })
const rest = async (path, token, init = {}) => {
  const r = await fetch(`${API}/rest/v1/${path}`, {
    method: init.method, headers: { apikey: APIKEY, 'content-type': 'application/json', authorization: `Bearer ${token}` },
    body: init.body && JSON.stringify(init.body),
  })
  return { status: r.status, body: await r.json().catch(() => null) }
}

async function cleanup() {
  await db.query(`delete from auth.users where email = $1`, [EMAIL])
  await db.query(`delete from public.phone_access_requests where phone_e164 = $1`, [E164])
  await db.query(`delete from public.phone_access_attempts where phone_e164 = $1 or phone_e164 is null`, [E164])
  await db.query(`delete from public.employees where last_name = 'Journey' and first_name = 'Test'`)
}
await cleanup()
const EMPNO = (await db.query(`insert into public.employees (company_id, employee_number, first_name, last_name, employment_type, date_of_joining, status, phone_personal, date_of_birth)
  select id, 'TEL-J1', 'Test', 'Journey', 'CDI', '2020-01-01', 'Active', $1, $2 from public.companies limit 1 returning employee_number`, [PHONE, DOB])).rows[0].employee_number // le matricule est attribué par la base
after(async () => { await cleanup(); await db.end() })

const admin = (await login(qa.QA_ADMIN_EMAIL, qa.QA_ADMIN_PASSWORD)).body.access_token
const rh = (await login(qa.QA_RH_EMAIL, qa.QA_RH_PASSWORD)).body.access_token
const paie = (await login(qa.QA_PAIE_EMAIL, qa.QA_PAIE_PASSWORD)).body.access_token
let reqId, token

test('numéro inconnu et numéro connu : même réponse, une seule demande créée', async () => {
  const unknown = await post('/auth/v1/phone/request', { phone: String(free2) })
  const known = await post('/auth/v1/phone/request', { phone: PHONE })
  assert.deepEqual(unknown, known)
  const list = (await rest('rpc/admin_phone_access_requests', admin, { method: 'POST', body: {} })).body
  const mine = list.filter((r) => r.employee_number === EMPNO && r.status === 'pending')
  assert.equal(mine.length, 1)
  assert.equal(mine[0].phone_masked, `+221 ${PHONE.slice(0, 2)} ••• •• ${PHONE.slice(-2)}`)
  assert.ok(!list.some((r) => r.phone_masked?.endsWith(String(free2).slice(-2)) && r.employee_number !== EMPNO), 'numéro inconnu : aucune demande')
  reqId = mine[0].id
})

test("l'alerte apparaît chez l'administrateur, pas de décision possible pour rh ni paie", async () => {
  const alerts = (await rest('rpc/phone_access_alerts', admin, { method: 'POST', body: {} })).body
  assert.ok(alerts.some((a) => a.code === 'phone_access_request' && a.employee_number === EMPNO))
  for (const t of [rh, paie]) {
    const r = await rest('rpc/admin_phone_access_decide', t, { method: 'POST', body: { p_request_id: reqId, p_authorize: true } })
    assert.ok(r.status >= 400, 'refusé')
  }
})

test("tant que rien n'est autorisé : « en attente » ; seconde information fausse refusée", async () => {
  assert.equal((await post('/auth/v1/phone/open', { phone: PHONE, second: DOB })).body.status, 'pending')
  const r = await rest('rpc/admin_phone_access_decide', admin, { method: 'POST', body: { p_request_id: reqId, p_authorize: true, p_note: 'test' } })
  assert.equal(r.status, 204)
  assert.equal((await post('/auth/v1/phone/open', { phone: PHONE, second: '1991-02-04' })).body.status, 'pending')
  const ok = await post('/auth/v1/phone/open', { phone: `+221 ${PHONE}`, second: DOB })
  assert.equal(ok.body.status, 'ready')
  token = ok.body.token
})

test('mot de passe : règle 5 à 8 lettres/chiffres, triviaux refusés, jeton à usage unique', async () => {
  for (const bad of ['1234', '123456789', 'ab cd', 'ab-cd1', '12345', 'Journey', '00000', String(free).slice(0, 8)]) {
    assert.equal((await post('/auth/v1/phone/set-password', { token, password: bad })).status, 422, bad)
  }
  assert.equal((await post('/auth/v1/phone/set-password', { token, password: 'Kx7mP' })).body.status, 'done')
  assert.equal((await post('/auth/v1/phone/set-password', { token, password: 'Zz9yQ' })).status, 400, 'jeton déjà utilisé')
  assert.equal((await post('/auth/v1/phone/open', { phone: PHONE, second: DOB })).body.status, 'pending', 'autorisation à usage unique')
})

test('connexion par téléphone : rôle salarié seul, ses données seulement, pas de promotion possible', async () => {
  const ok = await login(EMAIL, 'Kx7mP')
  assert.equal(ok.status, 200)
  const t = ok.body.access_token
  assert.deepEqual((await rest('employees?select=employee_number', t)).body, [{ employee_number: EMPNO }])
  assert.ok((await rest('rpc/admin_phone_access_requests', t, { method: 'POST', body: {} })).status >= 400)
  const uid = ok.body.user.id
  for (const role of ['rh', 'paie', 'admin', 'manager']) {
    const r = await rest('user_roles', admin, { method: 'POST', body: { user_id: uid, role } })
    assert.ok(r.status >= 400, `rôle ${role} refusé même pour l'administrateur`)
  }
  const roles = (await db.query('select role from public.user_roles where user_id = $1', [uid])).rows.map((x) => x.role)
  assert.deepEqual(roles, ['salarie'])
})

test('verrouillage progressif par couple numéro + adresse après 5 échecs ; autres comptes intacts', async () => {
  for (let i = 0; i < 5; i++) assert.equal((await login(EMAIL, 'Mauvais1')).status, 400)
  assert.equal((await login(EMAIL, 'Kx7mP')).status, 429, 'verrouillé même avec le bon mot de passe')
  assert.equal((await login(qa.QA_RH_EMAIL, qa.QA_RH_PASSWORD)).status, 200, 'les autres comptes ne sont pas bloqués')
})

test('révocation : statut « révoqué » et compte désactivé', async () => {
  const empId = (await db.query(`select id from public.employees where last_name = 'Journey' and first_name = 'Test'`)).rows[0].id
  const r = await rest('rpc/admin_phone_access_revoke', admin, { method: 'POST', body: { p_employee_id: empId } })
  assert.equal(r.status, 204)
  assert.equal((await rest('rpc/employee_phone_access_status', rh, { method: 'POST', body: { p_employee_id: empId } })).body, 'révoqué')
  assert.equal((await db.query(`select status from public.phone_access_accounts where employee_id = $1`, [empId])).rows[0].status, 'revoked')
})
