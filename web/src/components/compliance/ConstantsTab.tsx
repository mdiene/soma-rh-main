import { useMutation, useQuery } from '@tanstack/react-query'
import { ChevronDown, ChevronRight, RotateCcw } from 'lucide-react'
import { Fragment, useMemo, useState } from 'react'
import { dataApi, unwrap } from '../../lib/api'
import { useAuth } from '../../lib/auth'
import { checkValue, dateToMonth, effectLabel, formatValue, fromInput, monthToDate, toInput, type Unit } from '../../lib/compliance'
import { Badge, Button, ErrorNote, Modal, SelectField, Section, Spinner, TextField } from '../ui'
import { ScalesPanel } from './ScalesPanel'
import { STATUS_LABEL, doneMessage, useRefreshCompliance, type LegalSource } from './shared'

export type ParamRow = {
  code: string; domain: string; label: string; unit: string; sort: number
  current_value: number | null; default_value: number; is_modified: boolean; effective_from: string | null
  min_value: number | null; max_value: number | null
  source_code: string | null; source_label: string | null; source_document: string | null; source_article: string | null
  source_status: string | null; legal_text: string | null
}
export function EffectDateField({ floor, value, onChange }: { floor: string | null; value: string; onChange: (v: string) => void }) {
  return (
    <TextField label="Applicable à partir de" type="month" value={value} min={dateToMonth(floor) || undefined}
      onChange={(e) => onChange(e.target.value)}
      hint={floor ? `Des paies sont déjà calculées : premier mois possible ${effectLabel(floor)}.` : 'Aucune paie calculée : tout mois est possible.'} />
  )
}

