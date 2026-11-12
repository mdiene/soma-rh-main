// Fonction Edge « phone-auth » (version en ligne) : mêmes routes que la passerelle locale /auth/v1/phone/* + « login ».
// Déployée le 12/11/2026 sur le projet mzhdwdpesbggxtjxxgab (verify_jwt désactivé : l'appelant n'a pas encore de session ; voir docs/DECISION_CONNEXION_TELEPHONE.md).
// Secrets : SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, SUPABASE_ANON_KEY (fournis par Supabase), PHONE_AUTH_PEPPER (supabase secrets set, 32+ caractères aléatoires).
//
// Mot de passe 5 à 8 : Supabase Auth impose un minimum (6 par défaut). Pour respecter la règle métier sans toucher à la plateforme,
// le mot de passe saisi n'est jamais transmis à Supabase tel quel : le mot de passe d'authentification est
// HMAC-SHA256(PHONE_AUTH_PEPPER, numéro + ":" + mot de passe saisi) (64 caractères), et la connexion passe par la route « login ».
import { createClient } from 'npm:@supabase/supabase-js@2.45.4'

const url = Deno.env.get('SUPABASE_URL')!
const admin = createClient(url, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!, { auth: { persistSession: false } })
const anon = createClient(url, Deno.env.get('SUPABASE_ANON_KEY')!, { auth: { persistSession: false } })
const pepper = Deno.env.get('PHONE_AUTH_PEPPER')!

const NEUTRAL_REQUEST = "Votre demande a été enregistrée. L'administrateur doit l'autoriser. Revenez saisir votre numéro plus tard."
const NEUTRAL_OPEN = "Impossible d'ouvrir l'activation pour le moment. Si votre demande a été autorisée, vérifiez votre numéro et votre date de naissance ; sinon revenez plus tard."
const cors = { 'access-control-allow-origin': '*', 'access-control-allow-headers': 'authorization, apikey, content-type', 'content-type': 'application/json' }
const reply = (status: number, body: unknown) => new Response(JSON.stringify(body), { status, headers: cors })

const hex = (b: ArrayBuffer) => [...new Uint8Array(b)].map((x) => x.toString(16).padStart(2, '0')).join('')
const sha256 = async (s: string) => hex(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(s)))
async function derive(phone: string, password: string) {
  const key = await crypto.subtle.importKey('raw', new TextEncoder().encode(pepper), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign'])
  return hex(await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(`${phone}:${password}`)))
}
const toEmail = (e164: string) => `${e164.replace(/\D/g, '')}@tel.soma-rh.invalid`
const strip = (s: unknown) => String(s ?? '').normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase().replace(/[^a-z0-9]/g, '')
const COMMON = new Set(['12345', '123456', '1234567', '12345678', '00000', '000000', '0000000', '00000000', '11111', '111111', '54321', '654321', '123123', 'azerty', 'qwerty', 'abcde', 'abcdef', 'password', 'motdepasse', 'passer', 'senegal', 'dakar'])
// Même règle que api/phone.mjs (passwordProblem) : à garder identique.
function problem(pw: unknown, p: Record<string, string>): string | null {
  if (typeof pw !== 'string' || !/^[A-Za-z0-9]{5,8}$/.test(pw)) return 'Mot de passe invalide : 5 à 8 lettres ou chiffres, sans espace ni caractère spécial.'
  const l = pw.toLowerCase(), digits = p.phone_e164.replace(/\D/g, '').slice(-9)
  const [y, m, d] = String(p.date_of_birth ?? '').slice(0, 10).split('-')
  const birth = y && m && d ? [d + m + y, y + m + d, m + d + y, d + m + y.slice(2), y.slice(2) + m + d] : []
  const personal = [p.first_name, p.last_name, p.employee_number, `${p.first_name}${p.last_name}`].map(strip).filter(Boolean)
  const trivial = COMMON.has(l) || /^(.)\1+$/.test(l) || '0123456789012'.includes(l) || '9876543210987'.includes(l)
    || (/^\d+$/.test(l) && digits.includes(l)) || birth.includes(l) || personal.includes(strip(l))
  return trivial ? 'Ce mot de passe est trop facile à deviner (suite, numéro, nom, matricule ou date de naissance). Choisissez-en un autre.' : null
}

// Verrouillage de connexion par couple numéro + adresse (en mémoire de l'instance : meilleur effort ; la base verrouille déjà l'ouverture).
const fails = new Map<string, { n: number; until: number; level: number }>()

const UNAVAILABLE = 'Service indisponible, réessayez plus tard.'
// Le journal ne bloque pas la réponse, mais son échec laisse une trace
async function logLogin(phone: string, event: string) {
  const { error } = await admin.rpc('phone_access_log_login', { p_phone: phone, p_event: event })
  if (error) console.error('phone_access_log_login', error.message)
}

