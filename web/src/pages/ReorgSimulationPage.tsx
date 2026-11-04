import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { Trash2 } from 'lucide-react'
import { useMemo, useState } from 'react'
import { dataApi, unwrap, type ApiClient } from '../lib/api'
import { fullName, type OrgData } from '../lib/org'
import { Button, Empty, ErrorNote, PageHeader, SelectField, Spinner, TextField } from '../components/ui'

/** Simulation de réorganisation : on prépare des changements de manager direct, on voit l'effet (équipes, cycles, non rattachés),
 *  puis on les applique d'un coup via org_set_manager. Rien n'est écrit tant qu'on n'a pas cliqué sur « Appliquer ». */

const db = dataApi as unknown as ApiClient
const today = () => new Date().toISOString().slice(0, 10)
const SEUIL_EQUIPE = 8 // au-delà, l'étendue de contrôle est signalée
type Move = { employee: string; manager: string | null } // manager null = détacher

export default function ReorgSimulationPage() {
  const qc = useQueryClient()
  const chart = useQuery({ queryKey: ['org_chart', 'simulation'], queryFn: async () => unwrap(await db.rpc('org_chart', { p_on: today() })) as unknown as OrgData })
  const [moves, setMoves] = useState<Move[]>([])
  const [emp, setEmp] = useState(''); const [mgr, setMgr] = useState('')
  const [from, setFrom] = useState(today()); const [reason, setReason] = useState('')
  const [done, setDone] = useState<string | null>(null)

  const people = useMemo(() => [...(chart.data?.noeuds ?? [])].sort((a, b) => fullName(a).localeCompare(fullName(b), 'fr')), [chart.data])
  const name = (id: string | null | undefined) => { const p = people.find((x) => x.id === id); return p ? fullName(p) : 'Aucun manager' }
  const before = useMemo(() => new Map((chart.data?.liens ?? []).filter((l) => l.type === 'direct').map((l) => [l.target, l.source])), [chart.data])
  const after = useMemo(() => {
    const m = new Map(before)
    for (const v of moves) { if (v.manager) m.set(v.employee, v.manager); else m.delete(v.employee) }
    return m
  }, [before, moves])

  // la boucle se teste sur la hiérarchie telle qu'elle serait SANS le déplacement en cours de saisie
  const wouldCycle = (e: string, m: string | null) => {
    for (let cur = m, n = 0; cur && n < 1000; cur = after.get(cur) ?? null, n++) if (cur === e) return true
    return false
  }
  const error = !emp ? null : emp === mgr ? 'Un salarié ne peut pas être son propre manager.' : wouldCycle(emp, mgr || null) ? 'Ce changement créerait une boucle hiérarchique.' : null
  const add = () => { setMoves((x) => [...x.filter((v) => v.employee !== emp), { employee: emp, manager: mgr || null }]); setEmp(''); setMgr('') }

  const span = (map: Map<string, string>) => { const c = new Map<string, number>(); for (const m of map.values()) c.set(m, (c.get(m) ?? 0) + 1); return c }
  const spanBefore = useMemo(() => span(before), [before]); const spanAfter = useMemo(() => span(after), [after])
  const touched = [...new Set(moves.flatMap((v) => [before.get(v.employee), v.manager]).filter(Boolean) as string[])]
  const orphans = (map: Map<string, string>) => { const s = span(map); return people.filter((p) => !map.has(p.id) && !s.get(p.id)).length }

  const apply = useMutation({
    mutationFn: async () => {
      for (const v of moves) unwrap(await db.rpc('org_set_manager', { p_employee: v.employee, p_manager: v.manager, p_from: from, p_reason: reason || null }))
    },
    onSuccess: () => { setDone(`${moves.length} changement(s) appliqué(s) à compter du ${new Date(from + 'T00:00:00').toLocaleDateString('fr-FR')}.`); setMoves([]); void qc.invalidateQueries({ queryKey: ['org_chart'] }) },
  })

  return (
    <>
      <PageHeader title="Simulation de réorganisation" description="Préparez des changements de manager et mesurez leur effet avant de les appliquer. Rien n’est enregistré tant que vous n’avez pas appliqué." />
      <ErrorNote error={chart.error || apply.error} />
      {done && <p role="status" className="mb-4 rounded border border-phosphate/40 bg-phosphate-light px-3 py-2 text-sm">{done}</p>}
      {chart.isLoading ? <Spinner /> : (
        <>
          <section className="panel mb-6 p-4">
            <div className="grid gap-3 md:grid-cols-[1fr_1fr_auto] md:items-end">
              <SelectField label="Salarié à déplacer" value={emp} onChange={(e) => setEmp(e.target.value)}>
                <option value="">Choisir…</option>
                {people.map((p) => <option key={p.id} value={p.id}>{fullName(p)} — {p.poste}</option>)}
              </SelectField>
              <SelectField label="Nouveau manager direct" value={mgr} onChange={(e) => setMgr(e.target.value)} hint="Laisser vide pour le détacher de son manager.">
                <option value="">Aucun (détacher)</option>
                {people.filter((p) => p.id !== emp).map((p) => <option key={p.id} value={p.id}>{fullName(p)} — {p.poste}</option>)}
              </SelectField>
              <Button variant="primary" onClick={add} disabled={!emp || !!error}>Ajouter à la simulation</Button>
            </div>
            {error && <p role="alert" className="mt-2 text-sm text-signal">{error}</p>}
          </section>

          {moves.length === 0 ? <Empty title="Aucun changement simulé">Choisissez un salarié et son futur manager pour voir l’effet sur les équipes.</Empty> : (
            <>
              <section className="panel mb-6">
                <div className="border-b border-line px-4 py-3"><h2 className="text-base">Changements prévus</h2></div>
                <ul className="divide-y divide-line/70">
                  {moves.map((v) => (
                    <li key={v.employee} className="flex flex-wrap items-center gap-3 px-4 py-3 text-sm">
                      <span className="font-medium">{name(v.employee)}</span>
                      <span className="text-ink-muted">{name(before.get(v.employee))} → {name(v.manager)}</span>
                      <Button className="ml-auto" size="sm" variant="ghost" aria-label={`Retirer ${name(v.employee)}`} icon={<Trash2 className="h-4 w-4" />} onClick={() => setMoves((x) => x.filter((m) => m.employee !== v.employee))} />
                    </li>
                  ))}
                </ul>
              </section>

              <section className="panel mb-6">
                <div className="border-b border-line px-4 py-3">
                  <h2 className="text-base">Effet sur les équipes</h2>
                  <p className="text-xs text-ink-muted">Subordonnés directs avant → après. Orange : plus de {SEUIL_EQUIPE} personnes.</p>
                </div>
                <table className="w-full text-sm">
                  <thead><tr className="border-b border-line text-left text-xs text-ink-muted"><th className="px-4 py-2 font-semibold" scope="col">Manager</th><th className="px-3 py-2 text-right font-semibold" scope="col">Avant</th><th className="px-3 py-2 text-right font-semibold" scope="col">Après</th></tr></thead>
                  <tbody className="divide-y divide-line/70">
                    {touched.map((id) => {
                      const b = spanBefore.get(id) ?? 0; const a = spanAfter.get(id) ?? 0
                      return (
                        <tr key={id}>
                          <th scope="row" className="px-4 py-2 text-left font-medium">{name(id)}</th>
                          <td className="px-3 py-2 text-right tabular-nums">{b}</td>
                          <td className={`px-3 py-2 text-right tabular-nums ${a > SEUIL_EQUIPE ? 'font-semibold text-amber-700' : ''}`}>{a}{a !== b && <span className="ml-1 text-xs text-ink-muted">({a > b ? '+' : ''}{a - b})</span>}</td>
                        </tr>
                      )
                    })}
                    <tr><th scope="row" className="px-4 py-2 text-left font-medium">Salariés sans lien hiérarchique</th><td className="px-3 py-2 text-right tabular-nums">{orphans(before)}</td><td className="px-3 py-2 text-right tabular-nums">{orphans(after)}</td></tr>
                  </tbody>
                </table>
              </section>

              <section className="panel p-4">
                <div className="grid gap-3 md:grid-cols-[auto_1fr_auto] md:items-end">
                  <TextField label="Date d’effet" type="date" value={from} onChange={(e) => setFrom(e.target.value)} />
                  <TextField label="Motif (facultatif)" value={reason} onChange={(e) => setReason(e.target.value)} />
                  <Button variant="primary" loading={apply.isPending} disabled={!from}
                    onClick={() => { if (window.confirm(`Appliquer ${moves.length} changement(s) de manager ? Les salariés concernés seront notifiés.`)) apply.mutate() }}>
                    Appliquer {moves.length} changement{moves.length > 1 ? 's' : ''}
                  </Button>
                </div>
              </section>
            </>
          )}
        </>
      )}
    </>
  )
}
