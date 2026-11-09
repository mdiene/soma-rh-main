import { useMutation, useQuery } from '@tanstack/react-query'
import { Check, X } from 'lucide-react'
import { useState } from 'react'
import { dataApi, unwrap } from '../../lib/api'
import { useAuth } from '../../lib/auth'
import { KIND_LABEL } from '../../lib/compliance'
import { date } from '../../lib/format'
import { Badge, Button, Empty, ErrorNote, Modal, Section, Spinner } from '../ui'
import { useRefreshCompliance } from './shared'

type Req = {
  id: string; kind: string; target: string; summary: string; payload: Record<string, unknown>; status: string
  requested_by: string | null; requested_by_email: string | null; requested_at: string
  decided_by: string | null; decided_by_email: string | null; decided_at: string | null; decision_note: string | null
}

const STATUS: Record<string, { value: string; label: string }> = {
  en_attente: { value: 'En attente', label: 'En attente' },
  'approuvée': { value: 'Approuvée', label: 'Approuvée' },
  'refusée': { value: 'Rejetée', label: 'Refusée' },
  'annulée': { value: 'Annulée', label: 'Retirée' },
}

export function ApprovalsTab({ onNotice }: { onNotice: (m: string) => void }) {
  const { roles, session } = useAuth()
  const isAdmin = roles.includes('admin')
  const me = session?.user.id
  const refresh = useRefreshCompliance()
  const list = useQuery({ queryKey: ['approval_requests', 'all'], queryFn: async () => unwrap(await dataApi.rpc('approval_requests_overview')) as unknown as Req[] })
  const [refusing, setRefusing] = useState<Req | null>(null)
  const [note, setNote] = useState('')

  const decide = useMutation({
    mutationFn: async (v: { id: string; approve: boolean; note?: string }) =>
      unwrap(await dataApi.rpc('decide_request', { p_id: v.id, p_approve: v.approve, p_note: v.note })),
    onSuccess: (_d, v) => { setRefusing(null); setNote(''); refresh(); onNotice(v.approve ? 'Demande approuvée et appliquée.' : 'Demande refusée.') },
  })
  const cancel = useMutation({
    mutationFn: async (id: string) => unwrap(await dataApi.rpc('cancel_request', { p_id: id })),
    onSuccess: () => { refresh(); onNotice('Demande retirée.') },
  })

  if (list.isLoading) return <Spinner />
  const rows = list.data ?? []
  const pending = rows.filter((r) => r.status === 'en_attente')
  const history = rows.filter((r) => r.status !== 'en_attente')
  return (
    <div className="space-y-6">
      <ErrorNote error={list.error} />
      <Section title={`En attente de décision (${pending.length})`}>
        {pending.length === 0 ? (
          <Empty title="Aucune demande en attente">
            {isAdmin ? 'Les demandes du RH et de la paie apparaîtront ici pour validation.' : 'Vos demandes de dérogation, de modification de constante ou de barème apparaîtront ici jusqu’à la décision de l’administrateur.'}
          </Empty>
        ) : (
          <ul className="space-y-3">
            {pending.map((r) => (
              <li key={r.id} className="rounded border border-line px-3 py-2.5">
                <div className="flex flex-wrap items-start justify-between gap-3">
                  <div className="min-w-0 max-w-prose">
                    <p className="flex flex-wrap items-center gap-2 text-sm font-medium text-ink"><Badge value="En attente" label={KIND_LABEL[r.kind] ?? r.kind} />{r.summary}</p>
                    {r.kind === 'derogation' && <p className="mt-1 text-sm text-ink-soft">Motif : {String(r.payload.reason ?? '')}</p>}
                    <p className="mt-1 text-xs text-ink-muted">Demandé par {r.requested_by_email ?? 'un utilisateur supprimé'} le {date(r.requested_at)}</p>
                  </div>
                  <span className="inline-flex flex-wrap gap-1.5">
                    {isAdmin && <>
                      <Button size="sm" variant="primary" icon={<Check className="h-3.5 w-3.5" aria-hidden />} loading={decide.isPending && decide.variables?.id === r.id}
                        onClick={() => decide.mutate({ id: r.id, approve: true })} aria-label={`Approuver : ${r.summary}`}>Approuver</Button>
                      <Button size="sm" icon={<X className="h-3.5 w-3.5" aria-hidden />} onClick={() => { setRefusing(r); setNote('') }} aria-label={`Refuser : ${r.summary}`}>Refuser</Button>
                    </>}
                    {r.requested_by === me && <Button size="sm" variant="ghost" loading={cancel.isPending && cancel.variables === r.id} onClick={() => cancel.mutate(r.id)} aria-label={`Retirer : ${r.summary}`}>Retirer</Button>}
                  </span>
                </div>
              </li>
            ))}
          </ul>
        )}
        <div className="mt-3"><ErrorNote error={decide.error || cancel.error} /></div>
      </Section>

      <Section title="Historique">
        {history.length === 0 ? <p className="text-sm text-ink-muted">Aucune demande traitée.</p> : (
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <caption className="sr-only">Demandes traitées</caption>
              <thead>
                <tr className="table-head">
                  <th scope="col" className="px-2 py-1.5 text-left">Décision</th>
                  <th scope="col" className="px-2 py-1.5 text-left">Demande</th>
                  <th scope="col" className="px-2 py-1.5 text-left">Demandeur</th>
                  <th scope="col" className="px-2 py-1.5 text-left">Décideur</th>
                  <th scope="col" className="px-2 py-1.5 text-left">Date</th>
                  <th scope="col" className="px-2 py-1.5 text-left">Note</th>
                </tr>
              </thead>
              <tbody>
                {history.map((r) => (
                  <tr key={r.id} className="border-b border-line/70 align-top">
                    <td className="px-2 py-1.5"><Badge value={STATUS[r.status]?.value ?? r.status} label={STATUS[r.status]?.label ?? r.status} /></td>
                    <td className="px-2 py-1.5">{r.summary}</td>
                    <td className="px-2 py-1.5 text-xs">{r.requested_by_email ?? '—'}</td>
                    <td className="px-2 py-1.5 text-xs">{r.decided_by_email ?? '—'}</td>
                    <td className="px-2 py-1.5 tabular-nums">{date(r.decided_at)}</td>
                    <td className="px-2 py-1.5 text-xs text-ink-soft">{r.decision_note ?? ''}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </Section>

      {refusing && (
        <Modal open title="Refuser la demande" onClose={() => setRefusing(null)}
          footer={<>
            <Button onClick={() => setRefusing(null)}>Annuler</Button>
            <Button variant="danger" loading={decide.isPending} disabled={!note.trim()} onClick={() => decide.mutate({ id: refusing.id, approve: false, note })}>Refuser</Button>
          </>}>
          <div className="space-y-3">
            <p className="text-sm text-ink-soft">{refusing.summary}</p>
            <label className="block">
              <span className="label">Motif du refus (obligatoire)</span>
              <textarea className="field min-h-24" value={note} onChange={(e) => setNote(e.target.value)} autoFocus />
            </label>
            <ErrorNote error={decide.error} />
          </div>
        </Modal>
      )}
    </div>
  )
}
