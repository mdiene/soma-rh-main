import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { ChevronLeft, ChevronRight, ExternalLink, RefreshCw } from 'lucide-react'
import { useEffect, useMemo, useState } from 'react'
import { Link, useSearchParams } from 'react-router-dom'
import { dataApi, unwrap } from '../../lib/api'
import { useAuth } from '../../lib/auth'
import { EMPLOYEE_FIELDS, fieldKeys, fixLink, fixLinks } from '../../lib/complianceLinks'
import { FixFieldsModal } from './FixFieldsModal'
import { date } from '../../lib/format'
import { Badge, Button, ErrorNote, Modal, Section, SelectField, Spinner, TextField } from '../ui'
import { doneMessage, useRefreshCompliance } from './shared'

export type Finding = {
  finding_id: string; rule_id: string; rule_label: string; domain: string; legal_ref: string | null; suggested_action: string; fix_target: string
  severity: string; entity: string; entity_id: string; employee_id: string | null; employee_number: string | null; employee_name: string | null
  message: string; detected_on: string; waived: boolean; waiver_id: string | null; waiver_reason: string | null
}
export type Scan = { status: 'vert' | 'orange' | 'rouge'; nb_bloquants: number; nb_alertes: number; nb_salaries: number; nb_derogations: number; scanned_at: string }

const LIGHT: Record<Scan['status'], { dot: string; label: string }> = {
  vert: { dot: 'bg-phosphate', label: 'Conforme' },
  orange: { dot: 'bg-signal', label: 'Alertes à examiner' },
  rouge: { dot: 'bg-red-600', label: 'Écarts bloquants' },
}

