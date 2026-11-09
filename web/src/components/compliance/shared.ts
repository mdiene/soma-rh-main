import { useQueryClient } from '@tanstack/react-query'

export type LegalSource = { code: string; label: string; article: string | null; status: string }

export const STATUS_LABEL: Record<string, string> = { confirme: 'Source confirmée', a_confirmer: 'Source à confirmer' }

/** Message affiché après l'envoi : appliqué tout de suite pour l'administrateur, sinon transmis pour validation. */
export const doneMessage = (isAdmin: boolean, what: string) =>
  isAdmin ? `${what} appliquée.` : `${what} envoyée à l’administrateur pour validation.`

/** Rafraîchit les listes qui dépendent des constantes, des barèmes, des demandes et du scan. */
export function useRefreshCompliance() {
  const qc = useQueryClient()
  return () => {
    for (const key of ['param_overview', 'param_floor', 'approval_requests', 'approval_pending', 'scale_overview', 'scale_versions', 'scale_lines', 'compliance']) {
      void qc.invalidateQueries({ queryKey: [key] })
    }
  }
}
