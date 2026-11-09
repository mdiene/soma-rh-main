import { useMutation, useQuery } from '@tanstack/react-query'
import { ChevronDown, ChevronRight, Plus, RotateCcw, Trash2 } from 'lucide-react'
import { useMemo, useState } from 'react'
import { dataApi, unwrap } from '../../lib/api'
import { useAuth } from '../../lib/auth'
import type { Json } from '../../lib/database.types'
import {
  SCALE_GROUPS, dateToMonth, effectLabel, fromRows, monthToDate, showCell, toRows, type Col, type Group, type Line, type Row,
} from '../../lib/compliance'
import { Badge, Button, ErrorNote, Modal, Section, Spinner } from '../ui'
import { EffectDateField, ReferenceModal } from './ConstantsTab'
import { STATUS_LABEL, doneMessage, type LegalSource } from './shared'

type ScaleRow = {
  code: string; label: string; sort: number; effective_from: string | null; is_modified: boolean; nb_versions: number; next_free_date: string | null
  source_code: string | null; source_label: string | null; source_document: string | null; source_article: string | null
  source_status: string | null; legal_text: string | null
}

export function ScalesPanel({ floor, onNotice, refresh, sources }: {
  floor: string | null; onNotice: (m: string) => void; refresh: () => void; sources: LegalSource[]
}) {
  const { roles } = useAuth()
  const isAdmin = roles.includes('admin')
  const overview = useQuery({ queryKey: ['scale_overview'], queryFn: async () => unwrap(await dataApi.rpc('scale_overview')) as ScaleRow[] })
  const pending = useQuery({
    queryKey: ['approval_requests', 'pending'],
    queryFn: async () => unwrap(await dataApi.rpc('approval_requests_overview', { p_status: 'en_attente' })),
  })
  const [open, setOpen] = useState<string | null>(null)
  const [edit, setEdit] = useState<ScaleRow | null>(null)
  const [reset, setReset] = useState<ScaleRow | null>(null)
  const [ref, setRef] = useState<ScaleRow | null>(null)
  const pendingCodes = useMemo(() => new Set((pending.data ?? []).filter((p) => p.kind === 'bareme').map((p) => p.target)), [pending.data])

  if (overview.isLoading) return <Spinner />
  return (
    <Section title="Barèmes">
      <p className="mb-3 max-w-prose text-sm text-ink-soft">
        Un barème est un jeu de lignes daté : modifier crée une nouvelle version à la date choisie, les versions utilisées par des paies calculées ne changent jamais.
      </p>
      <ErrorNote error={overview.error} />
      <ul className="space-y-3">
        {(overview.data ?? []).map((s) => {
          const isOpen = open === s.code
          return (
            <li key={s.code} className="rounded border border-line">
              <div className="flex flex-wrap items-start justify-between gap-3 px-3 py-2.5">
                <div className="min-w-0">
                  <button type="button" className="flex items-start gap-1 text-left font-medium hover:text-river" aria-expanded={isOpen}
                    aria-controls={`scale-${s.code}`} onClick={() => setOpen(isOpen ? null : s.code)}>
                    {isOpen ? <ChevronDown className="mt-0.5 h-4 w-4 shrink-0" aria-hidden /> : <ChevronRight className="mt-0.5 h-4 w-4 shrink-0" aria-hidden />}
                    <span>{s.label}</span>
                  </button>
                  <p className="ml-5 mt-0.5 flex flex-wrap items-center gap-1.5 text-xs text-ink-soft">
                    <span>Version en vigueur depuis le {effectLabel(s.effective_from)}</span>
                    <span>· {s.nb_versions} version{s.nb_versions > 1 ? 's' : ''}</span>
                    {s.is_modified && <Badge value="Modifiée" />}
                    {pendingCodes.has(s.code) && <Badge value="En attente" label="Demande en attente" />}
                  </p>
                </div>
                <span className="inline-flex flex-wrap gap-1.5">
                  <Button size="sm" onClick={() => setEdit(s)} aria-label={`Modifier le barème : ${s.label}`}>Modifier</Button>
                  <Button size="sm" icon={<RotateCcw className="h-3.5 w-3.5" aria-hidden />} onClick={() => setReset(s)}
                    aria-label={`Réinitialiser le barème : ${s.label}`}>Réinitialiser</Button>
                </span>
              </div>
              {isOpen && (
                <div id={`scale-${s.code}`} className="border-t border-line bg-paper/60 px-4 py-3 text-sm">
                  <p className="font-medium text-ink">Ce que prévoit la loi</p>
                  <p className="mt-1 max-w-prose text-ink-soft">{s.legal_text ?? 'Texte à fournir.'}</p>
                  <p className="mt-2 text-xs text-ink-muted">
                    {s.source_code
                      ? <>Référence : {s.source_label}{s.source_document ? ` — ${s.source_document}` : ''}{s.source_article ? `, art. ${s.source_article}` : ''} ({STATUS_LABEL[s.source_status ?? ''] ?? s.source_status}).</>
                      : 'Aucune référence juridique renseignée.'}
                  </p>
                  {isAdmin && <Button size="sm" className="mt-2" onClick={() => setRef(s)}>Régler la référence légale</Button>}
                  <ScaleDetail code={s.code} />
                </div>
              )}
            </li>
          )
        })}
      </ul>

      {edit && <ScaleEditor scale={edit} floor={floor} isAdmin={isAdmin} onClose={() => setEdit(null)} onDone={(m) => { setEdit(null); refresh(); onNotice(m) }} />}
      {reset && <ScaleReset scale={reset} floor={floor} isAdmin={isAdmin} onClose={() => setReset(null)} onDone={(m) => { setReset(null); refresh(); onNotice(m) }} />}
      {ref && <ReferenceModal scale row={ref} sources={sources} onClose={() => setRef(null)} onDone={() => { setRef(null); refresh(); onNotice('Référence légale enregistrée.') }} />}
    </Section>
  )
}

