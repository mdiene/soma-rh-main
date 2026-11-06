import clsx from 'clsx'
import { Search } from 'lucide-react'
import { useEffect, useMemo, useRef, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import type { NavItem } from '../lib/nav'

export type PaletteEntry = NavItem & { space: string }

// sans accents ni casse : « conge » trouve « Congés », « ipres » trouve les états légaux
const norm = (s: string) => s.normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase()

/** Recherche rapide (Ctrl+K / Cmd+K) dans les entrées du menu accessibles à l'utilisateur. */
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

  if (!open) return null
  const go = (e?: PaletteEntry) => { if (!e) return; onClose(); navigate(e.to) }

  return (
    <div className="no-print fixed inset-0 z-[60] flex items-start justify-center bg-ink/50 px-4 pt-[15vh]" onMouseDown={onClose}>
      <div
        role="dialog" aria-modal="true" aria-label="Recherche rapide"
        className="w-full max-w-lg overflow-hidden rounded-lg border border-line bg-white shadow-2xl"
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
            ref={input} value={q} onChange={(e) => setQ(e.target.value)}
            role="combobox" aria-expanded="true" aria-controls="palette-list" aria-activedescendant={hits[active] ? `palette-${active}` : undefined}
            placeholder="Aller à… (bulletin, IPRES, congé)"
            className="h-12 w-full bg-transparent text-sm outline-none placeholder:text-ink-soft"
          />
        </div>
        <ul id="palette-list" role="listbox" className="max-h-80 overflow-y-auto p-1">
          {hits.length === 0 && <li className="px-3 py-6 text-center text-sm text-ink-soft">Aucune page ne correspond.</li>}
          {hits.map((e, i) => (
            <li
              key={`${e.space}-${e.to}`} id={`palette-${i}`} role="option" aria-selected={i === active}
              onMouseEnter={() => setActive(i)} onClick={() => go(e)}
              className={clsx('flex cursor-pointer items-center gap-2.5 rounded px-3 py-2 text-sm', i === active ? 'bg-river/10 text-ink' : 'text-ink')}
            >
              <e.icon className="h-4 w-4 shrink-0 text-ink-soft" aria-hidden />
              <span>{e.label}</span>
              <span className="ml-auto text-xs text-ink-soft">{e.space}</span>
            </li>
          ))}
        </ul>
      </div>
    </div>
  )
}