export function ConstantsTab({ onNotice }: { onNotice: (m: string) => void }) {
  const { roles } = useAuth()
  const isAdmin = roles.includes('admin')
  const refresh = useRefreshCompliance()
  const overview = useQuery({ queryKey: ['param_overview'], queryFn: async () => unwrap(await dataApi.rpc('parameter_overview')) as ParamRow[] })
  const floor = useQuery({ queryKey: ['param_floor'], queryFn: async () => (unwrap(await dataApi.rpc('parameters_min_effective_date')) ?? null) as string | null })
  const pending = useQuery({
    queryKey: ['approval_requests', 'pending'],
    queryFn: async () => unwrap(await dataApi.rpc('approval_requests_overview', { p_status: 'en_attente' })),
  })
  const sources = useQuery({
    queryKey: ['legal_sources'], enabled: isAdmin,
    queryFn: async () => unwrap(await dataApi.from('legal_sources').select('code, label, article, status').order('code')) as LegalSource[],
  })
  const [open, setOpen] = useState<string | null>(null)
  const [edit, setEdit] = useState<ParamRow | null>(null)
  const [reset, setReset] = useState<ParamRow | null>(null)
  const [ref, setRef] = useState<ParamRow | null>(null)

  const pendingCodes = useMemo(() => new Set((pending.data ?? []).filter((p) => p.kind === 'constante').map((p) => p.target)), [pending.data])
  const byDomain = useMemo(() => {
    const m = new Map<string, ParamRow[]>()
    for (const r of overview.data ?? []) m.set(r.domain, [...(m.get(r.domain) ?? []), r])
    return [...m.entries()]
  }, [overview.data])
  const floorDate = floor.data ?? null

  if (overview.isLoading) return <Spinner />
  return (
    <div className="space-y-6">
      <p className="rounded border border-river/30 bg-river-light px-3 py-2 text-sm text-ink">
        Les modifications s’appliqueront uniquement aux paies non encore calculées.
        {floorDate && <> Des paies sont déjà calculées : une nouvelle valeur prend effet au plus tôt le {effectLabel(floorDate)}.</>}
        {' '}{isAdmin ? 'Vos modifications sont appliquées immédiatement.' : 'Vos modifications sont envoyées à l’administrateur, qui les valide.'}
      </p>
      <ErrorNote error={overview.error || floor.error} />

      {byDomain.map(([domain, rows]) => (
        <Section key={domain} title={domain}>
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <caption className="sr-only">Constantes : {domain}</caption>
              <thead>
                <tr className="table-head">
                  <th scope="col" className="px-2 py-1.5 text-left">Constante</th>
                  <th scope="col" className="px-2 py-1.5 text-right">Valeur active</th>
                  <th scope="col" className="px-2 py-1.5 text-right">Valeur d’origine</th>
                  <th scope="col" className="px-2 py-1.5 text-left">En vigueur depuis</th>
                  <th scope="col" className="px-2 py-1.5 text-left">Source</th>
                  <th scope="col" className="px-2 py-1.5 text-right">Actions</th>
                </tr>
              </thead>
              <tbody>
                {rows.map((r) => {
                  const isOpen = open === r.code
                  return (
                    <Fragment key={r.code}>
                      <tr className="border-b border-line/70 align-top">
                        <td className="px-2 py-1.5">
                          <button type="button" className="flex items-start gap-1 text-left hover:text-river" aria-expanded={isOpen}
                            aria-controls={`detail-${r.code}`} onClick={() => setOpen(isOpen ? null : r.code)}>
                            {isOpen ? <ChevronDown className="mt-0.5 h-4 w-4 shrink-0" aria-hidden /> : <ChevronRight className="mt-0.5 h-4 w-4 shrink-0" aria-hidden />}
                            <span>{r.label}</span>
                          </button>
                          <span className="ml-5 mt-0.5 flex flex-wrap gap-1">
                            {r.is_modified && <Badge value="Modifiée" />}
                            {pendingCodes.has(r.code) && <Badge value="En attente" label="Demande en attente" />}
                          </span>
                        </td>
                        <td className="num px-2 py-1.5 text-right font-medium">{formatValue(r.current_value, r.unit)}</td>
                        <td className="num px-2 py-1.5 text-right text-ink-soft">{formatValue(r.default_value, r.unit)}</td>
                        <td className="px-2 py-1.5">{r.effective_from ? effectLabel(r.effective_from) : 'Immédiat'}</td>
                        <td className="px-2 py-1.5 text-xs">
                          {r.source_code
                            ? <span className={r.source_status === 'confirme' ? 'text-river-dark' : 'text-ink-soft'}>{STATUS_LABEL[r.source_status ?? ''] ?? r.source_status}</span>
                            : <span className="text-ink-muted">À fournir</span>}
                        </td>
                        <td className="px-2 py-1.5 text-right">
                          <span className="inline-flex flex-wrap justify-end gap-1.5">
                            <Button size="sm" onClick={() => setEdit(r)} aria-label={`Modifier ${r.label}`}>Modifier</Button>
                            <Button size="sm" icon={<RotateCcw className="h-3.5 w-3.5" aria-hidden />} disabled={!r.is_modified}
                              onClick={() => setReset(r)} aria-label={`Réinitialiser ${r.label} à la valeur d’origine`}>Réinitialiser</Button>
                          </span>
                        </td>
                      </tr>
                      {isOpen && (
                        <tr id={`detail-${r.code}`} className="border-b border-line/70 bg-paper/60">
                          <td colSpan={6} className="px-4 py-3 text-sm">
                            <p className="font-medium text-ink">Ce que prévoit la loi</p>
                            <p className="mt-1 max-w-prose text-ink-soft">{r.legal_text ?? 'Texte à fournir.'}</p>
                            <p className="mt-2 text-xs text-ink-muted">
                              {r.source_code
                                ? <>Référence : {r.source_label}{r.source_document ? ` — ${r.source_document}` : ''}{r.source_article ? `, art. ${r.source_article}` : ''} ({STATUS_LABEL[r.source_status ?? ''] ?? r.source_status}).</>
                                : 'Aucune référence juridique renseignée.'}
                              {' '}Bornes autorisées : {r.min_value !== null ? formatValue(r.min_value, r.unit) : 'aucune'} à {r.max_value !== null ? formatValue(r.max_value, r.unit) : 'aucune'}.
                            </p>
                            {isAdmin && <Button size="sm" className="mt-2" onClick={() => setRef(r)}>Régler la référence légale</Button>}
                          </td>
                        </tr>
                      )}
                    </Fragment>
                  )
                })}
              </tbody>
            </table>
          </div>
        </Section>
      ))}

      <ScalesPanel floor={floorDate} onNotice={onNotice} refresh={refresh} sources={sources.data ?? []} />

      {edit && <EditModal row={edit} floor={floorDate} isAdmin={isAdmin} onClose={() => setEdit(null)} onDone={(m) => { setEdit(null); refresh(); onNotice(m) }} />}
      {reset && <ResetModal row={reset} floor={floorDate} isAdmin={isAdmin} onClose={() => setReset(null)} onDone={(m) => { setReset(null); refresh(); onNotice(m) }} />}
      {ref && <ReferenceModal row={ref} sources={sources.data ?? []} onClose={() => setRef(null)} onDone={() => { setRef(null); refresh(); onNotice('Référence légale enregistrée.') }} />}
    </div>
  )
}

