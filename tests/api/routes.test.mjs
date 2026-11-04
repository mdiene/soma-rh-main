// Routes Node de la passerelle (/auth/v1, /api/v1/documents, /api/v1/employees) et jetons invalides (expiré, falsifié...).
// Prérequis : stack Docker, scénario chargé, comptes de test. Lancer : node --test --test-concurrency=1 tests/api/routes.test.mjs
// Le secret JWT est lu dans le conteneur au lancement, jamais écrit dans un fichier.
import { test, before } from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { execFileSync } from 'node:child_process'
import { createHmac, randomUUID } from 'node:crypto'

const read = (p) => Object.fromEntries(readFileSync(new URL(p, import.meta.url), 'utf8').split(/\r?\n/)
  .filter((l) => /^[A-Z_0-9]+=/.test(l)).map((l) => [l.slice(0, l.indexOf('=')), l.slice(l.indexOf('=') + 1).trim()]))
const env = read('../.env.qa')
const API = env.QA_API_URL
const KEY = read('../../web/.env.local').VITE_API_PUBLIC_KEY
const SECRET = execFileSync('docker', ['exec', 'soma-rh-local-api-1', 'printenv', 'JWT_SECRET']).toString().trim()

const b64 = (o) => Buffer.from(JSON.stringify(o)).toString('base64url')
const forge = (claims, secret = SECRET) => {
  const head = `${b64({ alg: 'HS256', typ: 'JWT' })}.${b64(claims)}`
  return `${head}.${createHmac('sha256', secret).update(head).digest('base64url')}`
}
const now = Math.floor(Date.now() / 1000)
const claimsDe = (tok) => JSON.parse(Buffer.from(tok.split('.')[1], 'base64url').toString())

const http = async (path, { tok, method = 'GET', body, headers = {} } = {}) => {
  const r = await fetch(`${API}${path}`, { method, headers: { apikey: KEY, 'content-type': 'application/json', ...(tok ? { authorization: `Bearer ${tok}` } : {}), ...headers },
    body: body === undefined ? undefined : typeof body === 'string' || Buffer.isBuffer(body) ? body : JSON.stringify(body) })
  let b = null; try { b = await r.json() } catch { /* corps vide ou non JSON */ }
  return { s: r.status, b }
}
const login = async (r) => (await http('/auth/v1/token', { method: 'POST', body: { email: env[`QA_${r}_EMAIL`], password: env[`QA_${r}_PASSWORD`] } })).b.access_token

const T = {}
let claims
before(async () => {
  for (const r of ['ADMIN', 'RH', 'SALARIE']) T[r] = await login(r)
  claims = claimsDe(T.SALARIE)
})
const valide = () => T.SALARIE

// ---- /auth/v1 ----
test('connexion : mauvais mot de passe et compte inconnu refusés (400), même message', async () => {
  const a = await http('/auth/v1/token', { method: 'POST', body: { email: env.QA_SALARIE_EMAIL, password: 'faux-faux-faux' } })
  const b = await http('/auth/v1/token', { method: 'POST', body: { email: 'inconnu@example.test', password: 'faux-faux-faux' } })
  assert.equal(a.s, 400); assert.equal(b.s, 400)
  assert.deepEqual(a.b, b.b, 'le message ne doit pas révéler si le compte existe')
})
test('connexion valide : jeton, refresh_token, expires_in, sans hash de mot de passe', async () => {
  const r = await http('/auth/v1/token', { method: 'POST', body: { email: env.QA_SALARIE_EMAIL, password: env.QA_SALARIE_PASSWORD } })
  assert.equal(r.s, 200); assert.ok(r.b.access_token && r.b.refresh_token); assert.equal(r.b.expires_in, 28800)
  assert.equal(r.b.user.encrypted_password, undefined)
})
test('inscription fermée (403)', async () => {
  const r = await http('/auth/v1/signup', { method: 'POST', body: { email: `x${randomUUID()}@example.test`, password: 'Mot2passe-long' } })
  assert.equal(r.s, 403)
})
test('/auth/v1/user : sans jeton 401 ; avec jeton valide 200 et sans hash', async () => {
  assert.equal((await http('/auth/v1/user')).s, 401)
  const r = await http('/auth/v1/user', { tok: valide() })
  assert.equal(r.s, 200); assert.equal(r.b.encrypted_password, undefined)
})

