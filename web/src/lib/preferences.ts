import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { dataApi, unwrap } from './api'
import { useAuth } from './auth'
import type { Json } from './database.types'

/** Préférences de l'utilisateur connecté (table user_preferences, une ligne par compte). Nouvelle clé = nouveau champ ici, sans migration. */
export type Preferences = {
  favorites?: string[]   // routes épinglées en haut du menu
  // à venir : theme?: 'clair' | 'sombre' | 'auto', densite?, couleur d'accent…
}

export const MAX_FAVORITES = 4

export function usePreferences() {
  const { session } = useAuth()
  const uid = session?.user.id
  const qc = useQueryClient()
  const key = ['user_preferences', uid]

  const query = useQuery({
    queryKey: key,
    enabled: !!uid,
    staleTime: Infinity,
    queryFn: async () => (unwrap(await dataApi.from('user_preferences').select('preferences').eq('user_id', uid!).maybeSingle())?.preferences ?? {}) as Preferences,
  })

  // ponytail: l'objet entier est réécrit (dernier écrit gagne) ; fusion par clé côté base si deux onglets s'écrasent
  const save = useMutation({
    mutationFn: async (next: Preferences) =>
      unwrap(await dataApi.from('user_preferences').upsert({ user_id: uid!, preferences: next as NonNullable<Json>, updated_at: new Date().toISOString() }, { onConflict: 'user_id' }).select('user_id')),
    onMutate: (next) => { qc.setQueryData(key, next) },      // affichage immédiat
    onError: () => qc.invalidateQueries({ queryKey: key }),   // retour à l'état enregistré
  })

  const preferences = query.data ?? {}
  const favorites = preferences.favorites ?? []
  const update = (patch: Preferences) => save.mutate({ ...preferences, ...patch })
  const toggleFavorite = (to: string) => {
    if (favorites.includes(to)) update({ favorites: favorites.filter((f) => f !== to) })
    else if (favorites.length < MAX_FAVORITES) update({ favorites: [...favorites, to] })
  }
  return { preferences, favorites, update, toggleFavorite, canAddFavorite: favorites.length < MAX_FAVORITES }
}
