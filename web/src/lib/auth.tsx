import { createContext, useCallback, useContext, useEffect, useMemo, useRef, useState, type ReactNode } from 'react'
import type { ApiSession as Session } from './api'
import { dataApi } from './api'

export type Role = 'admin' | 'rh' | 'paie' | 'manager' | 'salarie'

type AuthState = {
  session: Session | null
  roles: Role[]
  loading: boolean
  can: (...roles: Role[]) => boolean
  refreshRoles: () => Promise<void>
  signOut: () => Promise<void>
}

const AuthContext = createContext<AuthState | null>(null)

export function AuthProvider({ children }: { children: ReactNode }) {
  const [session, setSession] = useState<Session | null>(null)
  const [roles, setRoles] = useState<Role[]>([])
  const [loading, setLoading] = useState(true)

  // RPR-15 : les rôles étaient relus à chaque événement d'authentification (3 à 4 requêtes par navigation).
  // Une seule lecture par utilisateur, partagée entre les appelants simultanés (getSession et onAuthStateChange) : chacun attend la même promesse.
  const inflight = useRef<{ id: string; promise: Promise<void> } | null>(null)
  const loadRoles = useCallback((s: Session | null, force = false): Promise<void> => {
    if (!s) { inflight.current = null; setRoles([]); return Promise.resolve() }
    if (!force && inflight.current?.id === s.user.id) return inflight.current.promise
    const promise = (async () => {
      const { data, error } = await dataApi.from('user_roles').select('role').eq('user_id', s.user.id)
      if (error) inflight.current = null // échec (jeton expiré, réseau) : la prochaine notification retentera
      setRoles((data ?? []).map((r) => r.role as Role))
    })()
    inflight.current = { id: s.user.id, promise }
    return promise
  }, [])

  useEffect(() => {
    dataApi.auth.getSession().then(async ({ data }) => {
      setSession(data.session)
      await loadRoles(data.session)
      setLoading(false)
    })
    const { data: sub } = dataApi.auth.onAuthStateChange((event, s) => {
      setSession(s)
      void loadRoles(s, event === 'TOKEN_REFRESHED') // un renouvellement de jeton relit les rôles (retrait de droit pris en compte)
    })
    return () => sub.subscription.unsubscribe()
  }, [loadRoles])

  const value = useMemo<AuthState>(() => ({
    session,
    roles,
    loading,
    can: (...wanted) => roles.includes('admin') || wanted.some((r) => roles.includes(r)),
    refreshRoles: () => loadRoles(session, true),
    signOut: async () => { await dataApi.auth.signOut() },
  }), [session, roles, loading, loadRoles])

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>
}

export function useAuth(): AuthState {
  const ctx = useContext(AuthContext)
  if (!ctx) throw new Error('useAuth doit être utilisé dans <AuthProvider>')
  return ctx
}
