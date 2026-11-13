import { createColumnHelper } from '@tanstack/react-table'
import { useQuery } from '@tanstack/react-query'
import { ListChecks, UserPlus } from 'lucide-react'
import { useNavigate } from 'react-router-dom'
import { dataApi, unwrap } from '../lib/api'
import { useEmployees } from '../lib/queries'
import { useAuth } from '../lib/auth'
import { date } from '../lib/format'
import { DataTable } from '../components/DataTable'
import { Badge, Button, ErrorNote, PageHeader, Spinner } from '../components/ui'

type Emp = NonNullable<ReturnType<typeof useEmployees>['data']>[number]
const col = createColumnHelper<Emp>()

const columns = [
  col.accessor('employee_number', { header: 'Matricule' }),
  col.accessor((e) => `${e.first_name} ${e.last_name}`, { id: 'name', header: 'Prénom et nom', cell: (c) => <span className="font-medium">{c.getValue()}</span> }),
  col.accessor((e) => e.designation?.name ?? '', { id: 'designation', header: 'Emploi' }),
  col.accessor((e) => e.grade?.code ?? '', { id: 'grade', header: 'Catégorie' }),
  col.accessor((e) => e.grade?.staff_status ?? '', { id: 'staff', header: 'Statut' }),
  col.accessor('employment_type', { header: 'Contrat' }),
  col.accessor('date_of_joining', { header: "Date d'entrée", cell: (c) => date(c.getValue()) }),
  col.accessor('contract_end', { header: 'Fin de contrat', cell: (c) => <ContractEnd value={c.getValue()} /> }),
  col.accessor('status', { header: 'État', cell: (c) => <Badge value={c.getValue()} /> }),
]

export default function EmployeesPage() {
  const q = useEmployees()
  const nav = useNavigate()
  const { can } = useAuth()
  // saisies mises en attente par l'utilisateur (l'administrateur voit toutes les saisies)
  const drafts = useQuery({
    queryKey: ['employee_drafts', 'count'],
    enabled: can('rh'),
    queryFn: async () => unwrap(await dataApi.from('employee_drafts').select('id').limit(200)).length,
  }).data ?? 0
  return (
    <>
      <PageHeader
        title="Salariés"
        description="Fiches du personnel : identité, contrat, catégorie conventionnelle et situation familiale."
        actions={can('rh') && (
          <>
            <Button icon={<ListChecks className="h-4 w-4" />} onClick={() => nav('/salaries/en-cours')}>Saisies en cours{drafts > 0 ? ` (${drafts})` : ''}</Button>
            <Button variant="primary" icon={<UserPlus className="h-4 w-4" />} onClick={() => nav('/salaries/nouveau')}>Nouveau salarié</Button>
          </>
        )}
      />
      <ErrorNote error={q.error} />
      {q.isLoading ? <Spinner /> : (
        <DataTable data={q.data ?? []} columns={columns} searchPlaceholder="Nom, matricule, emploi…" exportName="salaries" onRowClick={(e) => nav(`/salaries/${e.id}`)}
          toolbar={
            <span className="hidden items-center gap-2 text-xs text-ink-soft lg:inline-flex" aria-label="Légende des fins de contrat">
              Fin de contrat :
              <span className={`rounded border px-1.5 py-0.5 ${TONE.past}`}>dépassée</span>
              <span className={`rounded border px-1.5 py-0.5 ${TONE.soon}`}>moins d’un an</span>
              <span className={`rounded border px-1.5 py-0.5 ${TONE.later}`}>plus d’un an</span>
            </span>
          } />
      )}
    </>
  )
}

const TONE = {
  past: 'border-signal/40 bg-signal-light text-signal',
  soon: 'border-phosphate/60 bg-phosphate-light text-ink',
  later: 'border-river/30 bg-river-light text-river-dark',
}

/** Date de fin de contrat encadrée : rouge si dépassée, jaune à moins d'un an, vert au-delà. */
function ContractEnd({ value }: { value: string | null }) {
  if (!value) return <span className="text-ink-muted">—</span>
  const today = new Date().toISOString().slice(0, 10)
  const inOneYear = new Date()
  inOneYear.setFullYear(inOneYear.getFullYear() + 1)
  const tone = value < today ? 'past' : value <= inOneYear.toISOString().slice(0, 10) ? 'soon' : 'later'
  const days = Math.round((Date.parse(value) - Date.parse(today)) / 86_400_000)
  const hint = tone === 'past' ? `Contrat échu depuis ${-days} jour(s)` : `Échéance dans ${days} jour(s)`
  return (
    <span title={hint} className={`inline-flex items-center rounded border px-1.5 py-0.5 text-xs font-medium tabular-nums ${TONE[tone]}`}>
      {date(value)}
    </span>
  )
}
