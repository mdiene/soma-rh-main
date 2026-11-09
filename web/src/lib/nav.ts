import {
  Banknote, CalendarCheck2, CalendarRange, CalendarDays, Calculator, FileSpreadsheet, FileText, History, Inbox, LayoutDashboard,
  LockKeyhole, Network, PieChart, Settings, ShieldCheck, SlidersHorizontal, UserCircle, Users, Wallet, Receipt,
  Blocks, Briefcase, Cog, UsersRound, type LucideIcon,
} from 'lucide-react'
import type { Role } from './auth'

// Source unique du menu. `admin` passe partout via can(). Le menu n'est qu'un confort :
// la sécurité réelle reste le RLS (has_role) en base.
export type NavItem = {
  to: string
  label: string
  icon: LucideIcon
  roles?: Role[]          // absent = tout utilisateur connecté
  withoutRole?: boolean   // visible même sans rôle (déclarer le premier administrateur)
  pinned?: boolean        // épinglé en tête du menu pour tous les rôles qui y ont accès, non retirable
  keywords?: string       // mots de recherche supplémentaires (palette Ctrl+K)
  badge?: 'demandes' | 'validations'      // compteur dynamique affiché à droite
}
export type NavSpace = { id: string; label: string; icon: LucideIcon; items: NavItem[] }

export const SPACES: NavSpace[] = [
  { id: 'perso', label: 'Espace personnel', icon: UserCircle, items: [
    { to: '/mon-espace', label: 'Mon profil et mes demandes', icon: UserCircle, roles: ['salarie', 'rh', 'paie', 'manager'] },
    { to: '/conges', label: 'Mes congés', icon: CalendarDays, roles: ['salarie', 'manager'], keywords: 'conge absence solde demande' },
    { to: '/mes-bulletins', label: 'Mes bulletins', icon: Receipt, roles: ['salarie', 'rh', 'paie', 'manager'], keywords: 'bulletin fiche de paie salaire' },
  ] },
  { id: 'equipe', label: 'Management', icon: UsersRound, items: [
    { to: '/mon-equipe', label: 'Mon équipe et validations', icon: Users, roles: ['manager'], badge: 'validations' },
    { to: '/equipes/organigramme', label: 'Organigramme d’équipe', icon: Network, roles: ['manager'] },
  ] },
  { id: 'rh', label: 'Administration du personnel', icon: Briefcase, items: [
    { to: '/salaries', label: 'Salariés', icon: Users, roles: ['rh', 'paie'], keywords: 'annuaire employé personnel' },
    { to: '/dossiers-salaries', label: 'Dossiers administratifs', icon: FileText, roles: ['rh'] },
    { to: '/demandes', label: 'Demandes des salariés', icon: Inbox, roles: ['rh'], badge: 'demandes' },
    { to: '/conges', label: 'Congés et absences', icon: CalendarDays, roles: ['rh', 'paie'], badge: 'validations', keywords: 'conge solde rtt maladie' },
    { to: '/presences', label: 'Présences', icon: CalendarCheck2, roles: ['rh', 'paie'] },
    { to: '/planning', label: 'Planning métier', icon: CalendarRange, roles: ['rh', 'paie'], keywords: 'poste vacation equipe rotation nuit gardiennage' },
    { to: '/equipes', label: 'Équipes et managers', icon: UsersRound, roles: ['rh'] },
    { to: '/conformite', label: 'Conformité', icon: ShieldCheck, roles: ['rh', 'paie'] },
  ] },
  { id: 'paie', label: 'Paie et rémunération', icon: Wallet, items: [
    { to: '/paie/variables', label: 'Variables du mois', icon: SlidersHorizontal, roles: ['paie', 'rh'] },
    { to: '/paie/ajustements', label: 'Prêts et régularisations', icon: Banknote, roles: ['paie', 'rh'] },
    { to: '/paie', label: 'Traitements de paie', icon: Wallet, roles: ['paie', 'rh'], keywords: 'calcul bulletins salaire' },
    { to: '/paie/gouvernance', label: 'Contrôle et clôture', icon: LockKeyhole, roles: ['paie', 'rh'] },
    { to: '/etats', label: 'États légaux et cotisations', icon: FileSpreadsheet, roles: ['paie', 'rh'], keywords: 'ipres css cfce ir trimf brs ipm livre de paie déclaration écritures comptables' },
    { to: '/paie/simulateur', label: 'Simulateur net / brut', icon: Calculator, roles: ['paie', 'rh'] },
  ] },
  { id: 'pilotage', label: 'Pilotage et décision', icon: PieChart, items: [
    { to: '/', label: 'Tableau de bord', icon: LayoutDashboard, roles: ['rh', 'paie'], pinned: true },
    { to: '/pilotage', label: 'Pilotage RH', icon: PieChart, roles: ['rh', 'paie'] },
    { to: '/equipes/organigramme', label: 'Organigramme global', icon: Network, roles: ['rh', 'paie'] },
    { to: '/equipes/simulation', label: 'Simulation d’organisation', icon: Network, roles: ['rh'] },
  ] },
  { id: 'config', label: 'Configuration', icon: Cog, items: [
    { to: '/parametres', label: 'Paramètres et comptes', icon: Settings, roles: ['rh', 'paie'], withoutRole: true },
    { to: '/modules', label: 'Modules métiers', icon: Blocks, roles: ['rh', 'paie'] },
    { to: '/journal', label: 'Journal des modifications', icon: History, roles: ['rh'] },
  ] },
]

export function visibleItems(space: NavSpace, can: (...r: Role[]) => boolean, roles: Role[]): NavItem[] {
  return space.items.filter((i) => !i.roles || can(...i.roles) || (i.withoutRole && roles.length === 0))
}

export const matches = (item: NavItem, pathname: string) =>
  item.to === '/' ? pathname === '/' : pathname === item.to || pathname.startsWith(item.to + '/')

/** Rôles requis pour une route du menu (union si plusieurs entrées) : les gardes de route en dérivent. */
export function rolesFor(to: string): Role[] {
  const found = SPACES.flatMap((s) => s.items).filter((i) => i.to === to)
  if (!found.length || found.some((i) => !i.roles)) throw new Error(`Route sans garde dans nav.ts : ${to}`)
  return [...new Set(found.flatMap((i) => i.roles!))]
}
