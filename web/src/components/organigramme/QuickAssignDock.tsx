import { motion } from 'framer-motion'
import { Cog, Landmark, LayoutGrid, Layers, X } from 'lucide-react'
import { useMemo, useState, type DragEvent } from 'react'
import type { OrgUnit, UnitKind } from '../../lib/org'
import { EMPLOYEE_MIME } from './orgContext'

/** Fenêtre flottante « Assignation rapide » : on y dépose une carte salarié sur une direction, un secteur ou une section pour l'y rattacher.
 *  Le glisser-déposer n'a pas d'équivalent clavier ici : le menu « + » de la carte (« Affecter à une direction ou un secteur… ») reste disponible. */

const ICON: Record<UnitKind, typeof Landmark> = { direction: Landmark, secteur: Layers, section: LayoutGrid, service: Cog }

export function QuickAssignDock({ units, shifted, busy, onClose, onAssign }: {
  units: OrgUnit[]
  shifted: boolean                      // une fiche est ouverte à droite : la fenêtre se décale
  busy: boolean
  onClose: () => void
  onAssign: (employeeId: string, unitId: string) => void
}) {
  const [over, setOver] = useState<string | null>(null)
  // ordre de lecture de l'arborescence : chaque unité sous son parent, retrait selon la profondeur
  const rows = useMemo(() => {
    const byParent = new Map<string | null, OrgUnit[]>()
    const ids = new Set(units.map((u) => u.id))
    for (const u of units) { const p = u.parent && ids.has(u.parent) ? u.parent : null; byParent.set(p, [...(byParent.get(p) ?? []), u]) }
    const out: { unit: OrgUnit; depth: number }[] = []
    const walk = (p: string | null, depth: number) => {
      for (const u of [...(byParent.get(p) ?? [])].sort((a, b) => a.nom.localeCompare(b.nom, 'fr'))) { out.push({ unit: u, depth }); walk(u.id, depth + 1) }
    }
    walk(null, 0)
    return out
  }, [units])

  const accepts = (e: DragEvent) => e.dataTransfer.types.includes(EMPLOYEE_MIME)

  return (
    <motion.aside
      aria-label="Assignation rapide"
      className="org-glass absolute top-3 z-30 flex w-[300px] flex-col rounded-2xl p-3 shadow-2xl backdrop-blur-md"
      style={{ right: shifted ? 404 : 12, maxHeight: 'calc(100% - 160px)' }}
      initial={{ opacity: 0, y: -10, scale: 0.97 }} animate={{ opacity: 1, y: 0, scale: 1 }} exit={{ opacity: 0, y: -10, scale: 0.97 }}
      transition={{ type: 'spring', stiffness: 380, damping: 34 }}
    >
      <div className="mb-2 flex items-center justify-between gap-2 border-b pb-2" style={{ borderColor: 'var(--o-border)' }}>
        <h2 className="text-sm font-semibold">Assignation rapide</h2>
        <button type="button" className="org-btn" style={{ minHeight: 28, padding: '0 6px' }} onClick={onClose} aria-label="Fermer l’assignation rapide"><X className="h-4 w-4" aria-hidden /></button>
      </div>
      <p className="mb-2 text-xs" style={{ color: 'var(--o-muted)' }}>Glissez une carte salarié sur la direction, le secteur ou la section où le rattacher. Son manager n’est pas modifié.</p>
      {rows.length === 0 ? (
        <p className="py-4 text-center text-xs" style={{ color: 'var(--o-muted)' }}>Aucune unité : créez une direction avec le bouton « Créer ».</p>
      ) : (
        <ul className="min-h-0 flex-1 space-y-1.5 overflow-y-auto pr-0.5" aria-busy={busy}>
          {rows.map(({ unit: u, depth }) => {
            const Icon = ICON[u.type]
            const active = over === u.id
            return (
              <li key={u.id}
                onDragEnter={(e) => { if (accepts(e)) { e.preventDefault(); setOver(u.id) } }}
                onDragOver={(e) => { if (accepts(e)) { e.preventDefault(); e.dataTransfer.dropEffect = 'move' } }}
                onDragLeave={(e) => { if (!e.currentTarget.contains(e.relatedTarget as Node | null)) setOver((o) => (o === u.id ? null : o)) }}
                onDrop={(e) => {
                  if (!accepts(e)) return
                  e.preventDefault(); setOver(null)
                  const id = e.dataTransfer.getData(EMPLOYEE_MIME)
                  if (id && !busy) onAssign(id, u.id)
                }}
                className="flex items-center justify-between gap-2 rounded-xl border px-2.5 py-2 text-sm transition-colors"
                data-drop-active={active ? 'true' : 'false'}
                style={{
                  marginLeft: depth * 14,
                  borderColor: active ? 'var(--o-violet)' : 'var(--o-border)',
                  background: active ? 'color-mix(in srgb, var(--o-violet) 14%, transparent)' : 'var(--o-card-2)',
                  boxShadow: active ? '0 0 0 2px color-mix(in srgb, var(--o-violet) 40%, transparent)' : undefined,
                }}>
                <span className="flex min-w-0 items-center gap-2"><Icon className="h-4 w-4 shrink-0" aria-hidden style={{ color: 'var(--o-muted)' }} /><span className="truncate font-medium">{u.nom}</span></span>
                <span className="org-chip" aria-label={`${u.membres} salarié(s)`}>{u.membres}</span>
              </li>
            )
          })}
        </ul>
      )}
    </motion.aside>
  )
}
