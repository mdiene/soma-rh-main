// Workflow de paie et droits des fonctions, avec le jeton de chaque rôle (invariants I3, I4, I15, I11).
// Prérequis : stack Docker, un scénario chargé (qa-reset-scenario.ps1) et les comptes (qa-create-users.ps1).
// Lancer : node --test --test-concurrency=1 tests/api/workflow.test.mjs
// Chaque test crée son traitement de paie et le supprime ensuite (voies légitimes de l'administrateur).
// Périodes de test : 2025-03 (passé, sans traitement existant), 2025-04, 2027-12 (futur).
import { test, before, after } from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { execFileSync } from 'node:child_process'

const read = (p) => Object.fromEntries(readFileSync(new URL(p, import.meta.url), 'utf8').split(/\r?\n/)
  .filter((l) => /^[A-Z_0-9]+=/.test(l)).map((l) => [l.slice(0, l.indexOf('=')), l.slice(l.indexOf('=') + 1).trim()]))
const env = read('../.env.qa')
const API = env.QA_API_URL
const KEY = read('../../web/.env.local').VITE_API_PUBLIC_KEY

const login = async (r) => (await (await fetch(`${API}/auth/v1/token?grant_type=password`, {
  method: 'POST', headers: { 'content-type': 'application/json' },
  body: JSON.stringify({ email: env[`QA_${r}_EMAIL`], password: env[`QA_${r}_PASSWORD`] }) })).json()).access_token
const call = async (path, tok, method = 'GET', body) => {
  const r = await fetch(`${API}/rest/v1/${path}`, { method,
    headers: { apikey: KEY, ...(tok ? { authorization: `Bearer ${tok}` } : {}), 'content-type': 'application/json', prefer: 'return=representation' },
    body: body ? JSON.stringify(body) : undefined })
  let b = null; try { b = await r.json() } catch { /* corps vide */ }
  return { s: r.status, b, msg: b?.message ?? '' }
}
const T = {}
let COMPANY
before(async () => {
  purger() // état de départ propre même après une exécution interrompue
  preparer()
  for (const r of ['ADMIN', 'RH', 'PAIE', 'MANAGER', 'SALARIE']) T[r] = await login(r)
  COMPANY = (await call('companies?select=id', T.ADMIN)).b[0].id
})

const transition = (id, statut, tok, motif) =>
  call('rpc/transition_payroll_entry', tok, 'POST', { p_payroll_entry_id: id, p_target_status: statut, p_reason: motif ?? null })
const statutDe = async (id) => (await call(`payroll_entries?id=eq.${id}&select=status`, T.ADMIN)).b[0].status

/**
 * Purge les traitements des périodes de test (2025-03, 2025-04, 2027-12) et leurs lignes liées.
 * Voie directe (superutilisateur local, déclencheurs neutralisés) : la voie légitime est impossible tant que des
 * mois postérieurs sont validés (« remettez d'abord les mois suivants »). Borné aux périodes de test uniquement.
 */
function purger() {
  const P = "('2025-03-01','2025-04-01','2027-12-01')"
  const sql = `begin; set local session_replication_role = replica;
    create temp table e as select id from public.payroll_entries where period_start in ${P};
    delete from public.salary_slip_details where salary_slip_id in (select id from public.salary_slips where payroll_entry_id in (select id from e));
    delete from public.salary_payments where slip_id in (select id from public.salary_slips where payroll_entry_id in (select id from e));
    delete from public.salary_slips where payroll_entry_id in (select id from e);
    delete from public.payroll_anomalies where payroll_entry_id in (select id from e);
    delete from public.payroll_approvals where payroll_entry_id in (select id from e);
    delete from public.payroll_snapshots where payroll_entry_id in (select id from e);
    update public.audit_events set payroll_entry_id = null where payroll_entry_id in (select id from e);
    delete from public.payroll_entries where id in (select id from e);
    delete from public.payroll_periods p where p.period_start in ${P} and not exists (select 1 from public.payroll_entries x where x.period_id = p.id);
    delete from public.salary_structure_assignments where notes = 'QA-TEST-WORKFLOW';
    commit;`
  execFileSync('docker', ['exec', '-i', 'soma-rh-local-postgres-1', 'psql', '-U', 'soma', '-d', 'soma_rh', '-q', '-v', 'ON_ERROR_STOP=1'], { input: sql })
}
const nettoyer = async () => { purger(); preparer() }  // entre deux tests : état propre, structures de test conservées
after(() => purger())                                  // fin de campagne : aucune trace des structures de test

