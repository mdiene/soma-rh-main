import clsx from 'clsx'
import { AnimatePresence, LayoutGroup, MotionConfig, motion } from 'framer-motion'
import { LogOut, Menu, Pin, PinOff, Search, Star, type LucideIcon } from 'lucide-react'
import { useQuery } from '@tanstack/react-query'
import { Suspense, useEffect, useRef, useState, useSyncExternalStore } from 'react'
import { NavLink, Outlet, useLocation } from 'react-router-dom'
import { useAuth } from '../lib/auth'
import { dataApi, unwrap, type ApiClient } from '../lib/api'
import { useHighlight } from '../lib/useHighlight'
import { ReturnToCompliance } from './ReturnToCompliance'
import { MAX_FAVORITES, usePreferences } from '../lib/preferences'
import { SPACES, matches, visibleItems, type NavItem } from '../lib/nav'
import { CommandPalette, type PaletteEntry } from './CommandPalette'
import QueryErrorBanner from './QueryErrorBanner'
import { Spinner } from './ui'

type Counts = Partial<Record<NonNullable<NavItem['badge']>, number>>

const EASE = [0.16, 1, 0.3, 1] as const
const PANEL_W = 220 // volet de second niveau (px) ; le rail fait 4,5 rem (72 px)

/** Largeur d'écran « bureau » (lg de Tailwind) : le repli du volet n'existe que là. */
function useDesktop() {
  return useSyncExternalStore(
    (cb) => { const m = window.matchMedia('(min-width: 1024px)'); m.addEventListener('change', cb); return () => m.removeEventListener('change', cb) },
    () => window.matchMedia('(min-width: 1024px)').matches,
    () => true,
  )
}

function Badge({ n, warning, className }: { n?: number; warning?: boolean; className?: string }) {
  if (!n) return null
  return (
    <span className={clsx('rounded-full px-1.5 text-[11px] font-semibold leading-5', warning ? 'bg-[#E0B000] text-ink' : 'bg-signal text-white', className)} aria-label={`${n} en attente`}>
      {n >= 100 ? '99+' : n}
    </span>
  )
}

type Fav = { on: boolean; disabled: boolean; toggle: () => void }

function ItemLink({ item, counts, fav, onNavigate }: { item: NavItem; counts: Counts; fav?: Fav; onNavigate: () => void }) {
  return (
    <motion.div className="group relative" whileHover={{ scale: 1.02 }} whileTap={{ scale: 0.98 }}>
      <NavLink
        to={item.to}
        end={item.to === '/' || item.to === '/paie'}
        onClick={onNavigate}
        className={({ isActive }) => clsx(
          'relative flex items-center gap-2.5 rounded px-2 py-1.5 text-sm transition-colors',
          fav && 'pr-8',
          isActive ? 'bg-white/10 text-white' : 'text-white/70 hover:bg-white/5 hover:text-white',
        )}
      >
        <item.icon className="h-4 w-4 shrink-0" aria-hidden />
        <span>{item.label}</span>
        <Badge n={item.badge ? counts[item.badge] : undefined} warning={item.badge === 'validations' || item.badge === 'approbations'} className="ml-auto" />
      </NavLink>
      {fav && (
        <button
          onClick={fav.toggle} disabled={!fav.on && fav.disabled}
          aria-pressed={fav.on}
          aria-label={fav.on ? `Retirer ${item.label} des favoris` : `Ajouter ${item.label} aux favoris`}
          title={fav.on ? 'Retirer des favoris' : fav.disabled ? `${MAX_FAVORITES} favoris au maximum` : 'Ajouter aux favoris'}
          className={clsx(
            'absolute right-1.5 top-1/2 hidden -translate-y-1/2 rounded p-0.5 text-white/60 hover:text-white focus-visible:opacity-100 disabled:cursor-not-allowed disabled:opacity-30 lg:group-hover:block',
            fav.on ? 'block' : 'focus-visible:block',
          )}
        >
          <Star className={clsx('h-3.5 w-3.5', fav.on && 'fill-[#E0B000] text-[#E0B000]')} aria-hidden />
        </button>
      )}
    </motion.div>
  )
}

/** Icône du rail dans un emplacement de 44 px : elle reste en place quand le rail s'élargit. */
function RailIcon({ icon: Icon, small }: { icon: LucideIcon; small?: boolean }) {
  return <span className="relative flex h-11 w-11 shrink-0 items-center justify-center"><Icon className={small ? 'h-4 w-4' : 'h-5 w-5'} aria-hidden /></span>
}

