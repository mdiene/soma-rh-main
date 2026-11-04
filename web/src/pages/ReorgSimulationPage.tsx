import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { Trash2 } from 'lucide-react'
import { useMemo, useState } from 'react'
import { dataApi, unwrap, type ApiClient } from '../lib/api'
import { LINK_LABEL, fullName, type LinkType, type OrgData } from '../lib/org'
import { Button, Empty, ErrorNote, PageHeader, SelectField, Spinner, TextField } from '../components/ui'

/** Simulation de réorganisation : on prépare des changements (manager direct, unité, lien hors hiérarchie), on voit l'effet
 *  (équipes, postes à pourvoir, boucles), puis on applique le tout en une transaction (org_apply_reorg : tout ou rien).
 *  La simulation n'est pas enregistrée : elle disparaît quand on quitte la page. */

const db = dataApi as unknown as ApiClient
const today = () => new Date().toISOString().slice(0, 10)
const SEUIL_EQUIPE = 8 // au-delà, l'étendue de contrôle est signalée
type Kind = 'manager' | 'unit' | 'relation'
type RelType = Exclude<LinkType, 'direct'>
type Move =
  | { kind: 'manager'; employee: string; manager: string | null }
  | { kind: 'unit'; employee: string; unit: string | null }
  | { kind: 'relation'; employee: string; related: string; type: RelType }
const KIND_LABEL: Record<Kind, string> = { manager: 'Manager direct', unit: 'Rattachement à une unité', relation: 'Lien pointillé / intérim / fonctionnel' }

