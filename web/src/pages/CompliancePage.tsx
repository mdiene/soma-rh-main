import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { RefreshCw } from 'lucide-react'
import { useState } from 'react'
import { dataApi, unwrap } from '../lib/api'
import { useAuth } from '../lib/auth'
import { Button, ErrorNote, Modal, PageHeader, Section, Spinner, TextField } from '../components/ui'

/** Écran de conformité (C26-17) : constats ouverts, actualisation, dérogation motivée réservée au rôle RH. */
export default function CompliancePage() {
  const qc = useQueryClient()
  const { can } = useAuth()
  const [target, setTarget] = useState<string | null>(null)
  const [motif, setMotif] = useState('')

  const findings = useQuery({
    queryKey: ['compliance-findings'],
    queryFn: async () => unwrap(await dataApi.from('compliance_findings').select('*').is('resolved_on', null).order('severity').order('detected_on', { ascending: false })),
  })
  const refresh = useMutation({
    mutationFn: async () => unwrap(await dataApi.rpc('detecter_conformite')),
    onSuccess: () => qc.invalidateQueries({ queryKey: ['compliance-findings'] }),
  })
  const waive = useMutation({
    mutationFn: async () => unwrap(await dataApi.rpc('deroger_constat', { p_id: target!, p_motif: motif })),
    onSuccess: () => { setTarget(null); setMotif(''); qc.invalidateQueries({ queryKey: ['compliance-findings'] }) },
  })

  const rows = findings.data ?? []
  return (
    <div className="space-y-4">
      <PageHeader title="Conformité" description="Écarts au Code du Travail 2026 : alertes (A) et blocages (B). Une dérogation exige un motif écrit." />
      <div className="flex items-center gap-3">
        <Button icon={<RefreshCw className="size-4" />} loading={refresh.isPending} onClick={() => refresh.mutate()}>Actualiser les constats</Button>
        {refresh.isSuccess && <span className="text-sm text-ink-muted">{refresh.data} nouveau(x) constat(s)</span>}
      </div>
      {refresh.isError && <ErrorNote error={refresh.error} />}
      <Section title={`Constats ouverts (${rows.length})`}>
        {findings.isLoading ? <Spinner /> : findings.isError ? <ErrorNote error={findings.error} /> : rows.length === 0 ? (
          <p className="text-sm text-ink-muted">Aucun constat ouvert. Cliquez sur « Actualiser » pour relancer les contrôles.</p>
        ) : (
          <table className="w-full text-sm">
            <thead><tr className="text-left text-ink-muted"><th className="py-1">Niveau</th><th>Règle</th><th>Constat</th><th>Détecté le</th><th>Dérogation</th></tr></thead>
            <tbody>
              {rows.map((f) => (
                <tr key={f.id} className="border-t border-line align-top">
                  <td className="py-1.5 font-medium">{f.severity === 'B' ? 'Bloquant' : 'Alerte'}</td>
                  <td>{f.rule_id}</td>
                  <td>{f.message}</td>
                  <td className="tabular-nums">{f.detected_on}</td>
                  <td>
                    {f.waived_by ? <span title={f.waiver_reason ?? ''}>Dérogé : {f.waiver_reason}</span>
                      : can('rh') ? <Button size="sm" onClick={() => setTarget(f.id)}>Déroger</Button> : '—'}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </Section>
      <Modal open={target !== null} title="Dérogation motivée" onClose={() => setTarget(null)}
        footer={<>
          <Button onClick={() => setTarget(null)}>Annuler</Button>
          <Button variant="primary" loading={waive.isPending} disabled={!motif.trim()} onClick={() => waive.mutate()}>Enregistrer</Button>
        </>}>
        <TextField label="Motif (obligatoire)" value={motif} onChange={(e) => setMotif(e.target.value)} />
        {waive.isError && <ErrorNote error={waive.error} />}
      </Modal>
    </div>
  )
}