/**
 * Donne une structure salariale (datée de 2024, donc antérieure et sans effet sur les périodes de 2026) aux
 * salariés actifs qui n'en ont pas en mars 2025 : sans cela, les contrôles bloquants « sans_bulletin »
 * empêchent légitimement toute validation. Marquée QA-TEST-WORKFLOW et supprimée par purger().
 */
function preparer() {
  const sql = `insert into public.salary_structure_assignments (employee_id, structure_id, from_date, base_salary, transport_mode, notes)
    select e.id, (select id from public.salary_structures limit 1), date '2024-01-01', 100000, 'Aucun', 'QA-TEST-WORKFLOW'
    from public.employees e where e.status = 'Active'
      and not exists (select 1 from public.salary_structure_assignments a where a.employee_id = e.id and a.from_date <= date '2025-03-01');`
  execFileSync('docker', ['exec', '-i', 'soma-rh-local-postgres-1', 'psql', '-U', 'soma', '-d', 'soma_rh', '-q', '-v', 'ON_ERROR_STOP=1'], { input: sql })
}

/** Crée un traitement par « paie » (le préparateur), le calcule, exécute le test, puis nettoie. */
async function avecTraitement(debut, fin, fn) {
  const ins = await call('payroll_entries', T.PAIE, 'POST', { company_id: COMPANY, period_start: debut, period_end: fin, payment_mode: 'espèces' })
  assert.equal(ins.s, 201, `création : ${ins.msg}`)
  const id = ins.b[0].id
  try {
    assert.equal((await call('rpc/run_payroll_entry', T.PAIE, 'POST', { p_payroll_entry_id: id })).s, 200)
    await fn(id)
  } finally { await nettoyer(id) }
}
const MARS = ['2025-03-01', '2025-03-31']

test('anonyme, salarié et manager ne peuvent ni calculer, ni changer le statut, ni supprimer', async () => {
  await avecTraitement(...MARS, async (id) => {
    for (const [nom, tok] of [['anonyme', null], ['salarié', T.SALARIE], ['manager', T.MANAGER]]) {
      for (const statut of ['En revue', 'Validée', 'Payée', 'Clôturée', 'Annulée']) {
        const r = await transition(id, statut, tok)
        assert.ok(r.s >= 400, `${nom} a pu passer à « ${statut} »`)
      }
      assert.ok((await call('rpc/run_payroll_entry', tok, 'POST', { p_payroll_entry_id: id })).s >= 400, `${nom} a pu calculer`)
      assert.ok((await call('rpc/delete_payroll_entry', tok, 'POST', { p_payroll_entry_id: id })).s >= 400, `${nom} a pu supprimer`)
    }
    assert.equal(await statutDe(id), 'Calculée')
  })
})

test('rh ne peut ni payer, ni clôturer, ni annuler, ni rouvrir ; paie ne peut ni approuver, ni annuler, ni rouvrir', async () => {
  await avecTraitement(...MARS, async (id) => {
    for (const statut of ['Payée', 'Clôturée', 'Annulée', 'Réouverte']) {
      assert.ok((await transition(id, statut, T.RH, 'essai')).s >= 400, `rh a pu passer à « ${statut} »`)
    }
    for (const statut of ['Approuvée', 'Annulée', 'Réouverte']) {
      assert.ok((await transition(id, statut, T.PAIE, 'essai')).s >= 400, `paie a pu passer à « ${statut} »`)
    }
    assert.equal(await statutDe(id), 'Calculée')
  })
})