export default function ReorgSimulationPage() {
  const qc = useQueryClient()
  const chart = useQuery({ queryKey: ['org_chart', 'simulation'], queryFn: async () => unwrap(await db.rpc('org_chart', { p_on: today() })) as unknown as OrgData })
  const [moves, setMoves] = useState<Move[]>([])
  const [kind, setKind] = useState<Kind>('manager')
  const [emp, setEmp] = useState(''); const [target, setTarget] = useState(''); const [relType, setRelType] = useState<RelType>('dotted')
  const [from, setFrom] = useState(today()); const [reason, setReason] = useState('')
  const [done, setDone] = useState<string | null>(null)

  const data = chart.data
  const people = useMemo(() => [...(data?.noeuds ?? [])].sort((a, b) => fullName(a).localeCompare(fullName(b), 'fr')), [data])
  const personName = (id: string | null | undefined) => { const p = people.find((x) => x.id === id); return p ? fullName(p) : 'Aucun'}
  const unitName = (id: string | null | undefined) => data?.unites.find((u) => u.id === id)?.nom ?? 'Sans unité'

  // hiérarchie directe avant / après
  const before = useMemo(() => new Map((data?.liens ?? []).filter((l) => l.type === 'direct').map((l) => [l.target, l.source])), [data])
  const after = useMemo(() => {
    const m = new Map(before)
    for (const v of moves) if (v.kind === 'manager') { if (v.manager) m.set(v.employee, v.manager); else m.delete(v.employee) }
    return m
  }, [before, moves])
  const span = (map: Map<string, string>) => { const c = new Map<string, number>(); for (const m of map.values()) c.set(m, (c.get(m) ?? 0) + 1); return c }
  const spanBefore = useMemo(() => span(before), [before]); const spanAfter = useMemo(() => span(after), [after])
  const orphans = (map: Map<string, string>) => { const s = span(map); return people.filter((p) => !map.has(p.id) && !s.get(p.id)).length }

  // unités avant / après
  const unitBefore = useMemo(() => new Map(people.map((p) => [p.id, p.unite])), [people])
  const unitAfter = useMemo(() => {
    const m = new Map(unitBefore)
    for (const v of moves) if (v.kind === 'unit') m.set(v.employee, v.unit)
    return m
  }, [unitBefore, moves])
  const unitMoves = moves.filter((v): v is Extract<Move, { kind: 'unit' }> => v.kind === 'unit')
  const touchedUnits = [...new Set(unitMoves.flatMap((v) => [unitBefore.get(v.employee), v.unit]).filter(Boolean) as string[])]
  const headcount = (map: Map<string, string | null>, unit: string) => [...map.values()].filter((u) => u === unit).length
  // postes : pourvus après = pourvus avant + arrivées − départs du même poste dans l'unité
  const vacancyRows = (data?.vacants ?? []).filter((v) => touchedUnits.includes(v.unite)).map((v) => {
    const delta = unitMoves.reduce((s, m) => {
      const p = people.find((x) => x.id === m.employee)
      if (!p || p.poste_id !== v.poste_id) return s
      return s + (m.unit === v.unite ? 1 : 0) - (unitBefore.get(m.employee) === v.unite ? 1 : 0)
    }, 0)
    return { ...v, vacantsApres: Math.max(0, v.prevus - (v.pourvus + delta)) }
  })

  const wouldCycle = (e: string, m: string | null) => {
    for (let cur = m, n = 0; cur && n < 1000; cur = after.get(cur) ?? null, n++) if (cur === e) return true
    return false
  }
  const error = !emp ? null
    : kind === 'manager' ? (emp === target ? 'Un salarié ne peut pas être son propre manager.' : wouldCycle(emp, target || null) ? 'Ce changement créerait une boucle hiérarchique.' : null)
    : kind === 'relation' ? (!target ? 'Choisissez la personne liée.' : emp === target ? 'Un salarié ne peut pas être lié à lui-même.' : null)
    : null
  const add = () => {
    const m: Move = kind === 'manager' ? { kind, employee: emp, manager: target || null }
      : kind === 'unit' ? { kind, employee: emp, unit: target || null } : { kind, employee: emp, related: target, type: relType }
    setMoves((x) => [...x.filter((v) => !(v.kind === m.kind && v.employee === m.employee && (m.kind !== 'relation' || (v as typeof m).related === m.related))), m])
    setEmp(''); setTarget('')
  }
  const describe = (v: Move) => v.kind === 'manager' ? `${personName(before.get(v.employee))} → ${personName(v.manager)}`
    : v.kind === 'unit' ? `${unitName(unitBefore.get(v.employee))} → ${unitName(v.unit)}` : `${LINK_LABEL[v.type]} avec ${personName(v.related)}`

  const apply = useMutation({
    mutationFn: async () => unwrap(await db.rpc('org_apply_reorg', { p_moves: moves, p_from: from, p_reason: reason || null })),
    onSuccess: () => { setDone(`${moves.length} changement(s) appliqué(s) à compter du ${new Date(from + 'T00:00:00').toLocaleDateString('fr-FR')}.`); setMoves([]); void qc.invalidateQueries({ queryKey: ['org_chart'] }) },
  })
  const touchedManagers = [...new Set(moves.filter((v) => v.kind === 'manager').flatMap((v) => [before.get(v.employee), (v as { manager: string | null }).manager]).filter(Boolean) as string[])]
  const th = 'px-3 py-2 text-right font-semibold'

  return (
    <>
      <PageHeader title="Simulation de réorganisation" description="Préparez des changements et mesurez leur effet avant de les appliquer. Rien n’est enregistré tant que vous n’avez pas appliqué ; tout est appliqué ensemble ou pas du tout." />
      <ErrorNote error={chart.error || apply.error} />
      {done && <p role="status" className="mb-4 rounded border border-phosphate/40 bg-phosphate-light px-3 py-2 text-sm">{done}</p>}
      {chart.isLoading ? <Spinner /> : (
        <>
          <section className="panel mb-6 p-4">
            <div className="grid gap-3 md:grid-cols-4 md:items-end">
              <SelectField label="Type de changement" value={kind} onChange={(e) => { setKind(e.target.value as Kind); setTarget('') }}>
                {(Object.keys(KIND_LABEL) as Kind[]).map((k) => <option key={k} value={k}>{KIND_LABEL[k]}</option>)}
              </SelectField>
              <SelectField label="Salarié concerné" value={emp} onChange={(e) => setEmp(e.target.value)}>
                <option value="">Choisir…</option>
                {people.map((p) => <option key={p.id} value={p.id}>{fullName(p)} — {p.poste}</option>)}
              </SelectField>
              {kind === 'unit' ? (
                <SelectField label="Nouvelle unité" value={target} onChange={(e) => setTarget(e.target.value)} hint="Laisser vide pour le détacher de son unité.">
                  <option value="">Aucune (détacher)</option>
                  {(data?.unites ?? []).map((u) => <option key={u.id} value={u.id}>{u.nom}</option>)}
                </SelectField>
              ) : (
                <SelectField label={kind === 'manager' ? 'Nouveau manager direct' : 'Personne liée'} value={target} onChange={(e) => setTarget(e.target.value)} hint={kind === 'manager' ? 'Laisser vide pour le détacher de son manager.' : undefined}>
                  <option value="">{kind === 'manager' ? 'Aucun (détacher)' : 'Choisir…'}</option>
                  {people.filter((p) => p.id !== emp).map((p) => <option key={p.id} value={p.id}>{fullName(p)} — {p.poste}</option>)}
                </SelectField>
              )}
              {kind === 'relation' && (
                <SelectField label="Nature du lien" value={relType} onChange={(e) => setRelType(e.target.value as RelType)}>
                  {(Object.keys(LINK_LABEL) as RelType[]).map((t) => <option key={t} value={t}>{LINK_LABEL[t]}</option>)}
                </SelectField>
              )}
              <Button variant="primary" onClick={add} disabled={!emp || !!error}>Ajouter à la simulation</Button>
            </div>
            {error && <p role="alert" className="mt-2 text-sm text-signal">{error}</p>}
          </section>

          {moves.length === 0 ? <Empty title="Aucun changement simulé">Choisissez un type de changement et un salarié pour voir l’effet sur les équipes et les postes.</Empty> : (
            <>
              <section className="panel mb-6">
                <div className="border-b border-line px-4 py-3"><h2 className="text-base">Changements prévus</h2></div>
                <ul className="divide-y divide-line/70">
                  {moves.map((v, i) => (
                    <li key={i} className="flex flex-wrap items-center gap-3 px-4 py-3 text-sm">
                      <span className="rounded border border-line px-1.5 py-0.5 text-xs text-ink-soft">{KIND_LABEL[v.kind]}</span>
                      <span className="font-medium">{personName(v.employee)}</span>
                      <span className="text-ink-muted">{describe(v)}</span>
                      <Button className="ml-auto" size="sm" variant="ghost" aria-label={`Retirer le changement de ${personName(v.employee)}`} icon={<Trash2 className="h-4 w-4" />} onClick={() => setMoves((x) => x.filter((_, j) => j !== i))} />
                    </li>
                  ))}
                </ul>
              </section>

              {touchedManagers.length > 0 && (
                <section className="panel mb-6">
                  <div className="border-b border-line px-4 py-3">
                    <h2 className="text-base">Effet sur les équipes</h2>
                    <p className="text-xs text-ink-muted">Subordonnés directs avant → après. Orange : plus de {SEUIL_EQUIPE} personnes.</p>
                  </div>
                  <table className="w-full text-sm">
                    <thead><tr className="border-b border-line text-left text-xs text-ink-muted"><th className="px-4 py-2 font-semibold" scope="col">Manager</th><th className={th} scope="col">Avant</th><th className={th} scope="col">Après</th></tr></thead>
                    <tbody className="divide-y divide-line/70">
                      {touchedManagers.map((id) => {
                        const b = spanBefore.get(id) ?? 0; const a = spanAfter.get(id) ?? 0
                        return (
                          <tr key={id}>
                            <th scope="row" className="px-4 py-2 text-left font-medium">{personName(id)}</th>
                            <td className="px-3 py-2 text-right tabular-nums">{b}</td>
                            <td className={`px-3 py-2 text-right tabular-nums ${a > SEUIL_EQUIPE ? 'font-semibold text-amber-700' : ''}`}>{a}{a !== b && <span className="ml-1 text-xs text-ink-muted">({a > b ? '+' : ''}{a - b})</span>}</td>
                          </tr>
                        )
                      })}
                      <tr><th scope="row" className="px-4 py-2 text-left font-medium">Salariés sans lien hiérarchique</th><td className="px-3 py-2 text-right tabular-nums">{orphans(before)}</td><td className="px-3 py-2 text-right tabular-nums">{orphans(after)}</td></tr>
                    </tbody>
                  </table>
                </section>
              )}

              {touchedUnits.length > 0 && (
                <section className="panel mb-6">
                  <div className="border-b border-line px-4 py-3">
                    <h2 className="text-base">Effet sur les unités et les postes à pourvoir</h2>
                    <p className="text-xs text-ink-muted">Un poste est pourvu quand un salarié de ce poste est rattaché à l’unité.</p>
                  </div>
                  <table className="w-full text-sm">
                    <thead><tr className="border-b border-line text-left text-xs text-ink-muted"><th className="px-4 py-2 font-semibold" scope="col">Unité</th><th className={th} scope="col">Effectif avant</th><th className={th} scope="col">Effectif après</th></tr></thead>
                    <tbody className="divide-y divide-line/70">
                      {touchedUnits.map((u) => (
                        <tr key={u}><th scope="row" className="px-4 py-2 text-left font-medium">{unitName(u)}</th><td className="px-3 py-2 text-right tabular-nums">{headcount(unitBefore, u)}</td><td className="px-3 py-2 text-right tabular-nums">{headcount(unitAfter, u)}</td></tr>
                      ))}
                    </tbody>
                  </table>
                  {vacancyRows.length > 0 && (
                    <table className="w-full border-t border-line text-sm">
                      <thead><tr className="border-b border-line text-left text-xs text-ink-muted"><th className="px-4 py-2 font-semibold" scope="col">Poste prévu</th><th className={th} scope="col">À pourvoir avant</th><th className={th} scope="col">À pourvoir après</th></tr></thead>
                      <tbody className="divide-y divide-line/70">
                        {vacancyRows.map((v) => (
                          <tr key={v.id}><th scope="row" className="px-4 py-2 text-left font-medium">{v.poste} <span className="font-normal text-ink-muted">· {unitName(v.unite)}</span></th><td className="px-3 py-2 text-right tabular-nums">{v.vacants}</td><td className={`px-3 py-2 text-right tabular-nums ${v.vacantsApres !== v.vacants ? 'font-semibold' : ''}`}>{v.vacantsApres}</td></tr>
                        ))}
                      </tbody>
                    </table>
                  )}
                </section>
              )}

              <section className="panel p-4">
                <div className="grid gap-3 md:grid-cols-[auto_1fr_auto] md:items-end">
                  <TextField label="Date d’effet" type="date" value={from} onChange={(e) => setFrom(e.target.value)} hint="Pour les rattachements aux unités, l’effet est immédiat." />
                  <TextField label="Motif (facultatif)" value={reason} onChange={(e) => setReason(e.target.value)} />
                  <Button variant="primary" loading={apply.isPending} disabled={!from}
                    onClick={() => { if (window.confirm(`Appliquer ${moves.length} changement(s) ? Tout est appliqué ensemble ou pas du tout ; les salariés concernés seront notifiés.`)) apply.mutate() }}>
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
