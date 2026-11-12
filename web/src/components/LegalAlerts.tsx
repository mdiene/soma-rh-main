import { useQuery } from '@tanstack/react-query'
import { Link } from 'react-router-dom'
import { dataApi, unwrap } from '../lib/api'
import { useAuth } from '../lib/auth'
import { Section } from './ui'

type Alert = { code: string; severity: 'erreur' | 'alerte' | 'info'; employee_id: string | null; employee_number: string | null; employee_name: string; due_date: string | null; message: string }

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
  const { can } = useAuth()
  const q = useQuery({
    queryKey: ['legal_alerts'],
    queryFn: async () => {
      const legal = unwrap(await dataApi.rpc('legal_alerts', { p_horizon_days: 30 })) as Alert[]
      // Demandes d'accès par téléphone : réservées à l'administrateur, ajoutées à la même liste
      const phone = can('admin') ? (unwrap(await dataApi.rpc('phone_access_alerts')) as Alert[]) : []
      // Verrouillages de connexion des dernières 24 h (RPR-03) : réservés à l'administrateur
      const security = can('admin') ? (unwrap(await dataApi.rpc('security_alerts')) as Alert[]) : []
      return [...phone, ...security, ...legal]
    },
  })
  const sorted = [...(q.data ?? [])].sort((a, b) => ORDER[a.severity] - ORDER[b.severity] || (a.due_date ?? '9999').localeCompare(b.due_date ?? '9999'))
  return (
    <Section title="Alertes réglementaires">
      <p className="mb-3 text-xs text-ink-muted">Fins de CDD, salaires sous le SMIG paramétré, pièces d'identité à renouveler (horizon de 30 jours).</p>
      {q.isLoading ? <p className="text-sm text-ink-muted">Chargement…</p>
        : q.error ? <p role="alert" className="text-sm text-signal">Alertes indisponibles : {(q.error as Error).message}</p>
        : sorted.length === 0 ? <p className="text-sm text-ink-soft">Aucune alerte : contrats, salaires et pièces sont à jour.</p>
        : (
          <ul className="divide-y divide-line text-sm">
            {sorted.map((a) => (
              <li key={a.code + a.employee_id + a.employee_name} className="flex flex-wrap items-center gap-2 py-2">
                <span className={`rounded border px-2 py-0.5 text-xs font-medium ${TONE[a.severity]}`}>{LABEL[a.severity]}</span>
                {a.code === 'login_lock'
                  ? <Link to="/parametres?onglet=journal" className="font-medium text-river hover:underline">{a.employee_name} — ouvrir le journal</Link>
                  : a.code.startsWith('phone_access')
                  ? <Link to="/parametres?onglet=acces" className="font-medium text-river hover:underline">{a.employee_name} — ouvrir l'écran d'autorisation</Link>
                  : a.employee_id
                  ? <Link to={`/salaries/${a.employee_id}`} className="font-medium text-river hover:underline">{a.employee_number} {a.employee_name}</Link>
                  : <Link to="/parametres" className="font-medium text-river hover:underline">{a.employee_name} (société)</Link>}
                <span className="text-ink-soft">{a.message}</span>
              </li>
            ))}
          </ul>
        )}
    </Section>
  )
}