test('séparation des tâches : le préparateur ne valide pas sa propre paie, une autre personne le peut', async () => {
  await avecTraitement(...MARS, async (id) => {
    const memePersonne = await transition(id, 'Validée', T.PAIE)
    assert.ok(memePersonne.s >= 400 && /séparation/i.test(memePersonne.msg), `attendu un refus de séparation, reçu : ${memePersonne.s} ${memePersonne.msg}`)
    const autre = await transition(id, 'Validée', T.RH)
    assert.equal(autre.s, 200, autre.msg)
    assert.equal(await statutDe(id), 'Validée')
  })
})

test('aucun contournement par UPDATE ou INSERT direct du statut (rh et paie)', async () => {
  await avecTraitement(...MARS, async (id) => {
    for (const [nom, tok] of [['rh', T.RH], ['paie', T.PAIE]]) {
      for (const statut of ['Validée', 'Payée', 'Clôturée', 'Annulée', 'Approuvée', 'Brouillon']) {
        const r = await call(`payroll_entries?id=eq.${id}`, tok, 'PATCH', { status: statut })
        const apres = await statutDe(id)
        assert.equal(apres, 'Calculée', `${nom} a changé le statut en « ${statut} » par UPDATE direct (statut : ${apres}, réponse ${r.s})`)
      }
    }
    const ins = await call('payroll_entries', T.RH, 'POST', { company_id: COMPANY, period_start: '2025-04-01', period_end: '2025-04-30', payment_mode: 'espèces', status: 'Validée' })
    if (ins.s === 201) await nettoyer(ins.b[0].id)
    assert.ok(ins.s >= 400, 'rh a pu créer un traitement directement « Validée »')
  })
})

test('transitions illégales refusées, même pour l\'administrateur', async () => {
  await avecTraitement(...MARS, async (id) => {
    for (const statut of ['Payée', 'Clôturée', 'Approuvée']) {
      const r = await transition(id, statut, T.ADMIN)
      assert.ok(r.s >= 400, `Calculée vers « ${statut} » accepté`)
    }
    assert.equal(await statutDe(id), 'Calculée')
  })
})

test('après validation : recalcul impossible ; le salarié ne voit ses bulletins qu\'une fois la paie validée', async () => {
  await avecTraitement(...MARS, async (id) => {
    const avant = (await call(`salary_slips?payroll_entry_id=eq.${id}&select=id`, T.SALARIE)).b.length
    assert.equal(avant, 0, 'bulletin visible avant validation')
    assert.equal((await transition(id, 'Validée', T.RH)).s, 200)
    const recalcul = await call('rpc/run_payroll_entry', T.PAIE, 'POST', { p_payroll_entry_id: id })
    assert.ok(recalcul.s >= 400 && /recalcul impossible/i.test(recalcul.msg), `recalcul accepté après validation : ${recalcul.msg}`)
    const apres = (await call(`salary_slips?payroll_entry_id=eq.${id}&select=id`, T.SALARIE)).b.length
    assert.ok(apres >= 1, 'le salarié ne voit pas son bulletin après validation')
  })
})

test('un mois futur ne peut pas être validé (administrateur compris)', async () => {
  await avecTraitement('2027-12-01', '2027-12-31', async (id) => {
    for (const [nom, tok] of [['rh', T.RH], ['admin', T.ADMIN]]) {
      const r = await transition(id, 'Validée', tok, 'essai')
      assert.ok(r.s >= 400 && /mois futur/i.test(r.msg), `${nom} : validation d'un mois futur acceptée ou message inattendu (${r.s} ${r.msg})`)
    }
    assert.equal(await statutDe(id), 'Calculée')
  })
})

