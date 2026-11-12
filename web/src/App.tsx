import { lazy, Suspense, type ReactNode } from 'react'
import { Navigate, Route, Routes } from 'react-router-dom'
import { rolesFor } from './lib/nav'
import { Layout } from './components/Layout'
import { Spinner } from './components/ui'
import { useAuth, type Role } from './lib/auth'
import LoginPage from './pages/LoginPage'

// Chaque écran est chargé à la demande pour alléger le premier affichage.
const DashboardPage = lazy(() => import('./pages/DashboardPage'))
const EmployeesPage = lazy(() => import('./pages/EmployeesPage'))
const EmployeeDetailPage = lazy(() => import('./pages/EmployeeDetailPage'))
const ModulesPage = lazy(() => import('./pages/ModulesPage'))
const LeavesPage = lazy(() => import('./pages/LeavesPage'))
const AttendancePage = lazy(() => import('./pages/AttendancePage'))
const PlanningPage = lazy(() => import('./pages/PlanningPage'))
const PayrollInputsPage = lazy(() => import('./pages/PayrollInputsPage'))
const PayrollEntriesPage = lazy(() => import('./pages/PayrollEntriesPage'))
const PayrollGovernancePage = lazy(() => import('./pages/PayrollGovernancePage'))
const PayrollEntryPage = lazy(() => import('./pages/PayrollEntryPage'))
const PayrollClosingReportPage = lazy(() => import('./pages/PayrollClosingReportPage'))
const PayrollAdjustmentsPage = lazy(() => import('./pages/PayrollAdjustmentsPage'))
const SalarySlipPage = lazy(() => import('./pages/SalarySlipPage'))
const PrintSlipsPage = lazy(() => import('./pages/PrintSlipsPage'))
const PayrollBookPrintPage = lazy(() => import('./pages/PayrollBookPrintPage'))
const ComplianceCenterPage = lazy(() => import('./pages/ComplianceCenterPage'))
const JournalPage = lazy(() => import('./pages/JournalPage'))
const MySpacePage = lazy(() => import('./pages/MySpacePage'))
const RequestsPage = lazy(() => import('./pages/RequestsPage'))
const PayrollPaymentsPage = lazy(() => import('./pages/PayrollPaymentsPage'))
const PayrollContributionsPage = lazy(() => import('./pages/PayrollContributionsPage'))
const PilotagePage = lazy(() => import('./pages/PilotagePage'))
const SimulatorPage = lazy(() => import('./pages/SimulatorPage'))
const ReportsPage = lazy(() => import('./pages/ReportsPage'))
const SettingsPage = lazy(() => import('./pages/SettingsPage'))
const MySlipsPage = lazy(() => import('./pages/MySlipsPage'))
const ManagerPage = lazy(() => import('./pages/ManagerPage'))
const ManagerAssignmentsPage = lazy(() => import('./pages/ManagerAssignmentsPage'))
const OrganigrammePage = lazy(() => import('./pages/OrganigrammePage'))
const ReorgSimulationPage = lazy(() => import('./pages/ReorgSimulationPage'))
const EmployeeDocumentsPage = lazy(() => import('./pages/EmployeeDocumentsPage'))

/**
 * Accès aux écrans de gestion : réservé aux rôles RH / paie (l'administrateur a tous les droits).
 * Un salarié sans ces rôles est renvoyé vers ses propres bulletins ; la RLS protège les données
 * dans tous les cas, ce garde évite d'afficher des écrans vides ou trompeurs.
 */
function RoleGuard({ roles, to, children }: { roles?: Role[]; to?: string; children: ReactNode }) {
  const { can } = useAuth()
  return can(...(roles ?? rolesFor(to!))) ? <>{children}</> : <Navigate to="/" replace />
}

/** Accueil : tableau de bord pour la gestion, bulletins personnels pour un salarié. */
function Home() {
  const { can, roles } = useAuth()
  if (!can('rh', 'paie') && roles.includes('salarie')) return <Navigate to="/mon-espace" replace />
  if (!can('rh', 'paie') && roles.includes('manager')) return <Navigate to="/mon-equipe" replace />
  return <DashboardPage />
}

const staff: Role[] = ['rh', 'paie']

