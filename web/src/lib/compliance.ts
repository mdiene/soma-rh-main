import { date, fcfa, num, pct } from './format'

/* ------------------------------------------------------------------------- constantes
   Les taux sont stockés en fraction (0,07) et affichés / saisis en pourcentage (7). */
export type Unit = 'FCFA' | 'taux' | 'h' | 'nb' | 'mois' | 'ans'

export const UNIT_SUFFIX: Record<Unit, string> = { FCFA: 'F', taux: '%', h: 'h', nb: '', mois: 'mois', ans: 'ans' }

export function formatValue(v: number | null | undefined, unit: string): string {
  if (v === null || v === undefined) return '—'
  if (unit === 'taux') return pct(v)
  if (unit === 'FCFA') return `${fcfa(v)} F`
  const s = num(v, 4)
  const suffix = UNIT_SUFFIX[unit as Unit]
  return suffix ? `${s} ${suffix}` : s
}

const round10 = (n: number) => Number(n.toFixed(10))

/** Valeur stockée -> texte de saisie (taux en pourcentage). */
export function toInput(v: number | null | undefined, kind: 'taux' | 'plain' = 'plain'): string {
  if (v === null || v === undefined) return ''
  return String(kind === 'taux' ? round10(v * 100) : v)
}

/** Texte de saisie -> valeur stockée ; null si vide ; NaN si illisible. */
export function fromInput(s: string, kind: 'taux' | 'plain' = 'plain'): number | null {
  const t = s.trim().replace(/\s/g, '').replace(',', '.')
  if (t === '') return null
  if (!/^-?\d+(\.\d+)?$/.test(t)) return Number.NaN
  const n = Number(t)
  return kind === 'taux' ? round10(n / 100) : n
}

/** Contrôle de saisie d'une constante ; renvoie un message ou null. */
export function checkValue(v: number | null, c: { label: string; unit: string; min_value: number | null; max_value: number | null }): string | null {
  if (v === null || Number.isNaN(v)) return 'Saisissez un nombre.'
  if (c.min_value !== null && v < c.min_value) return `La valeur doit être au moins ${formatValue(c.min_value, c.unit)}.`
  if (c.max_value !== null && v > c.max_value) return `La valeur ne peut dépasser ${formatValue(c.max_value, c.unit)}.`
  return null
}

/** Premier jour du mois d'une saisie <input type="month"> (AAAA-MM). */
export const monthToDate = (ym: string): string | undefined => (/^\d{4}-\d{2}$/.test(ym) ? `${ym}-01` : undefined)
export const dateToMonth = (d: string | null | undefined): string => (d ? d.slice(0, 7) : '')

/** Libellé d'une date d'effet (ex. « 01/01/2027 »). */
export const effectLabel = (d: string | null | undefined) => (d ? date(d) : '—')

/* ------------------------------------------------------------------ barèmes (jeux de lignes) */
export type ColKind = 'money' | 'rate' | 'number' | 'text' | 'bool'
export type Col = { key: string; label: string; kind: ColKind; readOnly?: boolean; nullable?: boolean }
export type Group = { key: string | null; title?: string; cols: Col[]; fixedRows?: boolean }