function EditModal({ row, floor, isAdmin, onClose, onDone }: { row: ParamRow; floor: string | null; isAdmin: boolean; onClose: () => void; onDone: (m: string) => void }) {
  const kind = row.unit === 'taux' ? 'taux' : 'plain'
  const dated = row.effective_from !== null
  const [value, setValue] = useState(toInput(row.current_value, kind))
  const [month, setMonth] = useState(dateToMonth(floor) || new Date().toISOString().slice(0, 7))
  const parsed = fromInput(value, kind)
  const problem = value.trim() === '' ? null : checkValue(parsed, row)
  const save = useMutation({
    mutationFn: async () => unwrap(await dataApi.rpc('request_parameter_change', { p_code: row.code, p_value: parsed as number, p_effective_from: dated ? monthToDate(month) : undefined })),
    onSuccess: () => onDone(doneMessage(isAdmin, 'Modification')),
  })
  const unit = row.unit as Unit
  return (
    <Modal open title={`Modifier : ${row.label}`} onClose={onClose}
      footer={<>
        <Button onClick={onClose}>Annuler</Button>
        <Button variant="primary" loading={save.isPending} disabled={parsed === null || Number.isNaN(parsed) || problem !== null || (dated && !monthToDate(month))} onClick={() => save.mutate()}>
          {isAdmin ? 'Appliquer' : 'Envoyer pour validation'}
        </Button>
      </>}>
      <div className="space-y-3">
        <p className="text-sm text-ink-soft">Valeur active : <strong>{formatValue(row.current_value, row.unit)}</strong> — valeur d’origine : {formatValue(row.default_value, row.unit)}.</p>
        <TextField label={`Nouvelle valeur${unit === 'taux' ? ' (en %)' : unit === 'FCFA' ? ' (en francs)' : ''}`} inputMode="decimal" value={value}
          onChange={(e) => setValue(e.target.value)} aria-invalid={problem !== null} autoFocus
          hint={problem ?? (row.min_value !== null || row.max_value !== null ? `Entre ${row.min_value !== null ? formatValue(row.min_value, row.unit) : 'aucune borne'} et ${row.max_value !== null ? formatValue(row.max_value, row.unit) : 'aucune borne'}.` : undefined)} />
        {dated
          ? <EffectDateField floor={floor} value={month} onChange={setMonth} />
          : <p className="text-xs text-ink-muted">Cette constante n’est pas datée : elle s’applique dès l’enregistrement aux nouveaux calculs.</p>}
        <ErrorNote error={save.error} />
      </div>
    </Modal>
  )
}

function ResetModal({ row, floor, isAdmin, onClose, onDone }: { row: ParamRow; floor: string | null; isAdmin: boolean; onClose: () => void; onDone: (m: string) => void }) {
  const dated = row.effective_from !== null
  const [month, setMonth] = useState(dateToMonth(floor) || new Date().toISOString().slice(0, 7))
  const save = useMutation({
    mutationFn: async () => unwrap(await dataApi.rpc('request_parameter_reset', { p_code: row.code, p_effective_from: dated ? monthToDate(month) : undefined })),
    onSuccess: () => onDone(doneMessage(isAdmin, 'Réinitialisation')),
  })
  return (
    <Modal open title={`Réinitialiser : ${row.label}`} onClose={onClose}
      footer={<>
        <Button onClick={onClose}>Annuler</Button>
        <Button variant="primary" loading={save.isPending} disabled={dated && !monthToDate(month)} onClick={() => save.mutate()}>
          {isAdmin ? 'Réinitialiser' : 'Envoyer pour validation'}
        </Button>
      </>}>
      <div className="space-y-3">
        <p className="text-sm text-ink-soft">
          La valeur <strong>{formatValue(row.current_value, row.unit)}</strong> est remplacée par la valeur d’origine <strong>{formatValue(row.default_value, row.unit)}</strong>.
          Les dérogations accordées au titre de cette constante sont levées.
        </p>
        {dated && <EffectDateField floor={floor} value={month} onChange={setMonth} />}
        <ErrorNote error={save.error} />
      </div>
    </Modal>
  )
}

export function ReferenceModal({ row, sources, onClose, onDone, scale }: {
  row: { code: string; label: string; legal_text: string | null; source_code: string | null }
  sources: LegalSource[]; onClose: () => void; onDone: () => void; scale?: boolean
}) {
  const [text, setText] = useState(row.legal_text ?? '')
  const [source, setSource] = useState(row.source_code ?? '')
  const save = useMutation({
    mutationFn: async () => scale
      ? unwrap(await dataApi.rpc('set_scale_reference', { p_code: row.code, p_legal_text: text, p_source_code: source || undefined }))
      : unwrap(await dataApi.rpc('set_parameter_reference', { p_code: row.code, p_legal_text: text, p_source_code: source || undefined })),
    onSuccess: onDone,
  })
  return (
    <Modal open title={`Référence légale : ${row.label}`} onClose={onClose}
      footer={<><Button onClick={onClose}>Annuler</Button><Button variant="primary" loading={save.isPending} onClick={() => save.mutate()}>Enregistrer</Button></>}>
      <div className="space-y-3">
        <label className="block">
          <span className="label">Ce que prévoit la loi</span>
          <textarea className="field min-h-28" value={text} onChange={(e) => setText(e.target.value)} />
        </label>
        <SelectField label="Source juridique" value={source} onChange={(e) => setSource(e.target.value)}>
          <option value="">Aucune (à fournir)</option>
          {sources.map((s) => <option key={s.code} value={s.code}>{s.label}{s.article ? ` (art. ${s.article})` : ''} — {STATUS_LABEL[s.status] ?? s.status}</option>)}
        </SelectField>
        <ErrorNote error={save.error} />
      </div>
    </Modal>
  )
}