// ---- jetons invalides : toutes les surfaces doivent répondre 401, jamais 200 ni 500 ----
const SURFACES = [
  ['REST (PostgREST)', '/rest/v1/employees?select=id&limit=1'],
  ['/auth/v1/user', '/auth/v1/user'],
  ['documents (Node)', `/api/v1/documents/${randomUUID()}`],
  ['dossier groupé (Node)', `/api/v1/employees/${randomUUID()}/documents/bundle`],
]
const mauvais = {
  'expiré': () => forge({ ...claims, iat: now - 90000, exp: now - 3600 }),
  'signé avec un autre secret': () => forge({ ...claims, exp: now + 3600 }, 'autre-secret-autre-secret-autre-secret'),
  'sans signature (alg none)': () => `${b64({ alg: 'none', typ: 'JWT' })}.${b64({ ...claims, exp: now + 3600 })}.`,
  'de mauvaise audience': () => forge({ ...claims, aud: 'autre', exp: now + 3600 }),
  'illisible': () => 'abc.def.ghi',
}
for (const [nom, fabrique] of Object.entries(mauvais)) {
  test(`jeton ${nom} : refusé (401) sur toutes les surfaces`, async () => {
    const tok = fabrique()
    const echecs = []
    for (const [surface, chemin] of SURFACES) {
      const r = await http(chemin, { tok })
      if (r.s !== 401) echecs.push(`${surface} → ${r.s}`)
    }
    assert.deepEqual(echecs, [], `réponse autre que 401 : ${echecs.join(' ; ')}`)
  })
}
test('contrôle : un jeton forgé correctement et non expiré est accepté (les refus ci-dessus tiennent donc au défaut du jeton)', async () => {
  const ok = forge({ ...claims, exp: now + 3600 })
  assert.equal((await http('/rest/v1/employees?select=id&limit=1', { tok: ok })).s, 200)
})

// ---- documents ----
test('documents : sans jeton 401 ; identifiant invalide 400 ; inconnu 404', async () => {
  assert.equal((await http(`/api/v1/documents/${randomUUID()}`)).s, 401)
  assert.equal((await http('/api/v1/documents/pas-un-uuid', { tok: valide() })).s, 400)
  assert.equal((await http(`/api/v1/documents/${randomUUID()}`, { tok: valide() })).s, 404)
})
const autreSalarie = async () => (await http(`/rest/v1/employees?select=id&user_id=neq.${claims.sub}&limit=1`, { tok: T.ADMIN })).b[0].id
test('documents : un salarié ne supprime rien (404) et n\'obtient pas le dossier d\'un autre (403)', async () => {
  assert.equal((await http(`/api/v1/documents/${randomUUID()}`, { tok: valide(), method: 'DELETE' })).s, 404)
  assert.equal((await http(`/api/v1/employees/${await autreSalarie()}/documents/bundle`, { tok: valide() })).s, 403)
})
test('téléversement : autre salarié 403, format interdit 415, références invalides 400', async () => {
  const autre = await autreSalarie()
  const up = (emp, mime, req = 'cni') => http('/api/v1/documents/upload', { tok: valide(), method: 'POST', body: Buffer.from('%PDF-1.4'),
    headers: { 'x-employee-id': emp, 'x-requirement-code': req, 'x-file-mime': mime, 'x-file-name': Buffer.from('a.pdf').toString('base64') } })
  assert.equal((await up(autre, 'application/pdf')).s, 403)
  assert.equal((await up(randomUUID(), 'application/x-msdownload')).s, 415)
  assert.equal((await up('pas-un-uuid', 'application/pdf')).s, 400)
  assert.equal((await up(autre, 'application/pdf', '../etc')).s, 400)
})