export const SCALE_GROUPS: Record<string, Group[]> = {
  HS: [{ key: null, fixedRows: true, cols: [
    { key: 'label', label: 'Majoration', kind: 'text', readOnly: true },
    { key: 'rate_uplift', label: 'Majoration appliquée', kind: 'rate' },
    { key: 'legal_min_uplift', label: 'Minimum légal', kind: 'rate', readOnly: true },
  ] }],
  PREAVIS: [{ key: null, cols: [
    { key: 'agreement_code', label: 'Convention (vide = toutes)', kind: 'text', nullable: true },
    { key: 'category', label: 'Catégorie', kind: 'text' },
    { key: 'notice_months', label: 'Préavis (mois)', kind: 'number' },
    { key: 'free_days_week', label: 'Jours libres par semaine', kind: 'number', nullable: true },
  ] }],
  QUOTITE_PRINCIPAL: [{ key: null, cols: [
    { key: 'lower_bound', label: 'De (F)', kind: 'money' },
    { key: 'upper_bound', label: 'À (F, vide = sans limite)', kind: 'money', nullable: true },
    { key: 'rate', label: 'Part saisissable', kind: 'rate' },
  ] }],
  LICENCIEMENT: [{ key: null, cols: [
    { key: 'year_from', label: 'Ancienneté de (ans)', kind: 'number' },
    { key: 'year_to', label: 'à (ans, vide = sans limite)', kind: 'number', nullable: true },
    { key: 'rate', label: 'Taux par année', kind: 'rate' },
  ] }],
  IR: [
    { key: 'brackets', title: 'Barème progressif (revenu annuel)', cols: [
      { key: 'from_amount', label: 'À partir de (F)', kind: 'money' },
      { key: 'rate', label: 'Taux', kind: 'rate' },
    ] },
    { key: 'reductions', title: 'Réduction pour charges de famille', cols: [
      { key: 'parts', label: 'Parts', kind: 'number' },
      { key: 'rate', label: 'Taux', kind: 'rate' },
      { key: 'min_amount', label: 'Minimum (F)', kind: 'money' },
      { key: 'max_amount', label: 'Maximum (F)', kind: 'money' },
    ] },
    { key: 'trimf', title: 'TRIMF (annuel)', cols: [
      { key: 'min_annual_gross', label: 'Brut annuel à partir de (F)', kind: 'money' },
      { key: 'annual_amount', label: 'Montant (F)', kind: 'money' },
      { key: 'per_part', label: 'Par part', kind: 'bool' },
    ] },
  ],
}
SCALE_GROUPS.QUOTITE_SUPPLEMENTAIRE = SCALE_GROUPS.QUOTITE_PRINCIPAL
SCALE_GROUPS.RETRAITE = SCALE_GROUPS.LICENCIEMENT

export type Line = Record<string, unknown>
export type Row = { raw: Line; cells: Record<string, string> }

const cellText = (v: unknown, kind: ColKind): string => {
  if (v === null || v === undefined) return ''
  if (kind === 'rate') return toInput(Number(v), 'taux')
  if (kind === 'bool') return v ? 'true' : 'false'
  return String(v)
}

/** Lignes du serveur -> lignes éditables (texte). Les clés non affichées (sources, bornes techniques) sont conservées dans `raw`. */
export function toRows(lines: Line[], cols: Col[]): Row[] {
  return lines.map((raw) => ({ raw, cells: Object.fromEntries(cols.map((c) => [c.key, cellText(raw[c.key], c.kind)])) }))
}

/** Lignes éditables -> lignes à envoyer ; `errors` liste les saisies illisibles ou manquantes. */
export function fromRows(rows: Row[], cols: Col[]): { lines: Line[]; errors: string[] } {
  const errors: string[] = []
  const lines = rows.map((r, i) => {
    const out: Line = { ...r.raw }
    for (const c of cols) {
      const s = r.cells[c.key] ?? ''
      if (c.kind === 'text') {
        const t = s.trim()
        if (t === '' && !c.nullable) errors.push(`Ligne ${i + 1} : « ${c.label} » est obligatoire.`)
        out[c.key] = t === '' ? null : t
      } else if (c.kind === 'bool') {
        out[c.key] = s === 'true'
      } else {
        const v = fromInput(s, c.kind === 'rate' ? 'taux' : 'plain')
        if (v === null && !c.nullable) errors.push(`Ligne ${i + 1} : « ${c.label} » est obligatoire.`)
        else if (v !== null && Number.isNaN(v)) errors.push(`Ligne ${i + 1} : « ${c.label} » n'est pas un nombre.`)
        out[c.key] = v === null || Number.isNaN(v) ? null : v
      }
    }
    return out
  })
  return { lines, errors }
}

/** Affichage en lecture seule d'une cellule de barème. */
export function showCell(v: unknown, kind: ColKind): string {
  if (v === null || v === undefined || v === '') return '—'
  if (kind === 'money') return `${fcfa(Number(v))} F`
  if (kind === 'rate') return pct(Number(v))
  if (kind === 'number') return num(Number(v), 4)
  if (kind === 'bool') return v ? 'Oui' : 'Non'
  return String(v)
}

export const KIND_LABEL: Record<string, string> = { derogation: 'Dérogation', constante: 'Constante', bareme: 'Barème' }
