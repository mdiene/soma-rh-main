import clsx from 'clsx'
import { AlertTriangle, ArrowDown, ArrowUp, CheckCircle2, Download, Maximize2, Minimize2, Printer, Search } from 'lucide-react'
import { Fragment, useMemo, useState, type ReactNode } from 'react'
import { fcfa, num, pct } from '../lib/format'
import { Button } from './ui'

/**
 * Tableau d'état à colonnes groupées par blocs fonctionnels :
 * - deux lignes d'en-tête figées au défilement vertical (bloc, puis colonne) ;
 * - colonnes d'identification figées au défilement horizontal ;
 * - sous-totaux par regroupement facultatif et total général figé en bas ;
 * - recherche, tri, export CSV (pleine précision) et impression.
 * Les montants restent en pleine précision ; seul l'affichage est arrondi.
 */

export type Tone = 'neutral' | 'river' | 'signal' | 'inkSoft' | 'ink' | 'phosphate' | 'phosphateSoft' | 'riverDark'
export type Kind = 'text' | 'money' | 'int' | 'rate' | 'number'

export type GCol<T> = {
  id: string
  header: string
  value: (row: T) => string | number | null | undefined
  kind?: Kind
  /** Somme dans les sous-totaux et le total (défaut : oui pour money/int/number). */
  sum?: boolean
  /** Colonne figée à gauche (largeur fixe en pixels). */
  stickyWidth?: number
  title?: string
}
export type GBlock<T> = { id: string; label: string; tone: Tone; columns: GCol<T>[] }
export type Check = { label: string; ok: boolean; detail?: string }

const TONES: Record<Tone, { band: string; head: string; total: string; edge: string }> = {
  neutral:       { band: 'bg-paper text-ink',     head: 'bg-paper',           total: 'bg-paper',           edge: 'border-l-line' },
  river:         { band: 'bg-river text-white',       head: 'bg-river-light',     total: 'bg-river-light',     edge: 'border-l-river' },
  signal:        { band: 'bg-signal text-white',      head: 'bg-signal-light',    total: 'bg-signal-light',    edge: 'border-l-signal' },
  inkSoft:       { band: 'bg-ink-soft text-white',    head: 'bg-paper',       total: 'bg-paper',       edge: 'border-l-ink-soft' },
  ink:           { band: 'bg-ink text-white',         head: 'bg-paper',       total: 'bg-paper',       edge: 'border-l-ink' },
  phosphate:     { band: 'bg-phosphate text-ink',     head: 'bg-phosphate-light', total: 'bg-phosphate-light', edge: 'border-l-phosphate' },
  phosphateSoft: { band: 'bg-phosphate text-ink',     head: 'bg-phosphate-light',       total: 'bg-phosphate-light',       edge: 'border-l-phosphate' },
  riverDark:     { band: 'bg-river-dark text-white',  head: 'bg-river-light',     total: 'bg-river-light',     edge: 'border-l-river-dark' },
}

const isNumeric = (k?: Kind) => k === 'money' || k === 'int' || k === 'number' || k === 'rate'
const summable = <T,>(c: GCol<T>) => c.sum ?? (c.kind === 'money' || c.kind === 'int' || c.kind === 'number')

function display(v: unknown, kind?: Kind): string {
  if (v === null || v === undefined || v === '') return ''
  switch (kind) {
    case 'money': return fcfa(v as number)
    case 'int': return String(Math.round(Number(v)))
    case 'rate': return pct(v as number)
    case 'number': return num(v as number)
    default: return String(v)
  }
}

/** Colonnes maximum par page imprimée (A4 paysage, corps 9,5 px). */
const PRINT_MAX_COLS = 13

/** Découpe les blocs en bandes imprimables ; le premier bloc (identification) est répété. */
function printBands<T>(blocks: GBlock<T>[]): GBlock<T>[][] {
  const [head, ...rest] = blocks
  if (!head) return []
  const bands: GBlock<T>[][] = []
  let cur: GBlock<T>[] = [head]
  let n = head.columns.length
  for (const b of rest) {
    if (cur.length > 1 && n + b.columns.length > PRINT_MAX_COLS) {
      bands.push(cur)
      cur = [head]
      n = head.columns.length
    }
    cur.push(b)
    n += b.columns.length
  }
  bands.push(cur)
  return bands
}

