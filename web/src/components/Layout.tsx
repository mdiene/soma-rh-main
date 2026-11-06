import clsx from 'clsx'
import { ChevronDown, ChevronsLeft, ChevronsRight, LogOut, Menu, Search } from 'lucide-react'
import { useQuery } from '@tanstack/react-query'
import { Suspense, useEffect, useState } from 'react'
import { NavLink, Outlet, useLocation } from 'react-router-dom'
import { useAuth } from '../lib/auth'
import { dataApi, unwrap, type ApiClient } from '../lib/api'
import { SPACES, matches, visibleItems, type NavItem } from '../lib/nav'
import { CommandPalette, type PaletteEntry } from './CommandPalette'
import QueryErrorBanner from './QueryErrorBanner'
import { Spinner } from './ui'

type Counts = Partial<Record<NonNullable<NavItem['badge']>, number>>

function Badge({ n, className }: { n?: number; className?: string }) {
  if (!n) return null
  return (
    <span className={clsx('rounded-full bg-signal px-1.5 text-[11px] font-semibold leading-5 text-white', className)} aria-label={`${n} en attente`}>
      {n >= 100 ? '99+' : n}
    </span>
  )
}

function ItemLink({ item, counts, rail, onNavigate }: { item: NavItem; counts: Counts; rail?: boolean; onNavigate: () => void }) {
  return (
    <NavLink
      to={item.to}
      end={item.to === '/' || item.to === '/paie'}
      title={rail ? item.label : undefined}
      onClick={onNavigate}
      className={({ isActive }) => clsx(
        'relative flex items-center gap-2.5 rounded px-2 py-1.5 text-sm transition-colors',
        isActive ? 'bg-white/10 text-white' : 'text-white/70 hover:bg-white/5 hover:text-white',
      )}
    >
      <item.icon className="h-4 w-4 shrink-0" aria-hidden />
      <span className={rail ? 'lg:hidden' : ''}>{item.label}</span>
      <Badge n={item.badge ? counts[item.badge] : undefined} className={clsx('ml-auto', rail && 'lg:absolute lg:right-1 lg:top-0 lg:ml-0')} />
    </NavLink>
  )
}

