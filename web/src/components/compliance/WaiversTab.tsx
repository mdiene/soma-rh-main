import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { useState } from 'react'
import { dataApi, unwrap } from '../../lib/api'
import { useAuth } from '../../lib/auth'
import { date } from '../../lib/format'
import { Button, ErrorNote, Modal, Section, Spinner, TextField } from '../ui'
import { useRefreshCompliance } from './shared'

type Waiver = {
  id: string; rule_id: string; entity_id: string; reason: string; status: string; granted_at: string; ended_at: string | null; ended_reason: string | null
  employees: { employee_number: string; last_name: string; first_name: string } | null
}

/** Registre des dérogations : lecture pour RH/paie, révocation motivée réservée à l'administrateur. */
export function WaiversTab({ onNotice }: { onNotice: (m: string) => void }) {
  const isAdmin = useAuth().roles.includes('admin')
  const qc = useQueryClient()
  const refresh = useRefreshCompliance()
  const [target, setTarget] = useState<Waiver | null>(null)
  const [motif, setMotif] = useState('')

  const list = useQuery({
    queryKey: ['compliance', 'waivers'],
    queryFn: async () => unwrap(await dataApi.from('compliance_waivers')
      .select('id, rule_id, entity_id, reason, status, granted_at, ended_at, ended_reason, employees(employee_number, last_name, first_name)')
      .order('granted_at', { ascending: false })) as unknown as Waiver[],
  })
  const rules = useQuery({
    queryKey: ['compliance', 'rules'],
    queryFn: async () => Object.fromEntries((unwrap(await dataApi.from('compliance_rules').select('rule_id, label')) as { rule_id: string; label: string }[]).map((r) => [r.rule_id, r.label])),
  })
  const revoke = useMutation({
    mutationFn: async () => unwrap(await dataApi.rpc('revoke_waiver', { p_id: target!.id, p_reason: motif })),
    onSuccess: () => { setTarget(null); setMotif(''); refresh(); void qc.invalidateQueries({ queryKey: ['compliance'] }); onNotice('Dérogation révoquée.') },
  })

  const rows = list.data ?? []
  return (
    <Section title={`Registre des dérogations (${rows.length})`}>
      {list.isLoading ? <Spinner /> : list.isError ? <ErrorNote error={list.error} /> : rows.length === 0 ? (
        <p className="text-sm text-ink-muted">Aucune dérogation enregistrée.</p>
      ) : (
        <div className="overflow-x-auto">
          <table className="w-full text-sm">
            <thead><tr className="text-left text-ink-muted"><th className="py-1 pr-3">Règle</th><th className="pr-3">Salarié</th><th className="pr-3">Motif</th><th className="pr-3">Accordée le</th><th className="pr-3">Statut</th><th /></tr></thead>
            <tbody>
              {rows.map((w) => (
                <tr key={w.id} className="border-t border-line align-top">
                  <td className="py-1.5 pr-3">{rules.data?.[w.rule_id] ?? w.rule_id}</td>
                  <td className="pr-3">{w.employees ? `${w.employees.employee_number} ${w.employees.last_name} ${w.employees.first_name}` : '—'}</td>
                  <td className="pr-3">{w.reason}</td>
                  <td className="pr-3 tabular-nums">{date(w.granted_at)}</td>
                  <td className="pr-3">{w.status}{w.ended_reason ? <span className="block text-xs text-ink-muted">{w.ended_reason}</span> : null}</td>
                  <td>{isAdmin && w.status === 'active' && <Button size="sm" onClick={() => { setTarget(w); setMotif('') }}>Révoquer</Button>}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
      <Modal open={target !== null} title="Révoquer la dérogation" onClose={() => setTarget(null)}
        footer={<>
          <Button onClick={() => setTarget(null)}>Annuler</Button>
          <Button variant="primary" loading={revoke.isPending} disabled={!motif.trim()} onClick={() => revoke.mutate()}>Révoquer</Button>
        </>}>
        <TextField label="Motif de la révocation (obligatoire)" value={motif} onChange={(e) => setMotif(e.target.value)} />
        {revoke.isError && <ErrorNote error={revoke.error} />}
      </Modal>
    </Section>
  )
}