type Props<T> = {
  rows: T[]
  blocks: GBlock<T>[]
  rowKey: (row: T) => string
  /** Regroupement facultatif : une ligne de sous-total par groupe. */
  groupBy?: { key: (row: T) => string; label: (row: T) => string }
  exportName?: string
  searchPlaceholder?: string
  /** Bandeau d'information au-dessus du tableau. */
  notice?: ReactNode
  /** Contrôles de cohérence affichés en tête. */
  checks?: Check[]
  toolbar?: ReactNode
  onRowClick?: (row: T) => void
  totalLabel?: string
}

export function GroupedTable<T>({
  rows, blocks, rowKey, groupBy, exportName, searchPlaceholder = 'Rechercher un salarié, un matricule…',
  notice, checks, toolbar, onRowClick, totalLabel = 'Total',
}: Props<T>) {
  const [query, setQuery] = useState('')
  const [sort, setSort] = useState<{ id: string; desc: boolean } | null>(null)
  const [wide, setWide] = useState(false)

  const cols = useMemo(() => blocks.flatMap((b) => b.columns.map((c, i) => ({ ...c, block: b, first: i === 0 }))), [blocks])

  const visible = useMemo(() => {
    const q = query.trim().toLowerCase()
    let out = q
      ? rows.filter((r) => cols.some((c) => !isNumeric(c.kind) && String(c.value(r) ?? '').toLowerCase().includes(q)))
      : rows.slice()
    if (sort) {
      const c = cols.find((x) => x.id === sort.id)
      if (c) {
        out = out.sort((a, b) => {
          const va = c.value(a), vb = c.value(b)
          const d = isNumeric(c.kind) ? Number(va ?? 0) - Number(vb ?? 0) : String(va ?? '').localeCompare(String(vb ?? ''), 'fr')
          return sort.desc ? -d : d
        })
      }
    }
    // tri stable : le regroupement garde l'ordre choisi à l'intérieur de chaque groupe
    if (groupBy) out = out.sort((a, b) => groupBy.key(a).localeCompare(groupBy.key(b), 'fr'))
    return out
  }, [rows, cols, query, sort, groupBy])

  const groups = useMemo(() => {
    if (!groupBy) return [{ key: '_all', label: '', rows: visible }]
    const m = new Map<string, { key: string; label: string; rows: T[] }>()
    for (const r of visible) {
      const k = groupBy.key(r)
      if (!m.has(k)) m.set(k, { key: k, label: groupBy.label(r), rows: [] })
      m.get(k)!.rows.push(r)
    }
    return [...m.values()]
  }, [visible, groupBy])

  const total = (list: T[], c: GCol<T>) => list.reduce((s, r) => s + Number(c.value(r) ?? 0), 0)
  const bands = useMemo(() => printBands(blocks), [blocks])

  function toggleSort(id: string) {
    setSort((s) => (s?.id !== id ? { id, desc: false } : s.desc ? null : { id, desc: true }))
  }

  function exportCsv() {
    const head = cols.map((c) => JSON.stringify(`${c.block.label} — ${c.header}`))
    const cell = (v: unknown, kind?: Kind) =>
      v === null || v === undefined ? '""' : isNumeric(kind) ? String(v).replace('.', ',') : JSON.stringify(String(v))
    const lines = visible.map((r) => cols.map((c) => cell(c.value(r), c.kind)).join(';'))
    const tot = cols.map((c, i) => (i === 0 ? JSON.stringify(totalLabel) : summable(c) ? cell(total(visible, c), c.kind) : '""')).join(';')
    const blob = new Blob(['﻿' + [head.join(';'), ...lines, tot].join('\r\n')], { type: 'text/csv;charset=utf-8' })
    const a = document.createElement('a')
    a.href = URL.createObjectURL(blob)
    a.download = `${exportName ?? 'etat'}.csv`
    a.click()
    URL.revokeObjectURL(a.href)
  }

  /** Rendu d'un tableau pour un jeu de blocs (écran : tous les blocs ; impression : une bande). */
  function renderTable(tb: GBlock<T>[], band = false) {
    const tc = tb.flatMap((b) => b.columns.map((c, i) => ({ ...c, block: b, first: i === 0 })))
    const left = new Map<string, number>()
    let x = 0
    let lastSticky: string | undefined
    for (const c of tc) if (c.stickyWidth) { left.set(c.id, x); x += c.stickyWidth; lastSticky = c.id }
    const stickyTotal = x
    type C = (typeof tc)[number]
    const cellCls = (c: C) => clsx(
      'whitespace-nowrap px-2 py-1.5',
      isNumeric(c.kind) && 'text-right',
      c.first && 'border-l-2', c.first && TONES[c.block.tone].edge,
      c.id === lastSticky && 'shadow-[2px_0_0_0_#DCE1DE]',
    )
    const stickyStyle = (c: C) =>
      c.stickyWidth ? { left: left.get(c.id), minWidth: c.stickyWidth, maxWidth: c.stickyWidth, width: c.stickyWidth } : undefined
    return (
          <table className={clsx('grouped-table min-w-full', !band && 'w-max', band && 'w-full')} data-band={band ? 'oui' : undefined} style={{ borderCollapse: 'separate', borderSpacing: 0 }}>
            <thead>
              <tr>
                {tb.map((b) => {
                  const stickyW = b.columns.reduce((s, c) => s + (c.stickyWidth ?? 0), 0)
                  const nSticky = b.columns.filter((c) => c.stickyWidth).length
                  const rest = b.columns.length - nSticky
                  const band = 'h-8 border-b border-white/40 px-2 text-left text-[11px] font-semibold uppercase tracking-wider'
                  return (
                    <Fragment key={b.id}>
                      {nSticky > 0 && (
                        <th colSpan={nSticky} scope="colgroup"
                          className={clsx(band, 'sticky left-0 top-0 z-40 border-l-2', TONES[b.tone].band, TONES[b.tone].edge)}
                          style={{ minWidth: stickyW, maxWidth: stickyW, width: stickyW }}>
                          {b.label}
                        </th>
                      )}
                      {rest > 0 && (
                        <th colSpan={rest} scope="colgroup"
                          className={clsx(band, 'sticky top-0 z-20', nSticky === 0 && 'border-l-2', TONES[b.tone].band, TONES[b.tone].edge)}>
                          {/* libellé du bloc maintenu visible lors du défilement horizontal */}
                          {nSticky > 0 ? '' : <span className="sticky" style={{ left: stickyTotal + 8 }}>{b.label}</span>}
                        </th>
                      )}
                    </Fragment>
                  )
                })}
              </tr>
              <tr>
                {tc.map((c) => (
                  <th key={c.id} scope="col" title={c.title} aria-sort={sort?.id === c.id ? (sort.desc ? 'descending' : 'ascending') : undefined}
                    className={clsx(cellCls(c), 'sticky top-8 border-b border-line text-xs font-semibold text-ink-soft', !isNumeric(c.kind) && 'text-left', c.stickyWidth ? 'z-40' : 'z-20', TONES[c.block.tone].head)}
                    style={stickyStyle(c)}>
                    <button type="button" onClick={() => toggleSort(c.id)}
                      className={clsx('inline-flex items-center gap-1 hover:text-ink', isNumeric(c.kind) && 'flex-row-reverse')}>
                      {c.header}
                      {sort?.id === c.id && (sort.desc ? <ArrowDown className="h-3 w-3" /> : <ArrowUp className="h-3 w-3" />)}
                    </button>
                  </th>
                ))}
              </tr>
            </thead>
            <tbody>
              {groups.map((g) => (
                <Fragment key={g.key}>
                  {groupBy && (
                    <tr>
                      <td colSpan={tc.length} className="border-b border-line bg-paper px-2 py-1.5 text-xs font-semibold uppercase tracking-wide text-ink-soft">
                        <span className="sticky left-2">{g.label} · {g.rows.length}</span>
                      </td>
                    </tr>
                  )}
                  {g.rows.map((r) => (
                    <tr key={rowKey(r)} onClick={onRowClick ? () => onRowClick(r) : undefined} className={clsx('group', onRowClick && 'cursor-pointer')}>
                      {tc.map((c) => (
                        <td key={c.id} style={stickyStyle(c)}
                          className={clsx(cellCls(c), 'border-b border-line/70 bg-white group-hover:bg-river-light', c.stickyWidth && 'sticky z-10', c.id === 'employee_number' && 'font-medium')}>
                          {c.stickyWidth
                            ? <span className="block truncate" title={String(c.value(r) ?? '')}>{display(c.value(r), c.kind)}</span>
                            : display(c.value(r), c.kind)}
                        </td>
                      ))}
                    </tr>
                  ))}
                  {groupBy && (
                    <tr className="font-semibold">
                      {tc.map((c, i) => (
                        <td key={c.id} style={stickyStyle(c)} className={clsx(cellCls(c), 'border-b border-line', c.stickyWidth && 'sticky z-10', TONES[c.block.tone].total)}>
                          {i === 0 ? 'Sous-total' : summable(c) ? display(total(g.rows, c), c.kind) : ''}
                        </td>
                      ))}
                    </tr>
                  )}
                </Fragment>
              ))}
              {visible.length === 0 && (
                <tr><td colSpan={tc.length} className="px-3 py-6 text-center text-sm text-ink-muted">Aucune ligne ne correspond à la recherche.</td></tr>
              )}
            </tbody>
            <tfoot>
              <tr className="font-bold">
                {tc.map((c, i) => (
                  <td key={c.id} style={stickyStyle(c)}
                    className={clsx(cellCls(c), 'sticky bottom-0 border-t-2 border-t-ink/30 print:static', c.stickyWidth ? 'z-30' : 'z-20', TONES[c.block.tone].total)}>
                    {i === 0 ? totalLabel : summable(c) ? display(total(visible, c), c.kind) : ''}
                  </td>
                ))}
              </tr>
            </tfoot>
          </table>
    )
  }

  return (
    <div className={clsx('panel overflow-hidden', wide && 'fixed inset-2 z-40 flex flex-col shadow-2xl print:static print:shadow-none')}>
      <div className="no-print flex flex-wrap items-center gap-2 border-b border-line px-3 py-2">
        <label className="relative min-w-[12rem] max-w-sm flex-1">
          <span className="sr-only">{searchPlaceholder}</span>
          <Search className="pointer-events-none absolute left-2.5 top-2.5 h-4 w-4 text-ink-muted" aria-hidden />
          <input type="search" value={query} onChange={(e) => setQuery(e.target.value)} placeholder={searchPlaceholder} className="field pl-8" />
        </label>
        <span className="text-xs text-ink-muted">{visible.length} ligne(s)</span>
        <div className="ml-auto flex items-center gap-2">
          {toolbar}
          <Button size="sm" icon={wide ? <Minimize2 className="h-3.5 w-3.5" /> : <Maximize2 className="h-3.5 w-3.5" />} onClick={() => setWide((w) => !w)}>
            {wide ? 'Réduire' : 'Plein écran'}
          </Button>
          <Button size="sm" icon={<Printer className="h-3.5 w-3.5" />} onClick={() => window.print()}>Imprimer</Button>
          {exportName && <Button size="sm" icon={<Download className="h-3.5 w-3.5" />} onClick={exportCsv}>Exporter CSV</Button>}
        </div>
      </div>

      {(notice || (checks && checks.length > 0)) && (
        <div className="space-y-2 border-b border-line px-3 py-2 text-sm">
          {notice}
          {checks && checks.length > 0 && (
            <ul className="flex flex-wrap gap-x-4 gap-y-1 text-xs" aria-label="Contrôles de cohérence">
              {checks.map((c) => (
                <li key={c.label} className={clsx('inline-flex items-center gap-1', c.ok ? 'text-river' : 'font-semibold text-signal')} title={c.detail}>
                  {c.ok ? <CheckCircle2 className="h-3.5 w-3.5" aria-hidden /> : <AlertTriangle className="h-3.5 w-3.5" aria-hidden />}
                  {c.label}{!c.ok && c.detail ? ` — ${c.detail}` : ''}
                </li>
              ))}
            </ul>
          )}
        </div>
      )}

      <div className={clsx('overflow-auto print:max-h-none print:overflow-visible', wide ? 'flex-1' : 'max-h-[calc(100vh-17rem)] min-h-[16rem]')}>
          <div className={clsx(bands.length > 1 && 'print:hidden')}>{renderTable(blocks)}</div>
          {/* impression : le tableau large est découpé en bandes de colonnes, l'identification est répétée */}
          {bands.length > 1 && bands.map((b, i) => (
            <div key={i} className={clsx('hidden print:block', i > 0 && 'print:break-before-page')}>
              <p className="mb-1 text-[9px] text-ink-muted">Partie {i + 1} / {bands.length} — {b.slice(1).map((x) => x.label).join(', ')}</p>
              {renderTable(b, true)}
            </div>
          ))}
      </div>
    </div>
  )
}
