// Connexion par téléphone : fonctions pures partagées par la passerelle (testées dans tests/unit/phone.auth.test.mjs).
// La normalisation du numéro est faite par la base (public.phone_normalize) : une seule source de vérité.
import { createHash } from 'node:crypto'

export const PHONE_EMAIL_DOMAIN = 'tel.soma-rh.invalid'
export const NEUTRAL_REQUEST_MESSAGE =
  "Votre demande a été enregistrée. L'administrateur doit l'autoriser. Revenez saisir votre numéro plus tard."
export const NEUTRAL_OPEN_MESSAGE =
  "Impossible d'ouvrir l'activation pour le moment. Si votre demande a été autorisée, vérifiez votre numéro et votre date de naissance ; sinon revenez plus tard."
export const PASSWORD_RULE = '5 à 8 lettres ou chiffres, sans espace ni caractère spécial.'

/** Adresse technique d'un compte téléphone : +221771234567 -> 221771234567@tel.soma-rh.invalid */
export const phoneToEmail = (e164) => `${String(e164).replace(/\D/g, '')}@${PHONE_EMAIL_DOMAIN}`
export const isPhoneEmail = (email) => typeof email === 'string' && email.toLowerCase().endsWith(`@${PHONE_EMAIL_DOMAIN}`)
export const emailToPhone = (email) => `+${String(email).split('@')[0]}`

/** Haché (sel = secret de la passerelle) : on ne stocke jamais une adresse IP en clair dans les compteurs. */
export const hashIp = (ip, salt) => createHash('sha256').update(`${salt}|${ip}`).digest('hex').slice(0, 32)
export const hashToken = (token) => createHash('sha256').update(String(token)).digest('hex')

const strip = (s) => String(s ?? '').normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase().replace(/[^a-z0-9]/g, '')
const COMMON = new Set(['12345', '123456', '1234567', '12345678', '00000', '000000', '0000000', '00000000', '11111', '111111',
  '54321', '654321', '123123', 'azerty', 'qwerty', 'abcde', 'abcdef', 'password', 'motdepasse', 'passer', 'senegal', 'dakar'])

/**
 * Règle du mot de passe : ^[A-Za-z0-9]{5,8}$ + refus des mots de passe triviaux.
 * `ctx` : { phone: '+221…', firstName, lastName, employeeNumber, birthDate: 'AAAA-MM-JJ' } (fiche du salarié).
 * Renvoie null si le mot de passe est accepté, sinon le message à afficher.
 */
export function passwordProblem(password, ctx = {}) {
  if (typeof password !== 'string' || !/^[A-Za-z0-9]{5,8}$/.test(password)) {
    return `Mot de passe invalide : ${PASSWORD_RULE}`
  }
  const p = password.toLowerCase()
  const digits = String(ctx.phone ?? '').replace(/\D/g, '').slice(-9)
  const [y, m, d] = String(ctx.birthDate ?? '').split('-')
  const birth = y && m && d ? [d + m + y, y + m + d, m + d + y, d + m + y.slice(2), y.slice(2) + m + d] : []
  const personal = [ctx.firstName, ctx.lastName, ctx.employeeNumber, `${ctx.firstName ?? ''}${ctx.lastName ?? ''}`].map(strip).filter(Boolean)
  const trivial =
    COMMON.has(p) ||
    /^(.)\1+$/.test(p) ||                                              // 11111, aaaaaa
    '0123456789012'.includes(p) || '9876543210987'.includes(p) ||      // suites 12345, 98765
    (/^\d+$/.test(p) && digits.includes(p)) ||                          // morceau du numéro de téléphone
    birth.includes(p) ||
    personal.includes(strip(p))
  return trivial ? 'Ce mot de passe est trop facile à deviner (suite, numéro, nom, matricule ou date de naissance). Choisissez-en un autre.' : null
}

/** Date saisie « AAAA-MM-JJ » (champ date du navigateur) ; null si absente ou mal formée. */
export const parseBirthDate = (value) => (/^\d{4}-\d{2}-\d{2}$/.test(String(value ?? '')) ? String(value) : null)

/**
 * Verrouillage progressif des connexions par couple numéro + adresse (RPR-03 : jamais de blocage collectif par adresse).
 * 5 échecs -> 1 min, puis 2, 4, 8, 16, 30 min (plafond) à chaque nouveau palier ; une connexion réussie remet à zéro.
 */
export function createLoginLimiter({ maxFailures = 5, baseMs = 60_000, capMs = 30 * 60_000, now = Date.now } = {}) {
  const store = new Map()
  return {
    /** Secondes restantes avant la fin du verrou, 0 si libre. */
    retryAfter(key) {
      const e = store.get(key)
      return e && now() < e.lockedUntil ? Math.ceil((e.lockedUntil - now()) / 1000) : 0
    },
    /** Enregistre un échec ; renvoie true si cet échec déclenche un verrou. */
    fail(key) {
      const e = store.get(key) ?? { failures: 0, level: 0, lockedUntil: 0 }
      e.failures += 1
      let locked = false
      if (e.failures >= maxFailures) {
        e.lockedUntil = now() + Math.min(baseMs * 2 ** e.level, capMs)
        e.level += 1
        e.failures = 0
        locked = true
      }
      store.set(key, e)
      return locked
    },
    success(key) { store.delete(key) },
  }
}

/**
 * Adresse du client. Derrière un proxy de confiance (TRUST_PROXY=1), l'entrée de DROITE de X-Forwarded-For est celle
 * que le proxy a vue : les entrées de gauche sont fournies par le client et falsifiables. Sans proxy déclaré, l'en-tête est ignoré.
 */
export function clientAddress(socketIp, forwardedFor, trustProxy) {
  if (trustProxy && forwardedFor) {
    const last = String(forwardedFor).split(',').map((s) => s.trim()).filter(Boolean).pop()
    if (last) return last
  }
  return socketIp || 'unknown'
}

/**
 * Verrou de connexion persistant : mêmes règles que createLoginLimiter mais l'état vit en base (public.login_attempts) :
 * il survit au redémarrage de la passerelle et se partage entre instances. La clé est hachée (aucun compte ni adresse en clair).
 * Si la base répond mal, on se replie sur le verrou en mémoire (meilleur effort) et l'incident est tracé.
 */
export function createPersistentLimiter({ query, memory, prefix, maxFailures = 5, salt, log = console.error }) {
  const k = (key) => createHash('sha256').update(`${prefix}|${salt()}|${key}`).digest('hex')
  const guarded = async (sql, params, fromMemory) => {
    try { return (await query(sql, params)).rows[0].r } catch (error) {
      log('Verrou de connexion : base indisponible, repli sur la mémoire :', error.message)
      return fromMemory()
    }
  }
  return {
    retryAfter: (key) => guarded('select public.login_lock_retry_after($1) as r', [k(key)], () => memory.retryAfter(key)),
    fail: async (key) => {
      const local = memory.fail(key)
      return guarded('select public.login_lock_fail($1, $2) as r', [k(key), maxFailures], () => local)
    },
    success: async (key) => {
      memory.success(key)
      await guarded('select public.login_lock_success($1) as r', [k(key)], () => null)
    },
  }
}