Deno.serve(async (req) => {
  // Pré-vérification CORS : un statut 204 n'admet aucun corps (Deno lève une erreur sinon)
  if (req.method === 'OPTIONS') return new Response(null, { status: 204, headers: { ...cors, 'access-control-allow-methods': 'POST, OPTIONS' } })
  if (req.method !== 'POST') return reply(405, { message: 'Méthode non autorisée' })
  const route = new URL(req.url).pathname.split('/').pop()
  const input = await req.json().catch(() => null)
  if (input === null || typeof input !== 'object') return reply(400, { message: 'Corps de requête invalide' })
  // Adresse : l'entrée de DROITE de X-Forwarded-For est celle que la plateforme a vue (celles de gauche sont fournies par le client)
  const ip = req.headers.get('cf-connecting-ip') ?? req.headers.get('x-forwarded-for')?.split(',').map((x) => x.trim()).filter(Boolean).pop() ?? 'unknown'
  const ipHash = (await sha256(`${pepper}|${ip}`)).slice(0, 32)
  const phone = String(input.phone ?? '').slice(0, 40)

  if (route === 'request') {
    const { error } = await admin.rpc('phone_access_request', { p_phone: phone, p_ip_hash: ipHash })
    if (error) { console.error('phone_access_request', error.message); return reply(500, { message: UNAVAILABLE }) } // la réponse neutre ne couvre pas une panne
    return reply(200, { status: 'received', message: NEUTRAL_REQUEST })
  }

  if (route === 'open') {
    const token = hex(crypto.getRandomValues(new Uint8Array(24)).buffer)
    const second = /^\d{4}-\d{2}-\d{2}$/.test(String(input.second ?? '')) ? input.second : null
    const { data, error } = await admin.rpc('phone_access_open', { p_phone: phone, p_second: second, p_ip_hash: ipHash, p_token_hash: await sha256(token) })
    if (error) { console.error('phone_access_open', error.message); return reply(500, { message: UNAVAILABLE }) }
    return data ? reply(200, { status: 'ready', token }) : reply(200, { status: 'pending', message: NEUTRAL_OPEN })
  }

  if (route === 'set-password') {
    const tokenHash = await sha256(String(input.token ?? ''))
    const { data: peek, error: peekError } = await admin.rpc('phone_access_peek', { p_token_hash: tokenHash })
    if (peekError) { console.error('phone_access_peek', peekError.message); return reply(500, { message: UNAVAILABLE }) }
    const p = peek?.[0]
    if (!p) return reply(400, { message: "Le lien d'activation est invalide ou a expiré. Recommencez la saisie de votre numéro." })
    const bad = problem(input.password, p)
    if (bad) return reply(422, { message: bad })
    const secret = await derive(p.phone_e164, input.password)
    let userId: string = p.user_id
    if (userId) {
      const { error } = await admin.auth.admin.updateUserById(userId, { password: secret, ban_duration: 'none' })
      if (error) return reply(500, { message: 'Service indisponible, réessayez plus tard.' })
    } else {
      const { data, error } = await admin.auth.admin.createUser({
        email: toEmail(p.phone_e164), password: secret, email_confirm: true, app_metadata: { account_kind: 'employee_phone' },
      })
      if (error || !data.user) return reply(500, { message: 'Service indisponible, réessayez plus tard.' })
      userId = data.user.id
    }
    const { error } = await admin.rpc('phone_access_complete', { p_token_hash: tokenHash, p_user_id: userId })
    if (error) return reply(400, { message: "Le lien d'activation est invalide ou a expiré. Recommencez la saisie de votre numéro." })
    return reply(200, { status: 'done' })
  }

  if (route === 'login') {
    const { data: e164, error: normError } = await admin.rpc('phone_normalize', { p_phone: phone })
    if (normError) { console.error('phone_normalize', normError.message); return reply(500, { message: UNAVAILABLE }) }
    if (!e164) return reply(400, { message: 'Numéro ou mot de passe invalide' })
    const key = `${ip}|${e164}`, f = fails.get(key) ?? { n: 0, until: 0, level: 0 }
    if (Date.now() < f.until) return reply(429, { message: `Trop d'échecs, réessayez dans ${Math.ceil((f.until - Date.now()) / 1000)} secondes` })
    const { data, error } = await anon.auth.signInWithPassword({ email: toEmail(e164), password: await derive(e164, String(input.password ?? '')) })
    // une panne du service d'authentification n'est pas un mot de passe faux : pas de compteur d'échecs, pas de verrou
    if (error && ((error.status ?? 0) >= 500 || error.name === 'AuthRetryableFetchError')) { console.error('signInWithPassword', error.message); return reply(503, { message: UNAVAILABLE }) }
    if (error || !data.session) {
      f.n += 1
      const locked = f.n >= 5
      if (locked) { f.until = Date.now() + Math.min(60_000 * 2 ** f.level, 1_800_000); f.level += 1; f.n = 0 }
      fails.set(key, f)
      await logLogin(e164, locked ? 'verrouillage de connexion' : 'connexion échouée')
      return reply(400, { message: 'Numéro ou mot de passe invalide' })
    }
    fails.delete(key)
    await logLogin(e164, 'connexion réussie')
    return reply(200, { access_token: data.session.access_token, refresh_token: data.session.refresh_token })
  }

  return reply(404, { message: 'Route inconnue' })
})