test('le mois précédent doit être validé d\'abord, sauf pour l\'administrateur', async () => {
  await avecTraitement(...MARS, async () => {
    await avecTraitement('2025-04-01', '2025-04-30', async (avril) => {
      const rh = await transition(avril, 'Validée', T.RH)
      assert.ok(rh.s >= 400 && /mois précédent/i.test(rh.msg), `rh a validé avril sans mars validé (${rh.s} ${rh.msg})`)
      const admin = await transition(avril, 'Validée', T.ADMIN, 'dérogation de test')
      assert.equal(admin.s, 200, `l'administrateur devrait pouvoir déroger : ${admin.msg}`)
    })
  })
})

test('réouverture : réservée à l\'administrateur et avec motif obligatoire', async () => {
  await avecTraitement(...MARS, async (id) => {
    assert.equal((await transition(id, 'Validée', T.RH)).s, 200)
    assert.equal((await transition(id, 'Payée', T.PAIE)).s, 200)
    assert.equal((await transition(id, 'Clôturée', T.PAIE)).s, 200)
    assert.ok((await transition(id, 'Réouverte', T.RH, 'motif')).s >= 400, 'rh a pu rouvrir')
    assert.ok((await transition(id, 'Réouverte', T.PAIE, 'motif')).s >= 400, 'paie a pu rouvrir')
    const sansMotif = await transition(id, 'Réouverte', T.ADMIN)
    assert.ok(sansMotif.s >= 400 && /motif/i.test(sansMotif.msg), `réouverture sans motif acceptée (${sansMotif.msg})`)
    assert.equal((await transition(id, 'Réouverte', T.ADMIN, 'correction demandée')).s, 200)
    assert.equal(await statutDe(id), 'Réouverte')
  })
})

// ---- Concurrence : deux requêtes simultanées sur le même traitement ----

test('concurrence : deux validations simultanées, une seule aboutit', async () => {
  await avecTraitement(...MARS, async (id) => {
    const r = await Promise.all([transition(id, 'Validée', T.RH), transition(id, 'Validée', T.ADMIN)])
    const ok = r.filter((x) => x.s === 200).length
    assert.ok(ok >= 1, `aucune validation n'a abouti : ${r.map((x) => x.s + ' ' + x.msg).join(' | ')}`)
    assert.equal(await statutDe(id), 'Validée')
    assert.ok(r.every((x) => x.s === 200 || x.s >= 400), 'réponse inattendue')
  })
})

test('concurrence : deux calculs simultanés ne dupliquent aucun bulletin', async () => {
  await avecTraitement(...MARS, async (id) => {
    const r = await Promise.all([1, 2, 3].map(() => call('rpc/run_payroll_entry', T.PAIE, 'POST', { p_payroll_entry_id: id })))
    assert.ok(r.some((x) => x.s === 200), `aucun calcul n'a abouti : ${r.map((x) => x.s + ' ' + x.msg).join(' | ')}`)
    const doublons = execFileSync('docker', ['exec', '-i', 'soma-rh-local-postgres-1', 'psql', '-U', 'soma', '-d', 'soma_rh', '-tA', '-c',
      `select count(*) from (select employee_id from public.salary_slips where payroll_entry_id = '${id}' group by 1 having count(*) > 1) d`]).toString().trim()
    assert.equal(doublons, '0', `${doublons} salariés avec plusieurs bulletins`)
    assert.equal(await statutDe(id), 'Calculée')
  })
})

test('concurrence : deux créations simultanées du même mois, un seul traitement', async () => {
  const body = { company_id: COMPANY, period_start: '2025-04-01', period_end: '2025-04-30', payment_mode: 'espèces' }
  try {
    const r = await Promise.all([call('payroll_entries', T.PAIE, 'POST', body), call('payroll_entries', T.PAIE, 'POST', body)])
    const n = (await call(`payroll_entries?period_start=eq.2025-04-01&company_id=eq.${COMPANY}&select=id`, T.ADMIN)).b.length
    assert.equal(n, 1, `${n} traitements pour le même mois (réponses : ${r.map((x) => x.s).join(', ')})`)
  } finally { await nettoyer() }
})
