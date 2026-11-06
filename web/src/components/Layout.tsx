import clsx from 'clsx'
import { ChevronsLeft, ChevronsRight, LogOut, Menu } from 'lucide-react'
import { useQuery } from '@tanstack/react-query'
import { Suspense, useState } from 'react'
import { NavLink, Outlet, useLocation, useNavigate } from 'react-router-dom'
import { useAuth } from '../lib/auth'
import { dataApi, unwrap, type ApiClient } from '../lib/api'
import { SPACES, matches, visibleItems } from '../lib/nav'
import QueryErrorBanner from './QueryErrorBanner'
import { Spinner } from './ui'

export function Layout() {
  const { session, can, roles, signOut } = useAuth()
  const { pathname } = useLocation()
  const navigate = useNavigate()
  const [open, setOpen] = useState(false)
  const [picked, setPicked] = useState<string>()
  // sidebar réduite aux icônes (bureau seulement), mémorisée par navigateur
  const [rail, setRail] = useState(() => { try { return localStorage.getItem('nav-rail') === '1' } catch { return false } })
  const toggleRail = () => setRail((v) => { try { localStorage.setItem('nav-rail', v ? '0' : '1') } catch { /* stockage indisponible */ } return !v })
  const hide = rail ? 'lg:hidden' : ''

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
  const counts = { demandes: pending, validations }

  const spaces = SPACES.map((s) => ({ ...s, items: visibleItems(s, can, roles) })).filter((s) => s.items.length)
  // espace courant : choix explicite s'il contient la page, sinon celui qui contient la page, sinon le choix, sinon le premier
  const inPath = (s: (typeof spaces)[number]) => s.items.some((i) => matches(i, pathname))
  const current = spaces.find((s) => s.id === picked && inPath(s)) ?? spaces.find(inPath) ?? spaces.find((s) => s.id === picked) ?? spaces[0]

  const nav = (
    <nav className="flex flex-1 flex-col gap-4 overflow-y-auto px-3 py-4" aria-label="Navigation principale">
      {spaces.length > 1 && (
        <ul className="space-y-0.5 border-b border-white/10 pb-3" aria-label="Espaces">
          {spaces.map((s) => (
            <li key={s.id}>
              <button
                onClick={() => { setPicked(s.id); if (!inPath(s)) navigate(s.items[0].to) }}
                title={rail ? s.label : undefined}
                aria-current={s.id === current?.id ? 'true' : undefined}
                className={clsx(
                  'flex w-full items-center gap-2.5 rounded px-2 py-1.5 text-left text-sm font-medium transition-colors',
                  s.id === current?.id ? 'text-white' : 'text-white/55 hover:text-white',
                )}
              >
                <s.icon className="h-4 w-4 shrink-0" aria-hidden />
                <span className={hide}>{s.label}</span>
              </button>
            </li>
          ))}
        </ul>
      )}
      <ul className="space-y-0.5">
        {current?.items.map((i) => (
          <li key={i.to}>
            <NavLink
              to={i.to}
              end={i.to === '/' || i.to === '/paie'}
              title={rail ? i.label : undefined}
              onClick={() => setOpen(false)}
              className={({ isActive }) => clsx(
                'relative flex items-center gap-2.5 rounded px-2 py-1.5 text-sm transition-colors',
                isActive ? 'bg-white/10 text-white' : 'text-white/70 hover:bg-white/5 hover:text-white',
              )}
            >
              <i.icon className="h-4 w-4 shrink-0" aria-hidden />
              <span className={hide}>{i.label}</span>
              {i.badge && !!counts[i.badge] && (
                <span className={clsx('ml-auto rounded-full bg-signal px-1.5 text-[11px] font-semibold leading-5 text-white', rail && 'lg:absolute lg:right-1 lg:top-0 lg:ml-0')} aria-label={`${counts[i.badge]} en attente`}>
                  {counts[i.badge]! >= 100 ? '99+' : counts[i.badge]}
                </span>
              )}
            </NavLink>
          </li>
        ))}
      </ul>
    </nav>
  )

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
        {nav}
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
