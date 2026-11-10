// Contrat unique de la connexion par téléphone, identique en local (passerelle /auth/v1/phone/*) et en ligne
// (fonction Edge « phone-auth » : VITE_PHONE_AUTH_URL). Aucune logique de sécurité ici : tout est contrôlé côté serveur.
import { dataApi } from './api'

const apiUrl = import.meta.env.VITE_API_URL as string
const apiKey = import.meta.env.VITE_API_PUBLIC_KEY as string
const base = ((import.meta.env.VITE_PHONE_AUTH_URL as string | undefined) ?? `${apiUrl}/auth/v1/phone`).replace(/\/$/, '')

export const PASSWORD_RULE = '5 à 8 lettres ou chiffres, sans espace ni caractère spécial.'
export const PASSWORD_PATTERN = /^[A-Za-z0-9]{5,8}$/

/** Adresse technique d'un compte téléphone (le serveur la fabrique de la même façon) : 221771234567@tel.soma-rh.invalid */
export function phoneToEmail(phone: string): string | null {
  const v = phone.replace(/[\s.\-()]/g, '')
  const m = /^(?:\+|00)?(?:221)?((?:70|75|76|77|78)\d{7})$/.exec(v)
  return m ? `221${m[1]}@tel.soma-rh.invalid` : null
}

async function call<T>(route: string, body: unknown): Promise<T & { message?: string }> {
  const r = await fetch(`${base}/${route}`, {
    method: 'POST',
    headers: { 'content-type': 'application/json', apikey: apiKey, authorization: `Bearer ${apiKey}` },
    body: JSON.stringify(body),
  })
  const data = (await r.json().catch(() => ({}))) as T & { message?: string }
  if (r.status === 429) throw new Error(data.message ?? 'Trop de tentatives, réessayez plus tard.')
  if (!r.ok && r.status !== 422 && r.status !== 400) throw new Error('Service indisponible, réessayez plus tard.')
  if (!r.ok) throw new Error(data.message ?? 'Demande refusée.')
  return data
}

/** 1. Demande d'accès : réponse toujours identique, que le numéro existe ou non. */
export const demanderAcces = (telephone: string) => call<{ status: 'received' }>('request', { phone: telephone })

/** 2. Ouverture de l'activation : renvoie un jeton (15 min, usage unique) si l'administrateur a autorisé, sinon « pending ». */
export const ouvrirActivation = (telephone: string, secondeInfo?: string) =>
  call<{ status: 'ready'; token: string } | { status: 'pending' }>('open', { phone: telephone, second: secondeInfo || undefined })

/** 3. Création ou changement du mot de passe avec le jeton. */
export const definirMotDePasse = (jeton: string, motDePasse: string) =>
  call<{ status: 'done' }>('set-password', { token: jeton, password: motDePasse })

/** 4. Connexion par numéro + mot de passe. */
export async function seConnecterParTelephone(telephone: string, motDePasse: string) {
  const email = phoneToEmail(telephone)
  if (!email) throw new Error('Numéro invalide : saisissez un mobile sénégalais (77 123 45 67).')
  if (import.meta.env.VITE_PHONE_AUTH_URL) {
    // En ligne : le mot de passe 5-8 est dérivé côté serveur (voir supabase/functions/phone-auth), la connexion passe par la fonction
    const s = await call<{ access_token: string; refresh_token: string }>('login', { phone: telephone, password: motDePasse })
    const { error } = await dataApi.auth.setSession({ access_token: s.access_token, refresh_token: s.refresh_token })
    if (error) throw new Error(error.message)
    return
  }
  const { error } = await dataApi.auth.signInWithPassword({ email, password: motDePasse })
  if (error) throw new Error(/invalid|credentials/i.test(error.message) ? 'Numéro ou mot de passe invalide' : error.message)
}
