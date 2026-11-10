import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import clsx from 'clsx'
import { CalendarCheck2, ChevronLeft, ChevronRight, Save } from 'lucide-react'
import { useEffect, useMemo, useState } from 'react'
import { useSearchParams } from 'react-router-dom'
import { dataApi, unwrap } from '../lib/api'
import { useAuth } from '../lib/auth'
import { useEmployees } from '../lib/queries'
import { date as fmtDate, monthLabel } from '../lib/format'
import { Button, Empty, ErrorNote, PageHeader, Section, Spinner, TextField } from '../components/ui'

/**
 * Planning métier (M6) — postes par salarié et par jour, à partir des modèles de postes des modules actifs.
 * Ordinateur : grille semaine, collage depuis Excel (lignes = salariés, colonnes = jours, cellules = codes de poste).
 * Mobile : une colonne, un jour à la fois. Le report alimente les présences et les heures de nuit de la paie.
 */

const iso = (d: Date) => d.toISOString().slice(0, 10)
const addDays = (d: string, n: number) => { const x = new Date(`${d}T12:00:00Z`); x.setUTCDate(x.getUTCDate() + n); return iso(x) }
const mondayOf = (d: string) => { const x = new Date(`${d}T12:00:00Z`); return addDays(d, -((x.getUTCDay() + 6) % 7)) }
const dayLabel = (d: string) => new Intl.DateTimeFormat('fr-FR', { weekday: 'short', day: '2-digit', timeZone: 'UTC' }).format(new Date(`${d}T12:00:00Z`))
const key = (emp: string, day: string) => `${emp}|${day}`

