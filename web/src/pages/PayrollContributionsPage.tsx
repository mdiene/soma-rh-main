import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { CheckCircle2 } from 'lucide-react'
import { useMemo, useState } from 'react'
import { useSearchParams } from 'react-router-dom'
import { dataApi, unwrap, type ApiClient } from '../lib/api'
import { useAuth } from '../lib/auth'
import { date, fcfa, monthLabel } from '../lib/format'
import { usePaymentModes } from '../lib/queries'
import { Badge, Button, ErrorNote, Modal, PageHeader, SelectField, Section, Spinner, TextField } from '../components/ui'

const db = dataApi as unknown as ApiClient
type Row = {
  mois: string; caisse: string; montant_du: number; dans_echeancier: boolean
  statut: 'À payer' | 'Payé'; paye_le: string | null; mode: string | null; montant_paye: number | null; reference: string | null; note: string | null
}
const today = () => new Date().toISOString().slice(0, 10)
const due = (r: Row) => Math.round(Number(r.montant_du))

/** Suivi des versements de cotisations : historique par mois, détail par caisse, marquage « payé » avec mode et référence (reçu, virement, chèque). */
export default function PayrollContributionsPage() {
  const { can } = useAuth()
  const qc = useQueryClient()
  const [params, setParams] = useSearchParams()
  const modes = usePaymentModes()
  const [sel, setSel] = useState<Set<string>>(new Set())
  const [open, setOpen] = useState(false)
  const [f, setF] = useState({ paid_at: today(), payment_mode: 'virement', reference: '' })

  const q = useQuery({
    queryKey: ['contribution_follow'],
    queryFn: async () => unwrap(await db.from('v_contribution_follow').select('*').order('mois', { ascending: false }).order('caisse')) as Row[],
  })
  const rows = useMemo(() => q.data ?? [], [q.data])
  const months = useMemo(() => {
    const m = new Map<string, Row[]>()
    for (const r of rows) m.set(r.mois, [...(m.get(r.mois) ?? []), r])
    return [...m.entries()].map(([mois, list]) => {
      const total = list.reduce((s, r) => s + due(r), 0)
      const paid = list.filter((r) => r.statut === 'Payé')
      const paidTotal = paid.reduce((s, r) => s + due(r), 0)
      return { mois, list, total, paidTotal, nbPaid: paid.length, state: paid.length === list.length ? 'Payé' : paid.length === 0 ? 'À payer' : 'Partiel' }
    })
  }, [rows])
  const asked = params.get('mois')
  // un mois inconnu dans l'adresse n'affiche rien : on retombe sur le premier mois à payer
  const month = (asked && months.some((m) => m.mois === asked) ? asked : null) ?? months.find((m) => m.state !== 'Payé')?.mois ?? months[0]?.mois
  const cur = months.find((m) => m.mois === month)
  const canPay = can('paie')

  const choose = (m: string) => { setSel(new Set()); setParams({ mois: m }, { replace: true }) }
  const toggle = (c: string) => setSel((s) => { const n = new Set(s); if (n.has(c)) n.delete(c); else n.add(c); return n })
  const mark = useMutation({
    mutationFn: async (paid: boolean) => {
      const recs = [...sel].map((caisse) => paid
        ? { month, caisse, status: 'Payé', paid_at: f.paid_at, payment_mode: f.payment_mode, reference: f.reference.trim() || null }
        : { month, caisse, status: 'À payer', paid_at: null, payment_mode: null, reference: null })
      return unwrap(await db.from('contribution_payment_lines').upsert(recs, { onConflict: 'month,caisse' }))
    },
    onSuccess: () => {
      setOpen(false); setSel(new Set()); setF((x) => ({ ...x, reference: '' }))
      void qc.invalidateQueries({ queryKey: ['contribution_follow'] }); void qc.invalidateQueries({ queryKey: ['compliance'] }); void qc.invalidateQueries({ queryKey: ['echeancier'] })
    },
  })

  const all = months.reduce((s, m) => s + m.total, 0)
  const allPaid = months.reduce((s, m) => s + m.paidTotal, 0)

  return (
    <>
      <PageHeader title="Suivi des cotisations"
        description="Versements aux caisses (IPRES, Caisse de sécurité sociale, IPM, impôts) : ce qui est payé, avec le mode et le n° de reçu, de virement ou de chèque, et ce qui reste à payer. Seuls les bulletins validés comptent." />
      <ErrorNote error={q.error || mark.error} />
      {q.isLoading ? <Spinner /> : months.length === 0 ? <p className="panel px-4 py-3 text-sm text-ink-soft">Aucun bulletin validé : aucune cotisation à suivre.</p> : (
        <>
          <div className="panel mb-4 grid grid-cols-2 gap-x-6 gap-y-3 p-4 sm:grid-cols-3">
            <div><p className="text-xs text-ink-muted">Cotisations dues (tous mois)</p><p className="text-lg font-semibold tabular-nums">{fcfa(all)} F</p></div>
            <div><p className="text-xs text-ink-muted">Payé</p><p className="text-lg font-semibold tabular-nums">{fcfa(allPaid)} F</p></div>
            <div><p className="text-xs text-ink-muted">Reste à payer</p><p className="text-lg font-semibold tabular-nums">{fcfa(all - allPaid)} F</p></div>
          </div>

          <Section title="Historique par mois" className="mb-4">
            <div className="overflow-auto">
              <table className="w-full text-sm">
                <thead><tr className="table-head"><th className="px-3 py-2">Mois</th><th className="px-3 py-2 text-right">Dû</th><th className="px-3 py-2 text-right">Payé</th><th className="px-3 py-2 text-right">Reste</th><th className="px-3 py-2">Caisses payées</th><th className="px-3 py-2">État</th></tr></thead>
                <tbody>{months.map((m) => (
                  <tr key={m.mois} className={`border-b border-line/70 ${m.mois === month ? 'bg-river-light' : ''}`}>
                    <td className="px-3 py-1.5"><button type="button" className="font-medium text-river hover:underline" aria-current={m.mois === month} onClick={() => choose(m.mois)}>{monthLabel(m.mois)}</button></td>
                    <td className="px-3 py-1.5 text-right tabular-nums">{fcfa(m.total)}</td>
                    <td className="px-3 py-1.5 text-right tabular-nums">{fcfa(m.paidTotal)}</td>
                    <td className="px-3 py-1.5 text-right tabular-nums">{fcfa(m.total - m.paidTotal)}</td>
                    <td className="px-3 py-1.5 tabular-nums">{m.nbPaid}/{m.list.length}</td>
                    <td className="px-3 py-1.5"><Badge value={m.state === 'Partiel' ? 'En attente' : m.state} label={m.state === 'Payé' ? 'Soldé' : m.state === 'Partiel' ? 'Partiel' : 'À payer'} /></td>
                  </tr>
                ))}</tbody>
              </table>
            </div>
          </Section>

          {cur && (
            <Section title={`Détail — ${monthLabel(cur.mois)}`}
              actions={canPay && (
                <div className="flex gap-2">
                  <Button size="sm" disabled={cur.list.every((r) => r.statut === 'Payé')} onClick={() => setSel(new Set(cur.list.filter((r) => r.statut !== 'Payé').map((r) => r.caisse)))}>Sélectionner ce qui reste à payer</Button>
                  <Button size="sm" variant="primary" icon={<CheckCircle2 className="h-4 w-4" />} disabled={sel.size === 0} onClick={() => setOpen(true)}>Marquer payé ({sel.size})</Button>
                </div>
              )}>
              <div className="overflow-auto">
                <table className="w-full text-sm">
                  <thead><tr className="table-head">
                    {canPay && <th className="w-8 px-3 py-2" />}<th className="px-3 py-2">Caisse</th><th className="px-3 py-2 text-right">Dû</th><th className="px-3 py-2">État</th>
                    <th className="px-3 py-2">Payé le</th><th className="px-3 py-2">Mode</th><th className="px-3 py-2">Reçu / virement / chèque</th>
                  </tr></thead>
                  <tbody>{cur.list.map((r) => (
                    <tr key={r.caisse} className="border-b border-line/70">
                      {canPay && <td className="px-3 py-1.5"><input type="checkbox" className="h-4 w-4 accent-river" aria-label={`Sélectionner ${r.caisse}`} checked={sel.has(r.caisse)} onChange={() => toggle(r.caisse)} /></td>}
                      <td className="px-3 py-1.5 font-medium">{r.caisse}{r.dans_echeancier ? '' : <span className="ml-2 text-xs font-normal text-ink-muted">hors échéancier</span>}</td>
                      <td className="px-3 py-1.5 text-right tabular-nums">{fcfa(due(r))}</td>
                      <td className="px-3 py-1.5"><Badge value={r.statut} /></td>
                      <td className="px-3 py-1.5">{r.paye_le ? date(r.paye_le) : ''}</td>
                      <td className="px-3 py-1.5">{r.mode ?? ''}</td>
                      <td className="px-3 py-1.5">{r.reference ?? ''}</td>
                    </tr>
                  ))}</tbody>
                  <tfoot><tr className="font-semibold"><td colSpan={canPay ? 2 : 1} className="px-3 py-2">Total</td><td className="px-3 py-2 text-right tabular-nums">{fcfa(cur.total)}</td><td colSpan={4} /></tr></tfoot>
                </table>
              </div>
              <p className="mt-2 text-xs text-ink-muted">Le mois est considéré comme versé dans l’échéancier légal quand l’IPRES et la Caisse de sécurité sociale sont toutes deux payées.</p>
            </Section>
          )}
        </>
      )}

      <Modal open={open} onClose={() => setOpen(false)} title={`Marquer ${sel.size} versement(s) payé(s)`}
        footer={<>
          <Button variant="ghost" onClick={() => setOpen(false)}>Annuler</Button>
          <Button variant="primary" loading={mark.isPending} disabled={!f.paid_at || !f.payment_mode} onClick={() => mark.mutate(true)}>Confirmer</Button>
        </>}>
        <div className="grid gap-3 sm:grid-cols-2">
          <TextField label="Date de paiement" type="date" max={today()} value={f.paid_at} onChange={(e) => setF({ ...f, paid_at: e.target.value })} />
          <SelectField label="Mode de paiement" value={f.payment_mode} onChange={(e) => setF({ ...f, payment_mode: e.target.value })}>
            {(modes.data ?? []).filter((m) => m.is_active || m.code === f.payment_mode).map((m) => <option key={m.code} value={m.code}>{m.label}</option>)}
          </SelectField>
          <TextField className="sm:col-span-2" label="N° de reçu, de virement ou de chèque" maxLength={100} value={f.reference} onChange={(e) => setF({ ...f, reference: e.target.value })}
            hint="Facultatif. Si plusieurs caisses sont cochées, la même référence s’applique à toutes ; marquez-les une par une pour des références différentes." />
        </div>
        {[...sel].some((c) => cur?.list.find((r) => r.caisse === c)?.statut === 'Payé') && (
          <Button className="mt-3" variant="ghost" onClick={() => mark.mutate(false)}>Remettre « à payer »</Button>
        )}
      </Modal>
    </>
  )
}
