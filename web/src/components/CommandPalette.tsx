import clsx from 'clsx'
import { AnimatePresence, motion } from 'framer-motion'
import { Search } from 'lucide-react'
import { useEffect, useMemo, useRef, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import type { NavItem } from '../lib/nav'

export type PaletteEntry = NavItem & { space: string }

// sans accents ni casse : « conge » trouve « Congés », « ipres » trouve les états légaux
const norm = (s: string) => s.normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase()

/** Recherche rapide (Ctrl+K / Cmd+K) dans les entrées du menu accessibles à l'utilisateur, groupées par espace. */
export function CommandPalette({ open, onClose, entries }: { open: boolean; onClose: () => void; entries: PaletteEntry[] }) {
  const navigate = useNavigate()
  const [q, setQ] = useState('')
  const [active, setActive] = useState(0)
  const input = useRef<HTMLInputElement>(null)

  const hits = useMemo(() => {
    const words = norm(q).split(/\s+/).filter(Boolean)
    // un mot par mot : tous doivent figurer dans libellé, espace ou mots-clés
    return entries.filter((e) => {
      const hay = norm(`${e.label} ${e.space} ${e.keywords ?? ''}`)
      return words.every((w) => hay.includes(w))
    })
  }, [q, entries])

  useEffect(() => { if (open) { setQ(''); setActive(0); input.current?.focus() } }, [open])
  useEffect(() => setActive(0), [q])

  const go = (e?: PaletteEntry) => { if (!e) return; onClose(); navigate(e.to) }

  return (
    <AnimatePresence>
      {open && (
        <motion.div
          className="no-print fixed inset-0 z-[60] flex items-start justify-center bg-ink/50 px-4 pt-[15vh] backdrop-blur-[2px]"
          initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }} transition={{ duration: 0.15 }}
          onMouseDown={onClose}
        >
          <motion.div
            role="dialog" aria-modal="true" aria-label="Recherche rapide"
            className="w-full max-w-lg overflow-hidden rounded-lg border border-line bg-white shadow-2xl"
            initial={{ opacity: 0, scale: 0.96, y: -10 }} animate={{ opacity: 1, scale: 1, y: 0 }} exit={{ opacity: 0, scale: 0.96, y: -10 }}
            transition={{ type: 'spring', stiffness: 380, damping: 34 }}
            onMouseDown={(e) => e.stopPropagation()}
            onKeyDown={(e) => {
              if (e.key === 'Escape') onClose()
              else if (e.key === 'ArrowDown') { e.preventDefault(); setActive((a) => Math.min(a + 1, hits.length - 1)) }
              else if (e.key === 'ArrowUp') { e.preventDefault(); setActive((a) => Math.max(a - 1, 0)) }
              else if (e.key === 'Enter') { e.preventDefault(); go(hits[active]) }
            }}
          >
            <div className="flex items-center gap-2 border-b border-line px-3">
              <Search className="h-4 w-4 text-ink-soft" aria-hidden />
              <input
                ref={input} value={q} onChange={(e) => setQ(e.target.value)} autoFocus
                role="combobox" aria-expanded="true" aria-controls="palette-list" aria-activedescendant={hits[active] ? `palette-${active}` : undefined}
                placeholder="Aller à… (bulletin, IPRES, congé)"
                className="h-12 w-full bg-transparent text-sm outline-none placeholder:text-ink-soft"
              />
            </div>
            <ul id="palette-list" role="listbox" aria-label="Pages" className="max-h-80 overflow-y-auto p-1">
              {hits.length === 0 && <li role="presentation" className="px-3 py-6 text-center text-sm text-ink-soft">Aucune page ne correspond.</li>}
              {hits.map((e, i) => (
                <li key={`${e.space}-${e.to}`} role="presentation">
                  {(i === 0 || hits[i - 1].space !== e.space) && (
                    <p aria-hidden className="px-3 pb-1 pt-2 text-[11px] font-semibold uppercase tracking-wide text-ink-soft">{e.space}</p>
                  )}
                  <motion.div
                    layout="position" id={`palette-${i}`} role="option" aria-selected={i === active} aria-label={`${e.label}, ${e.space}`}
                    onMouseEnter={() => setActive(i)} onClick={() => go(e)}
                    className={clsx('flex cursor-pointer items-center gap-2.5 rounded px-3 py-2 text-sm text-ink', i === active && 'bg-river/10')}
                  >
                    <e.icon className="h-4 w-4 shrink-0 text-ink-soft" aria-hidden />
                    <span>{e.label}</span>
                  </motion.div>
                </li>
              ))}
            </ul>
            <div aria-hidden className="flex items-center gap-4 border-t border-line bg-paper px-3 py-2 text-[11px] text-ink-soft">
              <span><kbd className="rounded bg-white px-1 ring-1 ring-line">↑↓</kbd> naviguer</span>
              <span><kbd className="rounded bg-white px-1 ring-1 ring-line">↵</kbd> ouvrir</span>
              <span><kbd className="rounded bg-white px-1 ring-1 ring-line">Esc</kbd> fermer</span>
            </div>
          </motion.div>
        </motion.div>
      )}
    </AnimatePresence>
  )
}