export function Layout() {
  const { session, can, roles, signOut } = useAuth()
  const { pathname } = useLocation()
  const [open, setOpen] = useState(false)
  const [palette, setPalette] = useState(false)
  // accordéon à ouverture unique : un choix explicite ne vaut que pour la page où il a été fait
  const [picked, setPicked] = useState<{ id: string | null; path: string }>()
  // flyout (sidebar réduite) : panneau flottant à côté de l'icône cliquée
  const [fly, setFly] = useState<{ id: string; top: number }>()
  // sidebar réduite aux icônes (bureau seulement), mémorisée par navigateur
  const [rail, setRail] = useState(() => { try { return localStorage.getItem('nav-rail') === '1' } catch { return false } })
  const toggleRail = () => { setFly(undefined); setRail((v) => { try { localStorage.setItem('nav-rail', v ? '0' : '1') } catch { /* stockage indisponible */ } return !v }) }
  const hide = rail ? 'lg:hidden' : ''

  // Ctrl+K / Cmd+K : recherche rapide
  useEffect(() => {
    const k = (e: KeyboardEvent) => { if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === 'k') { e.preventDefault(); setPalette((v) => !v) } }
    window.addEventListener('keydown', k)
    return () => window.removeEventListener('keydown', k)
  }, [])

  useEffect(() => {
    if (!fly) return
    const close = (e: KeyboardEvent) => e.key === 'Escape' && setFly(undefined)
    window.addEventListener('keydown', close)
    return () => window.removeEventListener('keydown', close)
  }, [fly])

  // compteur des demandes ouvertes (clé sous ['employee_requests'] : invalidée par les décisions)
  const pending = useQuery({
    queryKey: ['employee_requests', 'badge'],
    enabled: can('rh'),
    refetchInterval: 120_000,
    queryFn: async () => unwrap(await (dataApi as unknown as ApiClient).from('employee_requests').select('id').eq('status', 'Ouverte').limit(100)).length,
  }).data
  // congés à valider par l'utilisateur (même clé que LeaveApprovals : rafraîchi après chaque décision)
  const validations = useQuery({
    queryKey: ['my_leave_approvals'],
    enabled: can('manager', 'rh'),
    refetchInterval: 120_000,
    queryFn: async () => unwrap(await (dataApi as unknown as ApiClient).rpc('my_leave_approvals')) as unknown as unknown[],
    select: (rows) => rows.length,
  }).data
  const counts: Counts = { demandes: pending, validations }

  const spaces = SPACES.map((s) => ({ ...s, items: visibleItems(s, can, roles) })).filter((s) => s.items.length)
  const inPath = (s: (typeof spaces)[number]) => s.items.some((i) => matches(i, pathname))
  // ouvert : le choix fait sur cette page, sinon l'espace qui contient la page
  const openId = picked && picked.path === pathname ? picked.id : spaces.find(inPath)?.id ?? null
  const total = (s: (typeof spaces)[number]) => s.items.reduce((n, i) => n + (i.badge ? counts[i.badge] ?? 0 : 0), 0)
  const entries: PaletteEntry[] = spaces.flatMap((s) => s.items.map((i) => ({ ...i, space: s.label })))
  const done = () => { setOpen(false); setFly(undefined) }

  const nav = (
    <nav className="flex flex-1 flex-col gap-1 overflow-y-auto px-3 py-4" aria-label="Navigation principale">
      {spaces.length === 1 ? (
        <ul className="space-y-0.5">
          {spaces[0].items.map((i) => <li key={i.to}><ItemLink item={i} counts={counts} rail={rail} onNavigate={done} /></li>)}
        </ul>
      ) : spaces.map((s) => {
        const isOpen = openId === s.id && !rail
        const active = inPath(s)
        return (
          <div key={s.id}>
            <button
              onClick={(e) => {
                if (rail) {
                  const r = e.currentTarget.getBoundingClientRect()
                  setFly((f) => (f?.id === s.id ? undefined : { id: s.id, top: r.top }))
                } else setPicked({ id: isOpen ? null : s.id, path: pathname })
              }}
              title={rail ? s.label : undefined}
              aria-label={total(s) ? `${s.label}, ${total(s)} en attente` : s.label}
              aria-expanded={rail ? fly?.id === s.id : isOpen}
              aria-controls={`space-${s.id}`}
              className={clsx(
                'relative flex w-full items-center gap-2.5 rounded px-2 py-1.5 text-left text-sm font-medium transition-colors hover:text-white',
                active || isOpen || fly?.id === s.id ? 'text-white' : 'text-white/60',
              )}
            >
              <s.icon className="h-4 w-4 shrink-0" aria-hidden />
              <span className={clsx('flex-1', hide)}>{s.label}</span>
              {/* compteur d'un espace refermé : on voit où intervenir sans l'ouvrir */}
              {!isOpen && <Badge n={total(s)} className={clsx(rail && 'lg:absolute lg:right-1 lg:top-0')} />}
              <ChevronDown className={clsx('h-4 w-4 shrink-0 transition-transform duration-200 motion-reduce:transition-none', isOpen && 'rotate-180', hide)} aria-hidden />
            </button>
            {/* glissement : la hauteur passe de 0 à auto via grid-rows ; inert retire les liens cachés du clavier */}
            <div
              id={`space-${s.id}`}
              className={clsx('grid transition-[grid-template-rows] duration-200 ease-out motion-reduce:transition-none', isOpen ? 'grid-rows-[1fr]' : 'grid-rows-[0fr]')}
              {...(isOpen ? {} : ({ inert: '' } as object))}
            >
              <ul className="ml-4 space-y-0.5 overflow-hidden border-l border-white/10 pl-2">
                {s.items.map((i) => <li key={i.to}><ItemLink item={i} counts={counts} onNavigate={done} /></li>)}
              </ul>
            </div>
          </div>
        )
      })}
    </nav>
  )
  const flySpace = spaces.find((s) => s.id === fly?.id)

  return (
    <div className={clsx('min-h-screen lg:grid print:block print:bg-none print:bg-white',
      rail ? 'lg:grid-cols-[4rem_1fr] lg:bg-[linear-gradient(to_right,#1D2A33_4rem,#F6F7F5_4rem)]' : 'lg:grid-cols-[15rem_1fr] lg:bg-[linear-gradient(to_right,#1D2A33_15rem,#F6F7F5_15rem)]')}>
      {/* barre mobile */}
      <div className="no-print flex items-center justify-between bg-ink px-4 py-3 text-white lg:hidden">
        <Brand />
        <button onClick={() => setOpen((o) => !o)} className="rounded p-1.5 hover:bg-white/10" aria-label="Ouvrir le menu" aria-expanded={open}>
          <Menu className="h-5 w-5" />
        </button>
      </div>

      <aside className={clsx(
        'no-print flex-col bg-ink text-white lg:sticky lg:top-0 lg:flex lg:h-screen',
        open ? 'flex' : 'hidden',
      )}>
        <div className={clsx('hidden pb-2 pt-5 lg:block', rail ? 'px-3' : 'px-5')}><Brand compact={rail} /></div>
        <button
          onClick={() => { setPalette(true); setOpen(false) }}
          title="Rechercher (Ctrl+K)" aria-label="Rechercher une page (Ctrl+K)"
          className={clsx('mx-3 mt-3 flex items-center gap-2.5 rounded border border-white/15 px-2 py-1.5 text-sm text-white/60 transition-colors hover:border-white/30 hover:text-white', rail && 'lg:justify-center')}
        >
          <Search className="h-4 w-4 shrink-0" aria-hidden />
          <span className={clsx('flex-1 text-left', hide)}>Rechercher</span>
          <kbd className={clsx('rounded bg-white/10 px-1 text-[11px]', hide)}>Ctrl K</kbd>
        </button>
        {nav}
        {rail && fly && flySpace && (
          <>
            <div className="fixed inset-0 z-40 hidden lg:block" onClick={() => setFly(undefined)} aria-hidden />
            <div
              role="group" aria-label={flySpace.label}
              className="fixed z-50 hidden w-64 rounded-md border border-white/10 bg-ink p-2 text-white shadow-xl lg:block"
              style={{ left: '4.25rem', top: Math.max(8, Math.min(fly.top, window.innerHeight - 48 - flySpace.items.length * 34)) }}
            >
              <p className="px-2 pb-1 pt-0.5 text-xs font-medium text-white/50">{flySpace.label}</p>
              <ul className="space-y-0.5">
                {flySpace.items.map((i) => <li key={i.to}><ItemLink item={i} counts={counts} onNavigate={done} /></li>)}
              </ul>
            </div>
          </>
        )}
        <div className="border-t border-white/10 px-4 py-3 text-xs text-white/60">
          <div className={hide}>
            <p className="truncate text-white/85">{session?.user.email}</p>
            <p className="mt-0.5">{roles.length ? roles.join(', ') : 'aucun rôle attribué'}</p>
          </div>
          <button onClick={signOut} title="Se déconnecter" aria-label="Se déconnecter" className="mt-2 inline-flex items-center gap-1.5 text-white/70 hover:text-white">
            <LogOut className="h-3.5 w-3.5" aria-hidden /> <span className={hide}>Se déconnecter</span>
          </button>
          <button onClick={toggleRail} aria-pressed={rail} aria-label={rail ? 'Développer le menu' : 'Réduire le menu'} title={rail ? 'Développer le menu' : 'Réduire le menu'}
            className="mt-2 hidden items-center gap-1.5 text-white/70 hover:text-white lg:inline-flex">
            {rail ? <ChevronsRight className="h-3.5 w-3.5" aria-hidden /> : <><ChevronsLeft className="h-3.5 w-3.5" aria-hidden /> Réduire</>}
          </button>
        </div>
      </aside>

      <CommandPalette open={palette} onClose={() => setPalette(false)} entries={entries} />
      <main className="min-w-0 px-4 py-6 sm:px-6 lg:px-10 lg:py-8">
        <Suspense fallback={<Spinner />}>
          <QueryErrorBanner />
          <Outlet />
        </Suspense>
      </main>
    </div>
  )
}

function Brand({ compact = false }: { compact?: boolean }) {
  return (
    <div className="flex items-center gap-2.5">
      <svg viewBox="0 0 32 32" className="h-7 w-7" aria-hidden>
        <rect width="32" height="32" rx="6" fill="#ffffff" fillOpacity="0.08" />
        <path d="M8 22 L13 10 L18 22 Z" fill="#0F6E6A" />
        <path d="M15 22 L20 13 L25 22 Z" fill="#E0B000" />
      </svg>
      <div className={clsx('leading-tight', compact && 'hidden')}>
        <p className="text-[15px] font-bold" style={{ fontStretch: '80%' }}>SOMA-RH</p>
        <p className="text-[11px] text-white/55">Personnel et paie</p>
      </div>
    </div>
  )
}