/** Onglet Cohérence : scan, constats ouverts avec lien direct vers l'élément à corriger, demande de dérogation motivée. */
export function FindingsTab({ onNotice }: { onNotice: (m: string) => void }) {
  const { can, roles } = useAuth()
  const isAdmin = roles.includes('admin')
  const qc = useQueryClient()
  const refresh = useRefreshCompliance()
  const [severity, setSeverity] = useState('')
  const [domain, setDomain] = useState('')
  const [target, setTarget] = useState<Finding | null>(null)
  const [motif, setMotif] = useState('')
  const [params, setParams] = useSearchParams()
  // `?constat=<id>` : retour d'une page de correction, on rouvre la fiche du constat
  const [openId, setOpenId] = useState<string | null>(() => params.get('constat'))
  useEffect(() => { if (params.has('constat')) setParams({}, { replace: true }) }, [params, setParams])

  const list = useQuery({ queryKey: ['compliance', 'findings'], queryFn: async () => unwrap(await dataApi.rpc('compliance_open_findings')) as unknown as Finding[] })
  const last = useQuery({ queryKey: ['compliance', 'status'], queryFn: async () => (unwrap(await dataApi.rpc('compliance_status')) as unknown as Scan[])[0] ?? null })

  const scan = useMutation({
    mutationFn: async () => unwrap(await dataApi.rpc('run_compliance_scan')) as unknown as Scan,
    onSuccess: (s) => { refresh(); void qc.invalidateQueries({ queryKey: ['compliance'] }); onNotice(`Scan terminé : ${s.nb_bloquants} bloquant(s), ${s.nb_alertes} alerte(s).`) },
  })
  const waive = useMutation({
    mutationFn: async () => unwrap(await dataApi.rpc('request_waiver', { p_rule_id: target!.rule_id, p_entity_id: target!.entity_id, p_reason: motif })),
    onSuccess: () => { setTarget(null); setMotif(''); refresh(); void qc.invalidateQueries({ queryKey: ['compliance'] }); onNotice(doneMessage(isAdmin, 'Dérogation')) },
  })

  const rows = useMemo(() => list.data ?? [], [list.data])
  const domains = useMemo(() => [...new Set(rows.map((r) => r.domain))].sort(), [rows])
  const shown = rows.filter((r) => (!severity || r.severity === severity) && (!domain || r.domain === domain))
  const s = last.data
  const openIdx = shown.findIndex((r) => r.finding_id === openId)
  const open = openIdx >= 0 ? shown[openIdx] : null   // disparaît de la liste une fois corrigé et rescanné
  const [fixing, setFixing] = useState(false)
  const inline = open?.entity === 'employee' ? fieldKeys(open).filter((k) => k in EMPLOYEE_FIELDS) : []   // champs corrigeables sur place

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-center gap-4">
        {s ? (
          <p className="flex items-center gap-2 text-sm" role="status">
            <span className={`inline-block size-3 rounded-full ${LIGHT[s.status].dot}`} aria-hidden />
            <strong>{LIGHT[s.status].label}</strong>
            <span className="text-ink-muted">— {s.nb_bloquants} bloquant(s), {s.nb_alertes} alerte(s), {s.nb_derogations} dérogation(s) — dernier scan le {date(s.scanned_at)}</span>
          </p>
        ) : <p className="text-sm text-ink-muted">Aucun scan enregistré.</p>}
        {can('rh', 'paie') && <Button icon={<RefreshCw className="size-4" />} loading={scan.isPending} onClick={() => scan.mutate()}>Lancer le scan</Button>}
      </div>
      {scan.isError && <ErrorNote error={scan.error} />}

      <Section title={`Constats ouverts (${shown.length}${shown.length !== rows.length ? ` sur ${rows.length}` : ''})`}>
        <div className="mb-3 flex flex-wrap gap-3">
          <SelectField label="Gravité" value={severity} onChange={(e) => setSeverity(e.target.value)}>
            <option value="">Toutes</option><option value="B">Bloquant</option><option value="A">Alerte</option>
          </SelectField>
          <SelectField label="Domaine" value={domain} onChange={(e) => setDomain(e.target.value)}>
            <option value="">Tous</option>{domains.map((d) => <option key={d} value={d}>{d}</option>)}
          </SelectField>
        </div>
        {list.isLoading ? <Spinner /> : list.isError ? <ErrorNote error={list.error} /> : shown.length === 0 ? (
          <p className="text-sm text-ink-muted">Aucun constat ouvert. Lancez le scan pour relancer les contrôles.</p>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead><tr className="text-left text-ink-muted"><th className="py-1 pr-3">Niveau</th><th className="pr-3">Règle</th><th className="pr-3">Constat</th><th className="pr-3">Détecté le</th><th className="pr-3">Corriger</th><th>Dérogation</th></tr></thead>
              <tbody>
                {shown.map((f) => {
                  const fix = fixLink(f)
                  return (
                    <tr key={f.finding_id} className="border-t border-line align-top">
                      <td className="py-1.5 pr-3"><Badge value={f.severity === 'B' ? 'Rejetée' : 'En attente'} label={f.severity === 'B' ? 'Bloquant' : 'Alerte'} /></td>
                      <td className="pr-3"><span className="font-medium">{f.rule_label}</span><br /><span className="text-xs text-ink-muted">{f.domain}{f.legal_ref ? ` · ${f.legal_ref}` : ''}</span></td>
                      <td className="pr-3">{f.message}<br /><span className="text-xs text-ink-muted">{f.suggested_action}</span></td>
                      <td className="pr-3 tabular-nums">{date(f.detected_on)}</td>
                      <td className="pr-3">
                        <Link to={fixLinks(f, f.finding_id)[0].to} className="inline-flex items-center gap-1 text-river underline underline-offset-2 hover:text-ink">
                          <ExternalLink className="size-3.5" aria-hidden />{fix.label}<span className="sr-only"> : {f.message}</span>
                        </Link>
                        <br /><button type="button" className="text-xs text-river hover:underline" onClick={() => setOpenId(f.finding_id)}>Voir la fiche<span className="sr-only"> : {f.message}</span></button>
                      </td>
                      <td>
                        {f.waived ? <span title={f.waiver_reason ?? ''}>Dérogé : {f.waiver_reason}</span>
                          : can('rh', 'paie') ? <Button size="sm" onClick={() => { setTarget(f); setMotif('') }}>Déroger</Button> : '—'}
                      </td>
                    </tr>
                  )
                })}
              </tbody>
            </table>
          </div>
        )}
      </Section>

      <Modal wide open={open !== null} title={open ? open.rule_label : ''} onClose={() => setOpenId(null)}
        footer={open && <>
          <Button disabled={openIdx <= 0} icon={<ChevronLeft className="size-4" />} onClick={() => setOpenId(shown[openIdx - 1].finding_id)}>Précédent</Button>
          <Button disabled={openIdx >= shown.length - 1} onClick={() => setOpenId(shown[openIdx + 1].finding_id)}>Suivant<ChevronRight className="size-4" /></Button>
          {!open.waived && can('rh', 'paie') && <Button onClick={() => { setTarget(open); setMotif('') }}>Déroger</Button>}
          <Button variant="primary" onClick={() => setOpenId(null)}>Fermer</Button>
        </>}>
        {open && (
          <div className="space-y-4 text-sm">
            <p><Badge value={open.severity === 'B' ? 'Rejetée' : 'En attente'} label={open.severity === 'B' ? 'Bloquant' : 'Alerte'} /> <span className="text-ink-muted">{open.domain}{open.legal_ref ? ` · ${open.legal_ref}` : ''} · détecté le {date(open.detected_on)}</span></p>
            {open.employee_name && <p><span className="text-ink-muted">Salarié :</span> <strong>{open.employee_name}</strong> {open.employee_number && <span className="tabular-nums text-ink-muted">({open.employee_number})</span>}</p>}
            <div><h3 className="font-medium">Ce qui ne va pas</h3><p>{open.message}</p></div>
            <div><h3 className="font-medium">Ce qu’il faut faire</h3><p>{open.suggested_action}</p></div>
            <div>
              <h3 className="font-medium">Corriger</h3>
              <ul className="mt-1 flex flex-wrap gap-2">
                {fixLinks(open, open.finding_id).map((l) => (
                  <li key={l.to}><Link to={l.to} className="inline-flex items-center gap-1 rounded border border-line bg-white px-2.5 py-1.5 text-river hover:border-ink-muted">
                    <ExternalLink className="size-3.5" aria-hidden />{l.label}</Link></li>
                ))}
              </ul>
              {inline.length > 0 && can('rh') && <Button className="mt-2" variant="primary" onClick={() => setFixing(true)}>Corriger ici, sans quitter le centre</Button>}
              <p className="mt-1 text-xs text-ink-muted">Un bandeau « Retour au constat » vous ramène ici après la correction.</p>
            </div>
            {open.waived && <p>Dérogé : {open.waiver_reason}</p>}
          </div>
        )}
      </Modal>

      <FixFieldsModal employeeId={fixing && open?.entity === 'employee' ? (open.employee_id ?? open.entity_id) : null} keys={inline} onClose={() => setFixing(false)} />

      <Modal open={target !== null} title="Dérogation motivée" onClose={() => setTarget(null)}
        footer={<>
          <Button onClick={() => setTarget(null)}>Annuler</Button>
          <Button variant="primary" loading={waive.isPending} disabled={!motif.trim()} onClick={() => waive.mutate()}>{isAdmin ? 'Enregistrer' : 'Envoyer pour validation'}</Button>
        </>}>
        {target && <p className="mb-3 text-sm text-ink-soft">{target.message}</p>}
        <TextField label="Motif (obligatoire)" value={motif} onChange={(e) => setMotif(e.target.value)} />
        {!isAdmin && <p className="mt-2 text-xs text-ink-muted">La dérogation prend effet après validation par l’administrateur.</p>}
        {waive.isError && <ErrorNote error={waive.error} />}
      </Modal>
    </div>
  )
}