export default function PlanningPage() {
  const { can } = useAuth()
  const editable = can('rh') || can('paie')
  const qc = useQueryClient()
  const employees = useEmployees()
  const [params] = useSearchParams()
  const [week, setWeek] = useState(() => { const w = params.get('semaine'); return mondayOf(w && /^\d{4}-\d{2}-\d{2}$/.test(w) ? w : iso(new Date())) })
  const [dayIdx, setDayIdx] = useState(0)
  const [query, setQuery] = useState('')
  const [drafts, setDrafts] = useState<Record<string, string>>({})
  const [notice, setNotice] = useState<string | null>(null)
  const days = useMemo(() => Array.from({ length: 7 }, (_, i) => addDays(week, i)), [week])

  const templates = useQuery({
    queryKey: ['shift_templates'],
    queryFn: async () => unwrap(await dataApi.rpc('shift_templates')),
  })
  const shifts = useQuery({
    queryKey: ['module_shift', week],
    queryFn: async () => unwrap(await dataApi.from('module_shift').select('employee_id, work_date, shift_code').gte('work_date', week).lte('work_date', days[6])),
  })
  const concerned = useQuery({
    queryKey: ['module_staff'],
    queryFn: async () => unwrap(await dataApi.from('employee_module_data').select('employee_id')),
  })
  const compliance = useQuery({
    queryKey: ['planning_compliance', week],
    queryFn: async () => unwrap(await dataApi.rpc('planning_compliance', { p_from: week, p_to: days[6] })),
  })

  const saved = useMemo(() => new Map((shifts.data ?? []).map((s) => [key(s.employee_id, s.work_date), s.shift_code])), [shifts.data])
  useEffect(() => { setDrafts({}) }, [week, shifts.data])
  const valueOf = (emp: string, day: string) => drafts[key(emp, day)] ?? saved.get(key(emp, day)) ?? ''
  const codes = useMemo(() => new Set((templates.data ?? []).map((t) => t.code)), [templates.data])
  const changed = Object.entries(drafts).filter(([k, v]) => v !== (saved.get(k) ?? ''))
  const unknown = changed.filter(([, v]) => v !== '' && !codes.has(v))

  const staffIds = useMemo(() => new Set((concerned.data ?? []).map((c) => c.employee_id)), [concerned.data])
  const staff = useMemo(() => (employees.data ?? []).filter((e) => {
    if (e.status !== 'Active') return false
    if (staffIds.size > 0 && !staffIds.has(e.id)) return false
    const q = query.trim().toLowerCase()
    return !q || `${e.employee_number} ${e.first_name} ${e.last_name}`.toLowerCase().includes(q)
  }), [employees.data, staffIds, query])

  const save = useMutation({
    mutationFn: async () => unwrap(await dataApi.rpc('plan_shifts', {
      p_rows: changed.map(([k, v]) => { const [employee_id, work_date] = k.split('|'); return { employee_id, work_date, code: v } }),
    })),
    onSuccess: (n) => { setNotice(`${n} poste(s) enregistré(s).`); qc.invalidateQueries({ queryKey: ['module_shift'] }); qc.invalidateQueries({ queryKey: ['planning_compliance'] }) },
  })
  const apply = useMutation({
    mutationFn: async () => unwrap(await dataApi.rpc('apply_planning', { p_period: week })),
    onSuccess: (r) => {
      const x = r as { attendance_created: number; night_inputs: number }
      setNotice(`Report de ${monthLabel(week)} : ${x.attendance_created} présence(s) créée(s), ${x.night_inputs} saisie(s) d'heures de nuit.`)
      qc.invalidateQueries({ queryKey: ['attendance-day'] })
    },
  })

  /** Collage depuis Excel : la première cellule collée atterrit sur la cellule active (data-emp / data-day). */
  function onPaste(e: React.ClipboardEvent<HTMLDivElement>) {
    const t = (e.target as HTMLElement).closest('[data-emp]') as HTMLElement | null
    if (!t || !editable) return
    const r0 = staff.findIndex((s) => s.id === t.dataset.emp)
    const c0 = days.indexOf(t.dataset.day ?? '')
    if (r0 < 0 || c0 < 0) return
    e.preventDefault()
    const next: Record<string, string> = {}
    e.clipboardData.getData('text').replace(/\r/g, '').replace(/\n+$/, '').split('\n').forEach((line, i) =>
      line.split('\t').forEach((cell, j) => {
        const emp = staff[r0 + i], day = days[c0 + j]
        if (emp && day) next[key(emp.id, day)] = cell.trim().toUpperCase()
      }))
    setDrafts((d) => ({ ...d, ...next }))
  }

  const options = (templates.data ?? []).map((t) => <option key={t.code} value={t.code}>{t.code} — {t.label} ({t.hours} h)</option>)
  const cell = (emp: string, day: string, compact = false) => {
    const v = valueOf(emp, day)
    const bad = v !== '' && !codes.has(v)
    return (
      <select data-emp={emp} data-day={day} value={v} disabled={!editable} aria-label={`Poste du ${fmtDate(day)}`}
        onChange={(ev) => setDrafts((d) => ({ ...d, [key(emp, day)]: ev.target.value }))}
        className={clsx('rounded border bg-white py-1 text-xs tabular-nums', compact ? 'w-full px-2 py-2 text-sm' : 'w-full px-1',
          bad ? 'border-signal text-signal' : drafts[key(emp, day)] !== undefined && v !== (saved.get(key(emp, day)) ?? '') ? 'border-river bg-river/5' : 'border-ink/15')}>
        <option value="">—</option>
        {bad && <option value={v}>{v} (inconnu)</option>}
        {options}
      </select>
    )
  }

  const busy = templates.isLoading || shifts.isLoading || employees.isLoading
  return (
    <div>
      <PageHeader title="Planning métier"
        description="Postes par salarié et par jour, selon les modèles des modules actifs. Le report alimente les présences et les heures de nuit de la paie."
        actions={editable && (
          <>
            <Button icon={<Save size={16} />} loading={save.isPending} disabled={changed.length === 0 || unknown.length > 0} onClick={() => save.mutate()}>
              Enregistrer{changed.length > 0 ? ` (${changed.length})` : ''}
            </Button>
            <Button variant="primary" icon={<CalendarCheck2 size={16} />} loading={apply.isPending} disabled={changed.length > 0} onClick={() => apply.mutate()}>
              Reporter {monthLabel(week)}
            </Button>
          </>
        )} />
      <ErrorNote error={templates.error || shifts.error || save.error || apply.error} />
      {notice && <p role="status" className="mb-3 rounded bg-phosphate/10 px-3 py-2 text-sm">{notice}</p>}
      {unknown.length > 0 && <p role="alert" className="mb-3 text-sm text-signal">Code de poste inconnu dans {unknown.length} cellule(s) : corrigez avant d'enregistrer.</p>}

      <div className="mb-3 flex flex-wrap items-end gap-3">
        <div className="flex items-center gap-1">
          <Button size="sm" aria-label="Semaine précédente" onClick={() => setWeek(addDays(week, -7))} icon={<ChevronLeft size={16} />} />
          <span className="min-w-44 text-center text-sm font-medium tabular-nums">Semaine du {fmtDate(week)}</span>
          <Button size="sm" aria-label="Semaine suivante" onClick={() => setWeek(addDays(week, 7))} icon={<ChevronRight size={16} />} />
        </div>
        <TextField label="Rechercher" value={query} onChange={(e) => setQuery(e.target.value)} className="w-56" />
        {staffIds.size === 0 && !concerned.isLoading && (
          <p className="text-xs text-ink/60">Aucune fiche métier saisie : tous les salariés actifs sont listés.</p>
        )}
      </div>

      {busy ? <Spinner /> : (templates.data ?? []).length === 0 ? (
        <Empty title="Aucun modèle de poste">Activez un module métier (Gardiennage, Industrie et mines) pour disposer de modèles de postes.</Empty>
      ) : (
        <div onPaste={onPaste}>
          {/* ordinateur : grille semaine */}
          <div className="hidden overflow-x-auto sm:block">
            <table className="w-full min-w-[760px] border-collapse text-sm">
              <thead>
                <tr className="text-left text-xs text-ink/60">
                  <th className="sticky left-0 bg-paper py-2 pr-2">Salarié</th>
                  {days.map((d) => <th key={d} className="px-1 py-2 text-center font-medium capitalize">{dayLabel(d)}</th>)}
                </tr>
              </thead>
              <tbody>
                {staff.map((e) => (
                  <tr key={e.id} className="border-t border-ink/10">
                    <td className="sticky left-0 bg-paper py-1 pr-2"><span className="tabular-nums text-ink/50">{e.employee_number}</span> {e.last_name} {e.first_name}</td>
                    {days.map((d) => <td key={d} className="px-1 py-1">{cell(e.id, d)}</td>)}
                  </tr>
                ))}
              </tbody>
            </table>
            {editable && <p className="mt-2 text-xs text-ink/60">Collage depuis Excel : cliquez une cellule puis collez (Ctrl+V) un bloc de codes de poste.</p>}
          </div>

          {/* mobile : une colonne, un jour à la fois */}
          <div className="sm:hidden">
            <div className="mb-2 flex items-center justify-between">
              <Button size="sm" aria-label="Jour précédent" disabled={dayIdx === 0} onClick={() => setDayIdx(dayIdx - 1)} icon={<ChevronLeft size={16} />} />
              <span className="font-medium capitalize">{dayLabel(days[dayIdx])} — {fmtDate(days[dayIdx])}</span>
              <Button size="sm" aria-label="Jour suivant" disabled={dayIdx === 6} onClick={() => setDayIdx(dayIdx + 1)} icon={<ChevronRight size={16} />} />
            </div>
            <ul className="space-y-2">
              {staff.map((e) => (
                <li key={e.id} className="rounded border border-ink/10 bg-white p-2">
                  <div className="mb-1 text-sm">{e.last_name} {e.first_name}</div>
                  {cell(e.id, days[dayIdx], true)}
                </li>
              ))}
            </ul>
          </div>
        </div>
      )}

      <Section title="Conformité de la semaine" className="mt-6">
        {compliance.isLoading ? <Spinner /> : (compliance.data ?? []).length === 0 ? (
          <p className="text-sm text-ink/60">Aucune alerte sur les postes enregistrés de cette semaine.</p>
        ) : (
          <ul className="space-y-1 text-sm">
            {(compliance.data ?? []).map((a, i) => (
              <li key={i} className={clsx('rounded px-3 py-2', a.severity === 'erreur' ? 'bg-signal/10 text-signal' : 'bg-ink/5')}>
                <strong>{a.employee_name}</strong> — {a.message}
              </li>
            ))}
          </ul>
        )}
      </Section>
    </div>
  )
}
