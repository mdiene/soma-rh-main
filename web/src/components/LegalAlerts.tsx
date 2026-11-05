import { useQuery } from '@tanstack/react-query'
import { Link } from 'react-router-dom'
import { dataApi, unwrap } from '../lib/api'
import { Section } from './ui'

type Alert = { code: string; severity: 'erreur' | 'alerte' | 'info'; employee_id: string; employee_number: string; employee_name: string; due_date: string; message: string }

const TONE: Record<Alert['severity'], string> = {
  erreur: 'border-signal bg-signal-light text-signal',
  alerte: 'border-phosphate bg-phosphate-light text-ink',
  info: 'border-line bg-paper text-ink-soft',
}
const LABEL: Record<Alert['severity'], string> = { erreur: 'À traiter', alerte: 'À surveiller', info: 'Information' }
const ORDER = { erreur: 0, alerte: 1, info: 2 } as const

/**
 * Alertes réglementaires pour les RH et la paie : fins de CDD, salaire sous le SMIG paramétré, pièces d'identité expirées.
 * Les données viennent de la fonction legal_alerts (seuils lus dans les paramètres en vigueur, jamais codés ici).
 */
export function LegalAlerts() {
  const q = useQuery({
    queryKey: ['legal_alerts'],
    queryFn: async () => unwrap(await dataApi.rpc('legal_alerts', { p_horizon_days: 30 })) as Alert[],
  })
  const sorted = [...(q.data ?? [])].sort((a, b) => ORDER[a.severity] - ORDER[b.severity] || a.due_date.localeCompare(b.due_date))
  return (
    <Section title="Alertes réglementaires">
      <p className="mb-3 text-xs text-ink-muted">Fins de CDD, salaires sous le SMIG paramétré, pièces d'identité à renouveler (horizon de 30 jours).</p>
      {q.isLoading ? <p className="text-sm text-ink-muted">Chargement…</p>
        : q.error ? <p role="alert" className="text-sm text-signal">Alertes indisponibles : {(q.error as Error).message}</p>
        : sorted.length === 0 ? <p className="text-sm text-ink-soft">Aucune alerte : contrats, salaires et pièces sont à jour.</p>
        : (
          <ul className="divide-y divide-line text-sm">
            {sorted.map((a) => (
              <li key={a.code + a.employee_id} className="flex flex-wrap items-center gap-2 py-2">
                <span className={`rounded border px-2 py-0.5 text-xs font-medium ${TONE[a.severity]}`}>{LABEL[a.severity]}</span>
                <Link to={`/salaries/${a.employee_id}`} className="font-medium text-river hover:underline">{a.employee_number} {a.employee_name}</Link>
                <span className="text-ink-soft">{a.message}</span>
              </li>
            ))}
          </ul>
        )}
    </Section>
  )
}