export default function App() {
  const { session, loading, roles } = useAuth()
  if (loading) return <div className="p-10"><Spinner /></div>
  if (!session) {
    return (
      <Routes>
        <Route path="*" element={<LoginPage />} />
      </Routes>
    )
  }
  return (
    <Suspense fallback={<div className="p-10"><Spinner /></div>}>
    <Routes>
      <Route element={<Layout />}>
        <Route index element={<Home />} />
        <Route path="salaries" element={<RoleGuard to="/salaries"><EmployeesPage /></RoleGuard>} />
        <Route path="salaries/:id" element={<RoleGuard roles={staff}><EmployeeDetailPage /></RoleGuard>} />
        <Route path="dossiers-salaries" element={<RoleGuard to="/dossiers-salaries"><EmployeeDocumentsPage /></RoleGuard>} />
        <Route path="conges" element={<LeavesPage />} />
        <Route path="presences" element={<RoleGuard to="/presences"><AttendancePage /></RoleGuard>} />
        <Route path="planning" element={<RoleGuard to="/planning"><PlanningPage /></RoleGuard>} />
        <Route path="pilotage" element={<RoleGuard to="/pilotage"><PilotagePage /></RoleGuard>} />
        <Route path="paie" element={<RoleGuard to="/paie"><PayrollEntriesPage /></RoleGuard>} />
        <Route path="paie/cotisations" element={<RoleGuard to="/paie/cotisations"><PayrollContributionsPage /></RoleGuard>} />
        <Route path="paie/gouvernance"element={<RoleGuard to="/paie/gouvernance"><PayrollGovernancePage /></RoleGuard>} />
        <Route path="paie/variables" element={<RoleGuard to="/paie/variables"><PayrollInputsPage /></RoleGuard>} />
        <Route path="paie/ajustements" element={<RoleGuard to="/paie/ajustements"><PayrollAdjustmentsPage /></RoleGuard>} />
        <Route path="paie/simulateur" element={<RoleGuard to="/paie/simulateur"><SimulatorPage /></RoleGuard>} />
        <Route path="paie/:id" element={<RoleGuard roles={staff}><PayrollEntryPage /></RoleGuard>} />
        <Route path="paie/:id/imprimer" element={<RoleGuard roles={staff}><PrintSlipsPage /></RoleGuard>} />
        <Route path="paie/:id/paiements" element={<RoleGuard roles={staff}><PayrollPaymentsPage /></RoleGuard>} />
        <Route path="paie/:id/livre" element={<RoleGuard roles={staff}><PayrollBookPrintPage /></RoleGuard>} />
        <Route path="paie/:id/rapport" element={<RoleGuard roles={staff}><PayrollClosingReportPage /></RoleGuard>} />
        {/* bulletins : la RLS ne renvoie à un salarié que ses propres bulletins validés */}
        <Route path="bulletins/imprimer" element={<PrintSlipsPage />} />
        <Route path="bulletins/:id" element={<SalarySlipPage />} />
        <Route path="etats" element={<RoleGuard to="/etats"><ReportsPage /></RoleGuard>} />
        <Route path="conformite" element={<Navigate to="/centre-conformite" replace />} />
        <Route path="centre-conformite" element={<RoleGuard to="/centre-conformite"><ComplianceCenterPage /></RoleGuard>} />
        <Route path="modules" element={<RoleGuard to="/modules"><ModulesPage /></RoleGuard>} />
        <Route path="journal" element={<RoleGuard to="/journal"><JournalPage /></RoleGuard>} />
        <Route path="parametres" element={roles.length === 0 ? <SettingsPage /> : <RoleGuard roles={staff}><SettingsPage /></RoleGuard>} />
        <Route path="mon-espace" element={<MySpacePage />} />
        <Route path="mon-equipe" element={<RoleGuard to="/mon-equipe"><ManagerPage /></RoleGuard>} />
        <Route path="equipes" element={<RoleGuard to="/equipes"><ManagerAssignmentsPage /></RoleGuard>} />
        {/* organigramme : visible par tout utilisateur connecté (la base limite le contenu selon le rôle) */}
        <Route path="equipes/organigramme" element={<OrganigrammePage />} />
        <Route path="equipes/simulation" element={<RoleGuard to="/equipes/simulation"><ReorgSimulationPage /></RoleGuard>} />
        <Route path="demandes" element={<RoleGuard to="/demandes"><RequestsPage /></RoleGuard>} />
        <Route path="mes-bulletins" element={<MySlipsPage />} />
        <Route path="*" element={<Navigate to="/" replace />} />
      </Route>
    </Routes>
    </Suspense>
  )
}
