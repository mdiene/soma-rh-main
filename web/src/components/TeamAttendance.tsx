import { useQuery } from '@tanstack/react-query'
import { dataApi, unwrap, type ApiClient } from '../lib/api'
import type { TeamMember } from './TeamCalendar'

/** Anomalies de présence de l'équipe sur les 30 derniers jours : absences, maladie, heures supplémentaires. */

const db = dataApi as unknown as ApiClient
type Att = { employee_id: string; attendance_date: string; status: string; absence_hours: number; overtime_15: number; overtime_40: number; overtime_60: number; overtime_100: number }
const iso = (d: Date) => d.toISOString().slice(0, 10)
const SEUIL_ABSENCES = 3 // absences non justifiées sur 30 jours
const SEUIL_HS = 20 // heures supplémentaires sur 30 jours

export function TeamAttendance({ members }: { members: TeamMember[] }) {
  const ids = members.map((m) => m.id)
  const from = iso(new Date(Date.now() - 30 * 86400000))
  const att = useQuery({
    queryKey: ['team_attendance', ids, from],
    enabled: ids.length > 0,
    queryFn: async () => unwrap(await db.from('attendance')
      .select('employee_id, attendance_date, status, absence_hours, overtime_15, overtime_40, overtime_60, overtime_100')
      .in('employee_id', ids).gte('attendance_date', from)) as Att[],
  })

  const lines = members.map((m) => {
    const rows = (att.data ?? []).filter((r) => r.employee_id === m.id)
    const absences = rows.filter((r) => r.status === 'Absent').length
    const maladie = rows.filter((r) => r.status === 'Maladie').length
    const hs = rows.reduce((s, r) => s + Number(r.overtime_15) + Number(r.overtime_40) + Number(r.overtime_60) + Number(r.overtime_100), 0)
    return { m, absences, maladie, hs }
  })

  return (
    <section className="panel mb-6" aria-label="Présence de l’équipe">
      <div className="border-b border-line px-4 py-3">
        <h2 className="text-base">Présence</h2>
        <p className="text-xs text-ink-muted">30 derniers jours. Orange : {SEUIL_ABSENCES} absences non justifiées ou plus, ou {SEUIL_HS} h supplémentaires ou plus.</p>
      </div>
      {att.isLoading ? <p className="p-4 text-sm text-ink-muted">Chargement…</p>
        : att.error ? <p role="alert" className="p-4 text-sm text-red-700">{(att.error as Error).message}</p> : (
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b border-line text-left text-xs text-ink-muted">
                  <th className="px-4 py-2 font-semibold" scope="col">Salarié</th>
                  <th className="px-3 py-2 text-right font-semibold" scope="col">Absences</th>
                  <th className="px-3 py-2 text-right font-semibold" scope="col">Maladie</th>
                  <th className="px-3 py-2 text-right font-semibold" scope="col">H. sup.</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-line/70">
                {lines.map(({ m, absences, maladie, hs }) => (
                  <tr key={m.id}>
                    <th scope="row" className="px-4 py-2 text-left font-medium">{m.name}</th>
                    <td className={`px-3 py-2 text-right tabular-nums ${absences >= SEUIL_ABSENCES ? 'font-semibold text-amber-700' : ''}`}>{absences}</td>
                    <td className="px-3 py-2 text-right tabular-nums">{maladie}</td>
                    <td className={`px-3 py-2 text-right tabular-nums ${hs >= SEUIL_HS ? 'font-semibold text-amber-700' : ''}`}>{hs.toLocaleString('fr-FR', { maximumFractionDigits: 1 })}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
    </section>
  )
}