/* ----------------------------------------------------- lecture : lignes en vigueur et versions */
function groupLines(code: string, data: unknown): { group: Group; lines: Line[] }[] {
  const groups = SCALE_GROUPS[code] ?? []
  return groups.map((g) => ({ group: g, lines: ((g.key === null ? data : (data as Record<string, unknown>)?.[g.key]) ?? []) as Line[] }))
}

function ScaleDetail({ code }: { code: string }) {
  const lines = useQuery({ queryKey: ['scale_lines', code], queryFn: async () => unwrap(await dataApi.rpc('scale_get', { p_code: code })) as unknown })
  const versions = useQuery({ queryKey: ['scale_versions', code], queryFn: async () => unwrap(await dataApi.rpc('scale_versions', { p_code: code })) })
  if (lines.isLoading || versions.isLoading) return <Spinner />
  return (
    <div className="mt-3 space-y-4">
      <ErrorNote error={lines.error || versions.error} />
      {groupLines(code, lines.data).map(({ group, lines: ls }, gi) => (
        <div key={gi} className="overflow-x-auto">
          {group.title && <h4 className="mb-1 text-xs font-semibold text-ink">{group.title}</h4>}
          <table className="w-full text-sm">
            <caption className="sr-only">{group.title ?? 'Lignes du barème en vigueur'}</caption>
            <thead><tr className="table-head">{group.cols.map((c) => <th key={c.key} scope="col" className={`px-2 py-1 ${c.kind === 'text' ? 'text-left' : 'text-right'}`}>{c.label}</th>)}</tr></thead>
            <tbody>
              {ls.map((l, i) => (
                <tr key={i} className="border-b border-line/70">
                  {group.cols.map((c) => <td key={c.key} className={`num px-2 py-1 ${c.kind === 'text' ? 'text-left' : 'text-right'}`}>{showCell(l[c.key], c.kind)}</td>)}
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      ))}
      <div className="overflow-x-auto">
        <h4 className="mb-1 text-xs font-semibold text-ink">Versions</h4>
        <table className="w-full text-sm">
          <caption className="sr-only">Versions datées du barème</caption>
          <thead><tr className="table-head"><th scope="col" className="px-2 py-1 text-left">En vigueur depuis</th><th scope="col" className="px-2 py-1 text-right">Lignes</th><th scope="col" className="px-2 py-1 text-left">État</th></tr></thead>
          <tbody>
            {(versions.data ?? []).map((v) => (
              <tr key={v.effective_from} className="border-b border-line/70">
                <td className="px-2 py-1">{effectLabel(v.effective_from)}</td>
                <td className="num px-2 py-1 text-right">{v.nb_lines}</td>
                <td className="px-2 py-1 text-xs text-ink-soft">{v.locked ? 'Verrouillée : sert à des paies déjà calculées' : 'Modifiable'}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  )
}

/* --------------------------------------------------------------------------- édition */
function ScaleEditor({ scale, floor, isAdmin, onClose, onDone }: {
  scale: ScaleRow; floor: string | null; isAdmin: boolean; onClose: () => void; onDone: (m: string) => void
}) {
  const lines = useQuery({ queryKey: ['scale_lines', scale.code], queryFn: async () => unwrap(await dataApi.rpc('scale_get', { p_code: scale.code })) as unknown })
  return (
    <Modal open wide title={`Nouvelle version : ${scale.label}`} onClose={onClose}>
      {lines.isLoading ? <Spinner /> : lines.error ? <ErrorNote error={lines.error} /> : (
        <EditorBody scale={scale} floor={floor} isAdmin={isAdmin} initial={lines.data} onClose={onClose} onDone={onDone} />
      )}
    </Modal>
  )
}

function EditorBody({ scale, floor, isAdmin, initial, onClose, onDone }: {
  scale: ScaleRow; floor: string | null; isAdmin: boolean; initial: unknown; onClose: () => void; onDone: (m: string) => void
}) {
  const cfg = SCALE_GROUPS[scale.code] ?? []
  const [month, setMonth] = useState(dateToMonth(floor) || new Date().toISOString().slice(0, 7))
  const [groups, setGroups] = useState<Row[][]>(() => groupLines(scale.code, initial).map(({ group, lines }) => toRows(lines, group.cols)))
  const [errors, setErrors] = useState<string[]>([])
  const save = useMutation({
    mutationFn: async (payload: unknown) =>
      unwrap(await dataApi.rpc('request_scale_change', { p_code: scale.code, p_effective_from: monthToDate(month) as string, p_lines: payload as Json })),
    onSuccess: () => onDone(doneMessage(isAdmin, 'Nouvelle version du barème')),
  })
  const submit = () => {
    const parts = groups.map((rows, i) => fromRows(rows, cfg[i].cols))
    const errs = parts.flatMap((p, i) => p.errors.map((e) => (cfg.length > 1 ? `${cfg[i].title} — ${e}` : e)))
    setErrors(errs)
    if (errs.length) return
    save.mutate(cfg[0].key === null ? parts[0].lines : Object.fromEntries(cfg.map((g, i) => [g.key as string, parts[i].lines])))
  }
  const setRows = (gi: number, rows: Row[]) => setGroups((g) => g.map((x, i) => (i === gi ? rows : x)))
  return (
    <div className="space-y-4">
      <EffectDateField floor={floor} value={month} onChange={setMonth} />
      {cfg.map((g, gi) => (
        <LinesEditor key={gi} group={g} rows={groups[gi]} onChange={(rows) => setRows(gi, rows)} />
      ))}
      {errors.length > 0 && (
        <ul role="alert" className="space-y-1 rounded border border-signal bg-signal-light px-3 py-2 text-sm font-medium text-signal">
          {errors.map((e) => <li key={e}>{e}</li>)}
        </ul>
      )}
      <ErrorNote error={save.error} />
      <div className="flex justify-end gap-2 border-t border-line pt-3">
        <Button onClick={onClose}>Annuler</Button>
        <Button variant="primary" loading={save.isPending} disabled={!monthToDate(month)} onClick={submit}>{isAdmin ? 'Appliquer' : 'Envoyer pour validation'}</Button>
      </div>
    </div>
  )
}

function LinesEditor({ group, rows, onChange }: { group: Group; rows: Row[]; onChange: (rows: Row[]) => void }) {
  const setCell = (i: number, key: string, v: string) => onChange(rows.map((r, j) => (j === i ? { ...r, cells: { ...r.cells, [key]: v } } : r)))
  const blank = (): Row => ({ raw: {}, cells: Object.fromEntries(group.cols.map((c) => [c.key, c.kind === 'bool' ? 'false' : ''])) })
  return (
    <div className="overflow-x-auto">
      {group.title && <h3 className="mb-1 text-sm font-semibold">{group.title}</h3>}
      <table className="w-full text-sm">
        <caption className="sr-only">{group.title ?? 'Lignes du barème'}</caption>
        <thead>
          <tr className="table-head">
            {group.cols.map((c) => <th key={c.key} scope="col" className="px-1.5 py-1 text-left">{c.label}{c.kind === 'rate' ? ' (%)' : ''}</th>)}
            {!group.fixedRows && <th scope="col" className="px-1.5 py-1"><span className="sr-only">Supprimer</span></th>}
          </tr>
        </thead>
        <tbody>
          {rows.map((r, i) => (
            <tr key={i} className="border-b border-line/70">
              {group.cols.map((c) => <td key={c.key} className="px-1.5 py-1"><Cell col={c} value={r.cells[c.key] ?? ''} line={i + 1} onChange={(v) => setCell(i, c.key, v)} /></td>)}
              {!group.fixedRows && (
                <td className="px-1.5 py-1 text-right">
                  <Button size="sm" variant="ghost" aria-label={`Supprimer la ligne ${i + 1}`} onClick={() => onChange(rows.filter((_, j) => j !== i))}><Trash2 className="h-3.5 w-3.5" aria-hidden /></Button>
                </td>
              )}
            </tr>
          ))}
        </tbody>
      </table>
      {!group.fixedRows && <Button size="sm" className="mt-2" icon={<Plus className="h-3.5 w-3.5" aria-hidden />} onClick={() => onChange([...rows, blank()])}>Ajouter une ligne</Button>}
    </div>
  )
}

function Cell({ col, value, line, onChange }: { col: Col; value: string; line: number; onChange: (v: string) => void }) {
  const label = `${col.label}, ligne ${line}`
  if (col.readOnly) return <span className="num text-ink-soft">{col.kind === 'rate' && value !== '' ? `${value} %` : value}</span>
  if (col.kind === 'bool') return <input type="checkbox" checked={value === 'true'} aria-label={label} onChange={(e) => onChange(e.target.checked ? 'true' : 'false')} />
  return <input className="field num min-w-24" inputMode={col.kind === 'text' ? 'text' : 'decimal'} value={value} aria-label={label} onChange={(e) => onChange(e.target.value)} />
}

/* -------------------------------------------------------------------- réinitialisation */
function ScaleReset({ scale, floor, isAdmin, onClose, onDone }: {
  scale: ScaleRow; floor: string | null; isAdmin: boolean; onClose: () => void; onDone: (m: string) => void
}) {
  const [month, setMonth] = useState(dateToMonth(floor) || new Date().toISOString().slice(0, 7))
  const save = useMutation({
    mutationFn: async () => unwrap(await dataApi.rpc('request_scale_reset', { p_code: scale.code, p_effective_from: monthToDate(month) as string })),
    onSuccess: () => onDone(doneMessage(isAdmin, 'Réinitialisation du barème')),
  })
  return (
    <Modal open title={`Réinitialiser : ${scale.label}`} onClose={onClose}
      footer={<><Button onClick={onClose}>Annuler</Button><Button variant="primary" loading={save.isPending} disabled={!monthToDate(month)} onClick={() => save.mutate()}>{isAdmin ? 'Réinitialiser' : 'Envoyer pour validation'}</Button></>}>
      <div className="space-y-3">
        <p className="text-sm text-ink-soft">
          Le jeu d’origine du barème redevient celui en vigueur à la date choisie, ainsi que sur les versions futures encore modifiables.
          Les dérogations accordées au titre de ce barème sont levées.
        </p>
        <EffectDateField floor={floor} value={month} onChange={setMonth} />
        <ErrorNote error={save.error} />
      </div>
    </Modal>
  )
}
