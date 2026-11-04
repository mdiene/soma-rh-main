// Phase 7 : chronométrage de bout en bout (jeton réel, RLS comprise) sur le scénario actuellement chargé.
// Usage : node tests/perf/perf.mjs <nom-scenario>  → une ligne JSON par opération, puis un tableau Markdown.
// Chaque opération est mesurée REPS fois ; on retient la médiane et le maximum, en millisecondes.
// Le calcul de paie crée un traitement sur 2025-03 (période de test) puis le supprime.
import { readFileSync } from 'node:fs'
import { execFileSync } from 'node:child_process'

const REPS = 3
const read = (p) => Object.fromEntries(readFileSync(new URL(p, import.meta.url), 'utf8').split(/\r?\n/)
  .filter((l) => /^[A-Z_0-9]+=/.test(l)).map((l) => [l.slice(0, l.indexOf('=')), l.slice(l.indexOf('=') + 1).trim()]))
const env = read('../.env.qa')
const API = env.QA_API_URL
const KEY = read('../../web/.env.local').VITE_API_PUBLIC_KEY
const scenario = process.argv[2] ?? 'inconnu'

const call = async (path, tok, method = 'GET', body) => {
  const t0 = performance.now()
  const r = await fetch(`${API}/rest/v1/${path}`, { method,
    headers: { apikey: KEY, authorization: `Bearer ${tok}`, 'content-type': 'application/json', prefer: 'return=representation' },
    body: body ? JSON.stringify(body) : undefined })
  const text = await r.text()
  return { ms: performance.now() - t0, s: r.status, octets: text.length, b: (() => { try { return JSON.parse(text) } catch { return null } })() }
}
const login = async (r) => (await (await fetch(`${API}/auth/v1/token`, { method: 'POST', headers: { 'content-type': 'application/json' },
  body: JSON.stringify({ email: env[`QA_${r}_EMAIL`], password: env[`QA_${r}_PASSWORD`] }) })).json()).access_token
const psql = (sql) => execFileSync('docker', ['exec', '-i', 'soma-rh-local-postgres-1', 'psql', '-U', 'soma', '-d', 'soma_rh', '-tA', '-q', '-v', 'ON_ERROR_STOP=1'], { input: sql }).toString().trim()
const med = (a) => [...a].sort((x, y) => x - y)[Math.floor(a.length / 2)]

const T = {}
for (const r of ['ADMIN', 'RH', 'PAIE', 'SALARIE']) T[r] = await login(r)
const rows = []
async function mesurer(nom, tok, chemin, { method, body, reps = REPS } = {}) {
  const ms = []; let dernier
  for (let i = 0; i < reps; i++) { dernier = await call(chemin, tok, method, body); ms.push(dernier.ms) }
  const ligne = { scenario, operation: nom, statut: dernier.s, mediane_ms: Math.round(med(ms)), max_ms: Math.round(Math.max(...ms)), ko: Math.round(dernier.octets / 1024) }
  rows.push(ligne); console.log(JSON.stringify(ligne))
  return dernier
}

const nb = psql(`select (select count(*) from employees), (select count(*) from salary_slips), (select count(*) from attendance), (select count(*) from leave_applications)`)
console.log(JSON.stringify({ scenario, tailles: nb }))

// ---- lectures ----
await mesurer('Liste des salariés (admin, toutes colonnes)', T.ADMIN, 'employees?select=*&order=last_name')
await mesurer('Liste des salariés (admin, page de 50)', T.ADMIN, 'employees?select=id,employee_number,first_name,last_name,status&order=last_name&limit=50')
await mesurer('Salarié : son propre dossier (RLS)', T.SALARIE, 'employees?select=*')
await mesurer('Présences du mois (planning)', T.RH, 'attendance?attendance_date=gte.2026-10-01&attendance_date=lte.2026-10-31&select=*')
await mesurer('Demandes de congé', T.RH, 'leave_applications?select=*')
await mesurer('Soldes de congés (vue)', T.RH, 'v_leave_balances?select=*')

// ---- analyses ----
await mesurer('Tableau de bord RH', T.RH, 'rpc/hr_dashboard', { method: 'POST', body: {} })
await mesurer('Analyses RH (12 mois)', T.RH, 'rpc/hr_analytics', { method: 'POST', body: { p_months: 12 } })
await mesurer('Analyses RH (36 mois)', T.RH, 'rpc/hr_analytics', { method: 'POST', body: { p_months: 36 } })
await mesurer('Tableau de bord annuel', T.RH, 'rpc/hr_dashboard_year', { method: 'POST', body: { p_year: 2026 } })

// ---- paie : calcul, livre, états ----
psql(`insert into salary_structure_assignments (employee_id, structure_id, from_date, base_salary, transport_mode, notes)
  select e.id, (select id from salary_structures limit 1), date '2024-01-01', 100000, 'Aucun', 'QA-PERF'
  from employees e where e.status = 'Active' and not exists (select 1 from salary_structure_assignments a where a.employee_id = e.id and a.from_date <= date '2025-03-01')`)
const company = (await call('companies?select=id', T.ADMIN)).b[0].id
const ins = await call('payroll_entries', T.PAIE, 'POST', { company_id: company, period_start: '2025-03-01', period_end: '2025-03-31', payment_mode: 'espèces' })
if (ins.s !== 201) throw new Error(`création du traitement : ${ins.s} ${JSON.stringify(ins.b)}`)
const id = ins.b[0].id
try {
  const calc = await mesurer('Calcul de la paie du mois (run_payroll_entry)', T.PAIE, 'rpc/run_payroll_entry', { method: 'POST', body: { p_payroll_entry_id: id }, reps: 2 })
  const bulletins = psql(`select count(*) from salary_slips where payroll_entry_id = '${id}'`)
  console.log(JSON.stringify({ scenario, bulletins_calcules: bulletins, calcul_ms: calc.ms }))
  await mesurer('Livre de paie (v_payroll_register)', T.PAIE, `v_payroll_register?payroll_entry_id=eq.${id}&select=*`)
  await mesurer('Bulletins du traitement', T.PAIE, `salary_slips?payroll_entry_id=eq.${id}&select=*`)
  await mesurer('Rapport de clôture', T.PAIE, 'rpc/payroll_closing_report', { method: 'POST', body: { p_payroll_entry_id: id } })
  await mesurer('Récapitulatif des paiements', T.PAIE, 'rpc/payment_summary', { method: 'POST', body: { p_payroll_entry_id: id } })
  await mesurer('Journal comptable (export)', T.PAIE, 'rpc/export_payroll_journal', { method: 'POST', body: { p_payroll_entry_id: id } })
  await mesurer('Contrôles avant validation', T.PAIE, 'rpc/payroll_entry_checks', { method: 'POST', body: { p_payroll_entry_id: id } })
} finally {
  if (process.env.PERF_KEEP) { console.log(JSON.stringify({ traitement_conserve: id })); } else {
  const del = await call('rpc/delete_payroll_entry', T.ADMIN, 'POST', { p_payroll_entry_id: id })
  if (del.s >= 300) console.error(`⚠ suppression du traitement de test impossible (${del.s}) : ${JSON.stringify(del.b)}`)
  psql(`delete from salary_structure_assignments where notes = 'QA-PERF'`)
  }
}

console.log(`\n| Opération | Statut | Médiane (ms) | Max (ms) | Ko |\n|---|---|---|---|---|`)
for (const r of rows) console.log(`| ${r.operation} | ${r.statut} | ${r.mediane_ms} | ${r.max_ms} | ${r.ko} |`)
