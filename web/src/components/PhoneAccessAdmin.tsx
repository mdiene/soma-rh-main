import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { dataApi, unwrap } from '../lib/api'
import { date as dateTime } from '../lib/format'
import { Button, ErrorNote, Section, Spinner } from './ui'

type Request = {
  id: string; employee_id: string | null; employee_number: string | null; employee_name: string; department: string | null
  phone_masked: string | null; purpose: 'signup' | 'reset' | 'shared'; status: string; requested_at: string
  decided_at: string | null; expires_at: string | null; repeat_count: number; has_birth_date: boolean
}
type Account = { employee_id: string; employee_number: string; employee_name: string; phone_masked: string; status: string; created_at: string }

const STATUS: Record<string, string> = {
  pending: 'En attente', authorized: 'Autorisée', refused: 'Refusée', used: 'Utilisée', revoked: 'Révoquée', expired: 'Expirée',
}
const PURPOSE = { signup: 'Création', reset: 'Réinitialisation', shared: 'Numéro partagé' } as const
const ACCOUNT = { active: 'Actif', disabled: 'Désactivé (numéro modifié)', revoked: 'Révoqué' } as Record<string, string>

/** Écran de l'administrateur : autoriser, refuser ou révoquer l'accès des salariés par téléphone. */
export function PhoneAccessAdmin() {
  const qc = useQueryClient()
  const refresh = () => { qc.invalidateQueries({ queryKey: ['phone_requests'] }); qc.invalidateQueries({ queryKey: ['phone_accounts'] }); qc.invalidateQueries({ queryKey: ['legal_alerts'] }) }
  const requests = useQuery({ queryKey: ['phone_requests'], queryFn: async () => unwrap(await dataApi.rpc('admin_phone_access_requests')) as Request[] })
  const accounts = useQuery({ queryKey: ['phone_accounts'], queryFn: async () => unwrap(await dataApi.rpc('admin_phone_access_accounts')) as Account[] })
  const settings = useQuery({ queryKey: ['phone_settings'], queryFn: async () => unwrap(await dataApi.from('phone_access_settings').select('second_factor, authorization_hours').single()) })
  const decide = useMutation({
    mutationFn: async ({ id, authorize }: { id: string; authorize: boolean }) =>
      unwrap(await dataApi.rpc('admin_phone_access_decide', { p_request_id: id, p_authorize: authorize })),
    onSuccess: refresh,
  })
  const revoke = useMutation({
    mutationFn: async (employeeId: string) => unwrap(await dataApi.rpc('admin_phone_access_revoke', { p_employee_id: employeeId })),
    onSuccess: refresh,
  })
  const secondFactor = useMutation({
    mutationFn: async (on: boolean) => unwrap(await dataApi.from('phone_access_settings').update({ second_factor: on, updated_at: new Date().toISOString() }).eq('id', true).select()),
    onSuccess: () => qc.invalidateQueries({ queryKey: ['phone_settings'] }),
  })

  const pending = (requests.data ?? []).filter((r) => r.status === 'pending')
  const rows = requests.data ?? []

  return (
    <Section title={`Accès des salariés par téléphone${pending.length ? ` — ${pending.length} demande${pending.length > 1 ? 's' : ''} en attente` : ''}`}>
      <div id="acces-telephone" />
      <p className="mb-3 text-sm text-ink-soft">
        Contactez le salarié (appel ou message) avant d'autoriser. Une autorisation est valable {settings.data?.authorization_hours ?? 48} h et ne sert qu'une fois ;
        le salarié devra ressaisir son numéro{settings.data?.second_factor ? ' et sa date de naissance' : ''}, puis choisira son mot de passe.
      </p>
      <ErrorNote error={requests.error || accounts.error || settings.error || decide.error || revoke.error || secondFactor.error} />

      {requests.isLoading ? <Spinner /> : rows.length === 0 ? <p className="text-sm text-ink-soft">Aucune demande d'accès par téléphone.</p> : (
        <div className="overflow-x-auto">
          <table className="w-full text-sm">
            <caption className="sr-only">Demandes d'accès par téléphone</caption>
            <thead><tr className="table-head">
              <th className="px-2 py-1.5">Salarié</th><th className="px-2 py-1.5">Service</th><th className="px-2 py-1.5">Numéro</th>
              <th className="px-2 py-1.5">Objet</th><th className="px-2 py-1.5">Demandée le</th><th className="px-2 py-1.5">Statut</th><th className="px-2 py-1.5">Décision</th>
            </tr></thead>
            <tbody>
              {rows.map((r) => (
                <tr key={r.id} className="border-b border-line/70 align-top">
                  <td className="px-2 py-1.5"><span className="font-medium">{r.employee_name}</span>{r.employee_number && <span className="block text-xs text-ink-muted">Matricule {r.employee_number}</span>}</td>
                  <td className="px-2 py-1.5">{r.department ?? '—'}</td>
                  <td className="px-2 py-1.5 tabular-nums">{r.phone_masked}</td>
                  <td className="px-2 py-1.5">{PURPOSE[r.purpose]}{r.repeat_count > 0 && <span className="block text-xs text-signal">Redemandée {r.repeat_count} fois</span>}</td>
                  <td className="px-2 py-1.5">{dateTime(r.requested_at)}</td>
                  <td className="px-2 py-1.5">{STATUS[r.status] ?? r.status}{r.status === 'authorized' && r.expires_at && <span className="block text-xs text-ink-muted">jusqu'au {dateTime(r.expires_at)}</span>}</td>
                  <td className="px-2 py-1.5">
                    {r.status === 'pending' && r.purpose !== 'shared' && (
                      <div className="flex flex-wrap items-center gap-3">
                        <label className="flex items-center gap-2">
                          <input type="checkbox" className="h-4 w-4 accent-river" checked={false} disabled={decide.isPending || !settings.data || (settings.data.second_factor && !r.has_birth_date)}
                            onChange={() => decide.mutate({ id: r.id, authorize: true })} />
                          Autoriser l'accès par téléphone
                        </label>
                        <Button size="sm" onClick={() => decide.mutate({ id: r.id, authorize: false })} disabled={decide.isPending}>Refuser</Button>
                        {settings.data?.second_factor && !r.has_birth_date && <span className="text-xs text-signal">Date de naissance absente de la fiche</span>}
                      </div>
                    )}
                    {r.status === 'pending' && r.purpose === 'shared' && <Button size="sm" onClick={() => decide.mutate({ id: r.id, authorize: false })}>Classer (corriger les fiches)</Button>}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      <h3 className="mb-2 mt-6 text-sm font-semibold">Comptes actifs par téléphone</h3>
      {accounts.isLoading ? <Spinner /> : (accounts.data ?? []).length === 0 ? <p className="text-sm text-ink-soft">Aucun compte.</p> : (
        <ul className="divide-y divide-line text-sm">
          {accounts.data!.map((a) => (
            <li key={a.employee_id} className="flex flex-wrap items-center gap-3 py-2">
              <span className="font-medium">{a.employee_name}</span><span className="text-xs text-ink-muted">Matricule {a.employee_number}</span>
              <span className="tabular-nums">{a.phone_masked}</span><span>{ACCOUNT[a.status] ?? a.status}</span>
              {a.status === 'active' && <Button size="sm" onClick={() => revoke.mutate(a.employee_id)} loading={revoke.isPending}>Révoquer l'accès</Button>}
            </li>
          ))}
        </ul>
      )}

      <label className="mt-6 flex items-center gap-2 text-sm">
        <input type="checkbox" className="h-4 w-4 accent-river" checked={settings.data?.second_factor ?? true} disabled={secondFactor.isPending || !settings.data}
          onChange={(e) => secondFactor.mutate(e.target.checked)} />
        Exiger la date de naissance à l'activation (recommandé tant qu'aucun SMS n'est envoyé)
      </label>
    </Section>
  )
}