/** Libellé affiché seulement quand le rail est élargi (le nom accessible vient de aria-label). */
function RailLabel({ show, children }: { show: boolean; children: string }) {
  return show ? <span aria-hidden className="relative min-w-0 flex-1 truncate pr-7 text-left text-sm">{children}</span> : null
}

export function Layout() {
  const { session, can, roles, signOut } = useAuth()
  const { pathname } = useLocation()
  useHighlight()
  const desktop = useDesktop()
  const [open, setOpen] = useState(false)
  const [palette, setPalette] = useState(false)
  const { favorites, toggleFavorite, canAddFavorite } = usePreferences()
  // espace affiché dans le volet : un choix explicite ne vaut que pour la page où il a été fait
  const [picked, setPicked] = useState<{ id: string; path: string }>()
  // panneau flottant (volet replié) : à côté de l'icône cliquée
  const [fly, setFly] = useState<{ id: string; top: number }>()
  // menu épinglé ouvert ou non (bureau seulement), mémorisé par navigateur. Non épinglé (par défaut) : le rail d'icônes reste seul,
  // le volet de chaque espace se déploie au survol ou au clic et se referme au clic sur une page ou quand la souris sort de la zone.
  const [rail, setRail] = useState(() => { try { return localStorage.getItem('nav-rail') !== '0' } catch { return true } })
  const toggleRail = () => { setFly(undefined); setRail((v) => { try { localStorage.setItem('nav-rail', v ? '0' : '1') } catch { /* stockage indisponible */ } return !v }) }
  // survol : ouverture immédiate, fermeture après un court délai (le temps de passer de l'icône au volet)
  const closeTimer = useRef<number>()
  const cancelClose = () => window.clearTimeout(closeTimer.current)
  const [railHover, setRailHover] = useState(false)
  const expandTimer = useRef<number>() // mode épinglé : léger délai avant l'élargissement, pour ne pas recouvrir le volet quand on le vise
  const railExpanded = desktop && railHover // le rail s'élargit (noms des espaces) tant que la souris est sur le rail ou sur le volet flottant
  const hoverClose = () => { cancelClose(); closeTimer.current = window.setTimeout(() => { setFly(undefined); setRailHover(false) }, 220) }
  useEffect(() => () => window.clearTimeout(closeTimer.current), [])
  // clic ou toucher en dehors du rail et du volet flottant : fermeture (le survol seul ne suffit pas sur écran tactile)
  useEffect(() => {
    if (!fly) return
    const outside = (e: PointerEvent) => { if (!(e.target as Element | null)?.closest('[data-nav-zone]')) setFly(undefined) }
    document.addEventListener('pointerdown', outside)
    return () => document.removeEventListener('pointerdown', outside)
  }, [fly])

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
  // demandes de dérogation / de modification de constantes en attente de l'administrateur (les siennes pour rh et paie)
  const approbations = useQuery({
    queryKey: ['approval_pending'],
    enabled: can('rh', 'paie'),
    refetchInterval: 120_000,
    queryFn: async () => unwrap(await (dataApi as unknown as ApiClient).rpc('approval_pending_count')) as unknown as number,
  }).data
  const counts: Counts = { demandes: pending, validations, approbations }

  const allSpaces = SPACES.map((s) => ({ ...s, items: visibleItems(s, can, roles) })).filter((s) => s.items.length)
  // palette et épinglés voient toutes les pages ; le volet n'affiche pas les entrées déjà épinglées
  const entries: PaletteEntry[] = allSpaces.flatMap((s) => s.items.map((i) => ({ ...i, space: s.label })))
  const spaces = allSpaces.map((s) => ({ ...s, items: s.items.filter((i) => !i.pinned) })).filter((s) => s.items.length)
  const inPath = (s: (typeof spaces)[number]) => s.items.some((i) => matches(i, pathname))
  const activeId = (picked && picked.path === pathname ? picked.id : null) ?? spaces.find(inPath)?.id ?? spaces[0]?.id ?? null
  const active = spaces.find((s) => s.id === activeId)
  const total = (s: (typeof spaces)[number]) => s.items.reduce((n, i) => n + (i.badge ? counts[i.badge] ?? 0 : 0), 0)
  // un seul espace (salarié) : pas de rail, le volet affiche directement les pages
  const hasRail = spaces.length > 1
  const collapsed = hasRail && rail && desktop
  // épinglés imposés par le menu (non retirables, sans étoile), puis favoris choisis par l'utilisateur
  const pinnedItems = entries.filter((e, k) => e.pinned && entries.findIndex((x) => x.to === e.to) === k)
  const isPinned = (to: string) => pinnedItems.some((e) => e.to === to)
  const favOf = (to: string): Fav | undefined => isPinned(to) ? undefined : ({ on: favorites.includes(to), disabled: !canAddFavorite, toggle: () => toggleFavorite(to) })
  // favoris : seulement les pages encore accessibles au rôle courant
  const favItems = favorites.filter((to) => !isPinned(to)).map((to) => entries.find((e) => e.to === to)).filter((e): e is PaletteEntry => !!e)
  const done = () => { window.clearTimeout(expandTimer.current); setOpen(false); setFly(undefined); setRailHover(false) }
  const flySpace = spaces.find((s) => s.id === fly?.id)
  const initials = (session?.user.email ?? '?').slice(0, 2).toUpperCase()

  const railButtonCls = 'relative flex h-11 w-full items-center rounded-lg text-white/70 transition-colors hover:bg-white/5 hover:text-white'

  return (
    <MotionConfig reducedMotion="user">
      <div className="min-h-screen lg:flex print:block">
        {/* barre mobile */}
        <div className="no-print flex items-center justify-between bg-ink px-4 py-3 text-white lg:hidden">
          <Brand />
          <button onClick={() => setOpen((o) => !o)} className="rounded p-1.5 hover:bg-white/10" aria-label="Ouvrir le menu" aria-expanded={open}>
            <Menu className="h-5 w-5" />
          </button>
        </div>

        <aside className={clsx('no-print max-h-[calc(100vh-3.25rem)] bg-ink text-white lg:sticky lg:top-0 lg:z-40 lg:flex lg:h-screen lg:max-h-none lg:shrink-0', open ? 'flex' : 'hidden')}>
          <nav className="flex min-h-0 flex-1" aria-label="Navigation principale">
            {/* colonne 1 : rail d'ancrage. Au survol (bureau) il s'élargit en recouvrant le contenu et affiche le nom des espaces, comme la barre latérale de Supabase */}
            {hasRail && (
              <div className="relative w-[4.5rem] shrink-0 lg:z-30">
                <div
                  data-nav-zone
                  onPointerEnter={(e) => { if (!desktop || e.pointerType !== 'mouse') return; cancelClose(); window.clearTimeout(expandTimer.current); if (collapsed) setRailHover(true); else expandTimer.current = window.setTimeout(() => setRailHover(true), 350) }}
                  onPointerLeave={(e) => { if (e.pointerType === 'mouse') { window.clearTimeout(expandTimer.current); hoverClose() } }}
                  className={clsx('absolute inset-y-0 left-0 flex flex-col gap-1 overflow-hidden bg-[#16212A] px-3.5 py-4 transition-[width,box-shadow] duration-200 ease-out', railExpanded ? 'w-72 shadow-2xl shadow-black/40' : 'w-[4.5rem]')}
                >
                  <div className="mb-2 hidden h-11 items-center lg:flex">
                    <span className="flex w-11 shrink-0 justify-center"><Brand compact /></span>
                    {railExpanded && <span className="truncate text-sm font-semibold">SOMA-RH</span>}
                  </div>
                  {pinnedItems.map((i) => (
                    <NavLink key={i.to} to={i.to} end={i.to === '/'} onClick={done} aria-label={i.label}
                      className={({ isActive }) => clsx(railButtonCls, isActive && 'bg-white/10 text-white')}>
                      <RailIcon icon={i.icon} />
                      <RailLabel show={railExpanded}>{i.label}</RailLabel>
                    </NavLink>
                  ))}
                  {pinnedItems.length > 0 && <div className="my-1 h-px bg-white/10" aria-hidden />}
                  <LayoutGroup>
                    {spaces.map((s) => {
                      const isActive = s.id === activeId
                      const n = total(s)
                      return (
                        <div key={s.id}
                          onPointerEnter={(e) => { if (collapsed && e.pointerType === 'mouse') { cancelClose(); setFly({ id: s.id, top: e.currentTarget.getBoundingClientRect().top }) } }}>
                          <motion.button
                            whileTap={{ scale: 0.98 }}
                            onClick={(e) => {
                              if (collapsed) {
                                const r = e.currentTarget.getBoundingClientRect()
                                setFly({ id: s.id, top: r.top }) // ouvert au survol : le clic le garde ouvert (Échap, clic ailleurs ou sortie de la souris le ferment)
                              } else { setPicked({ id: s.id, path: pathname }); setFly(undefined); window.clearTimeout(expandTimer.current); setRailHover(false) }
                            }}
                            aria-label={n ? `${s.label}, ${n} en attente` : s.label}
                            aria-expanded={collapsed ? fly?.id === s.id : isActive}
                            aria-controls={!collapsed && isActive ? `space-${s.id}` : undefined}
                            className={clsx(railButtonCls, (isActive || fly?.id === s.id) && 'text-white')}
                          >
                            {isActive && (
                              <motion.span layoutId="activePillarIndicator" className="absolute inset-0 rounded-lg bg-white/10" transition={{ duration: 0.25, ease: EASE }}>
                                <span className="absolute -left-3.5 top-2 h-7 w-1 rounded-r bg-[#E0B000]" />
                              </motion.span>
                            )}
                            <RailIcon icon={s.icon} />
                            <RailLabel show={railExpanded}>{s.label}</RailLabel>
                            <Badge n={n} className={clsx('absolute min-w-[1.25rem] text-center', railExpanded ? 'right-2 top-1/2 -translate-y-1/2' : '-right-0.5 -top-0.5')} />
                          </motion.button>
                        </div>
                      )
                    })}
                  </LayoutGroup>
                  <div className="mt-auto flex flex-col gap-1 pt-3">
                    {collapsed && (
                      <>
                        <button onClick={() => setPalette(true)} title="Rechercher (Ctrl+K)" aria-label="Rechercher une page (Ctrl+K)" className={railButtonCls}>
                          <RailIcon icon={Search} />
                          <RailLabel show={railExpanded}>Rechercher</RailLabel>
                        </button>
                        <button onClick={toggleRail} aria-pressed={false} aria-label="Épingler le menu ouvert" title="Épingler le menu : le garder ouvert en permanence" className={railButtonCls}>
                          <RailIcon icon={Pin} />
                          <RailLabel show={railExpanded}>Épingler le menu</RailLabel>
                        </button>
                      </>
                    )}
                    <div className="flex h-11 items-center" title={roles.length ? roles.join(', ') : 'aucun rôle attribué'}>
                      <span className="flex w-11 shrink-0 justify-center">
                        <span aria-hidden className="flex h-9 w-9 items-center justify-center rounded-full bg-river text-xs font-semibold text-white">{initials}</span>
                      </span>
                      {railExpanded && <span className="min-w-0 truncate text-xs text-white/70">{session?.user.email}</span>}
                    </div>
                    <button onClick={signOut} title="Se déconnecter" aria-label="Se déconnecter" className={railButtonCls}>
                      <RailIcon icon={LogOut} small />
                      <RailLabel show={railExpanded}>Se déconnecter</RailLabel>
                    </button>
                  </div>
                </div>
              </div>
            )}

            {/* colonne 2 : volet de second niveau, repliable */}
            <motion.div
              className="overflow-hidden"
              initial={false}
              animate={{ width: collapsed ? 0 : PANEL_W }}
              transition={{ duration: 0.28, ease: EASE }}
              {...(collapsed ? ({ inert: '' } as object) : {})}
            >
              <div className="flex h-full flex-col" style={{ width: PANEL_W }}>
                <div className="flex items-center gap-2 px-3 pb-2 pt-4">
                  {hasRail
                    ? <h2 className="min-w-0 flex-1 truncate text-sm font-semibold">{active?.label ?? ''}</h2>
                    : <div className="flex-1"><Brand /></div>}
                  {hasRail && desktop && (
                    <button onClick={toggleRail} aria-pressed={true} aria-label="Désépingler le menu (le replier)" title="Désépingler : le menu se replie et se déploie au survol" className="rounded p-1 text-white/60 hover:bg-white/10 hover:text-white">
                      <PinOff className="h-4 w-4" aria-hidden />
                    </button>
                  )}
                </div>
                <button
                  onClick={() => { setPalette(true); setOpen(false) }}
                  title="Rechercher (Ctrl+K)" aria-label="Rechercher une page (Ctrl+K)"
                  className="mx-3 mb-2 flex items-center gap-2.5 rounded border border-white/15 px-2 py-1.5 text-sm text-white/60 transition-colors hover:border-white/30 hover:text-white"
                >
                  <Search className="h-4 w-4 shrink-0" aria-hidden />
                  <span className="flex-1 text-left">Rechercher</span>
                  <kbd className="rounded bg-white/10 px-1 text-[11px]">Ctrl K</kbd>
                </button>
                <div className="min-h-0 flex-1 overflow-y-auto px-3 pb-3">
                  {(pinnedItems.length > 0 || favItems.length > 0) && (
                    <div className="mb-2 border-b border-white/10 pb-2">
                      <ul className="space-y-0.5">
                        {pinnedItems.map((i) => <li key={i.to}><ItemLink item={i} counts={counts} onNavigate={done} /></li>)}
                      </ul>
                      {favItems.length > 0 && <p className="px-2 pb-1 pt-2 text-xs text-white/45">Favoris</p>}
                      <ul className="space-y-0.5">
                        {favItems.map((i) => <li key={i.to}><ItemLink item={i} counts={counts} fav={favOf(i.to)} onNavigate={done} /></li>)}
                      </ul>
                    </div>
                  )}
                  <AnimatePresence mode="wait" initial={false}>
                    {active && (
                      <motion.ul
                        key={active.id} id={`space-${active.id}`} className="space-y-0.5"
                        initial={{ opacity: 0, x: -8 }} animate={{ opacity: 1, x: 0 }} exit={{ opacity: 0, x: -8 }} transition={{ duration: 0.16 }}
                      >
                        {active.items.map((i) => <li key={i.to}><ItemLink item={i} counts={counts} fav={favOf(i.to)} onNavigate={done} /></li>)}
                      </motion.ul>
                    )}
                  </AnimatePresence>
                </div>
                <div className="border-t border-white/10 px-4 py-3 text-xs text-white/60">
                  <p className="truncate text-white/85">{session?.user.email}</p>
                  <p className="mt-0.5">{roles.length ? roles.join(', ') : 'aucun rôle attribué'}</p>
                  {!hasRail && (
                    <button onClick={signOut} title="Se déconnecter" aria-label="Se déconnecter" className="mt-2 inline-flex items-center gap-1.5 text-white/70 hover:text-white">
                      <LogOut className="h-3.5 w-3.5" aria-hidden /> Se déconnecter
                    </button>
                  )}
                </div>
              </div>
            </motion.div>
          </nav>

          {/* panneau flottant du volet replié */}
          <AnimatePresence>
            {collapsed && fly && flySpace && (
              <>
                <motion.div
                  role="group" aria-label={flySpace.label} data-nav-zone
                  onPointerEnter={(e) => { if (e.pointerType === 'mouse') { cancelClose(); setRailHover(true) } }} onPointerLeave={(e) => { if (e.pointerType === 'mouse') hoverClose() }}
                  initial={{ opacity: 0, scale: 0.95 }} animate={{ opacity: 1, scale: 1 }} exit={{ opacity: 0, scale: 0.95 }}
                  transition={{ type: 'spring', stiffness: 420, damping: 32 }}
                  className="fixed z-50 hidden w-64 origin-top-left rounded-md border border-white/10 bg-ink p-2 text-white shadow-xl lg:block"
                  style={{ left: railExpanded ? '18.25rem' : '4.75rem', top: Math.max(8, Math.min(fly.top, window.innerHeight - 48 - flySpace.items.length * 34)) }}
                >
                  <div className="flex items-center justify-between px-2 pb-1 pt-0.5">
                    <p className="text-xs font-medium text-white/50">{flySpace.label}</p>
                    <button onClick={toggleRail} aria-pressed={false} aria-label="Épingler le menu ouvert" title="Épingler le menu : le garder ouvert en permanence" className="rounded p-1 text-white/50 hover:bg-white/10 hover:text-white">
                      <Pin className="h-3.5 w-3.5" aria-hidden />
                    </button>
                  </div>
                  <ul className="space-y-0.5">
                    {flySpace.items.map((i) => <li key={i.to}><ItemLink item={i} counts={counts} fav={favOf(i.to)} onNavigate={done} /></li>)}
                  </ul>
                </motion.div>
              </>
            )}
          </AnimatePresence>
        </aside>

        <CommandPalette open={palette} onClose={() => setPalette(false)} entries={entries} />
        <main className="min-w-0 flex-1 px-4 py-6 sm:px-6 lg:px-10 lg:py-8">
          <Suspense fallback={<Spinner />}>
            <QueryErrorBanner />
            <ReturnToCompliance />
            <Outlet />
          </Suspense>
        </main>
      </div>
    </MotionConfig>
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
