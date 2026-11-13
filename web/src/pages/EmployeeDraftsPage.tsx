import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { PlayCircle, Trash2 } from 'lucide-react'
import { useState } from 'react'
import { Link } from 'react-router-dom'
import { dataApi, unwrap } from '../lib/api'
import { useAuth } from '../lib/auth'
import { draftSummary, stepsFor, type Draft } from '../lib/employeeWizard'
import { Button, Empty, ErrorNote, PageHeader, Spinner } from '../components/ui'

type Saved = { draft?: Draft; withPayroll?: boolean; index?: number }

/** Salariés dont la saisie est en attente : avancement, points manquants, reprise en un clic. */
export default function EmployeeDraftsPage() {
  const { can } = useAuth()
  const qc = useQueryClient()
  const steps = stepsFor(can('paie')).map((s) => s.id)
  const [confirm, setConfirm] = useState<string | null>(null)
  const q = useQuery({
    queryKey: ['employee_drafts'],
    queryFn: async () => unwrap(await dataApi.from('employee_drafts').select('id, data, created_at, updated_at').order('updated_at', { ascending: false })),
  })
  const remove = useMutation({
    mutationFn: async (id: string) => unwrap(await dataApi.from('employee_drafts').delete().eq('id', id).select('id')),
    onSuccess: () => { setConfirm(null); qc.invalidateQueries({ queryKey: ['employee_drafts'] }) },
  })
  const rows = q.data ?? []

  return (
    <>
      <PageHeader
        title="Saisies en cours"
        description="Salariés dont la création a été mise en attente. Cliquez sur une saisie pour la reprendre là où vous l’avez laissée ; aucune fiche n’existe tant que la saisie n’est pas terminée."
        actions={<Link to="/salaries/nouveau" className="inline-flex items-center rounded bg-river px-3 py-2 text-sm font-medium text-white hover:bg-river-dark">Nouveau salarié</Link>}
      />
      <ErrorNote error={q.error || remove.error} />
      {q.isLoading ? <Spinner /> : rows.length === 0 ? (
        <Empty title="Aucune saisie en attente">Dans l’assistant de saisie, le bouton « Mettre en attente » enregistre la saisie pour la reprendre plus tard.</Empty>
      ) : (
        <ul className="space-y-3" aria-label="Saisies en attente">
          {rows.map((r) => {
            const sd = (r.data ?? {}) as unknown as Saved
            const sum = draftSummary(sd.draft ?? {}, steps, { payrollRequested: can('paie') && (sd.withPayroll ?? true) })
            const blocking = sum.missing.filter((m) => m.blocking)
            const others = sum.missing.filter((m) => !m.blocking)
            const stepTitle = (id: string) => stepsFor(true).find((s) => s.id === id)?.title ?? id
            const resume = `/salaries/nouveau?brouillon=${encodeURIComponent(r.id)}`
            return (
              <li key={r.id} className="panel p-4">
                <div className="flex flex-wrap items-start justify-between gap-3">
                  <div className="min-w-0">
                    <Link to={resume} className="text-base font-semibold text-river hover:underline">{sum.label}</Link>
                    <p className="text-xs text-ink-muted">Dernière modification le {new Date(r.updated_at).toLocaleString('fr-FR')}</p>
                  </div>
                  <div className="flex gap-2">
                    <Link to={resume} className="inline-flex items-center gap-1.5 rounded bg-river px-3 py-1.5 text-sm font-medium text-white hover:bg-river-dark"><PlayCircle className="h-4 w-4" aria-hidden />Continuer la saisie</Link>
                    {confirm === r.id
                      ? <Button variant="danger" loading={remove.isPending} onClick={() => remove.mutate(r.id)}>Confirmer la suppression</Button>
                      : <Button variant="ghost" icon={<Trash2 className="h-4 w-4" />} aria-label={`Supprimer la saisie de ${sum.label}`} onClick={() => setConfirm(r.id)}>Supprimer</Button>}
                  </div>
                </div>
                <div className="mt-3 flex items-center gap-3">
                  <div className="h-2 flex-1 overflow-hidden rounded bg-line" role="progressbar" aria-label={`Avancement de la saisie de ${sum.label}`} aria-valuemin={0} aria-valuemax={100} aria-valuenow={sum.pct}>
                    <div className="h-full bg-river" style={{ width: `${sum.pct}%` }} />
                  </div>
                  <span className="w-12 text-right text-sm font-medium tabular-nums">{sum.pct} %</span>
                </div>
                {sum.missing.length === 0 ? (
                  <p className="mt-2 text-sm text-river-dark">Saisie complète : il ne reste qu’à créer le salarié depuis l’étape « Revue et sauvegarde ».</p>
                ) : (
                  <div className="mt-2 text-sm">
                    <p className="font-medium">Points à déterminer</p>
                    <ul className="mt-1 list-disc space-y-0.5 pl-5">
                      {blocking.map((m) => <li key={m.step + m.message} className="text-signal"><span className="font-medium">{stepTitle(m.step)} :</span> {m.message}</li>)}
                      {others.slice(0, 4).map((m) => <li key={m.step + m.message} className="text-ink-soft"><span className="font-medium">{stepTitle(m.step)} :</span> {m.message}</li>)}
                    </ul>
                    {others.length > 4 && <p className="mt-1 text-xs text-ink-muted">+ {others.length - 4} autre(s) point(s) à compléter</p>}
                  </div>
                )}
              </li>
            )
          })}
        </ul>
      )}
    </>
  )
}
