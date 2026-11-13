import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { Calculator, Check, ChevronLeft, PauseCircle } from 'lucide-react'
import { useEffect, useMemo, useRef, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { dataApi, unwrap } from '../lib/api'
import type { Json } from '../lib/database.types'
import { selectable, useAgreements, useContractTypes, useDesignations, useGrades, usePaymentModes } from '../lib/queries'
import { useAuth } from '../lib/auth'
import { fcfa } from '../lib/format'
import { contractQuestions, draftHasContent, asksMaidenName, firstFullMonth, isLikelyDuplicate, normalizeNames, parseDraft, partsAlerts, PARTS_MEMO, personName, reviewIssues, senegalParts, serializeDraft, softWarnings, stepsFor, toPayload, validateStep, type Draft, type SavedDraft } from '../lib/employeeWizard'
import { Button, ErrorNote, Modal, SelectField, Spinner, TextField } from './ui'

const INITIAL: Draft = {
  employment_type: 'CDI', payment_mode: 'espèces', marital_status: 'Célibataire', nationality: 'sénégalaise',
  spouses_count: 0, children_count: 0, trimf_parts: 1, ir_parts: 1, status: 'Active',
}
const INITIAL_ASSIGN: Draft = { sursalaire: 0, fees: 0, other_fixed: 0, transport_mode: 'Prime de transport', leave_paid_monthly: true }

const LABELS: Record<string, string> = {
  gender: 'Sexe', first_name: 'Prénom', last_name: 'Nom', date_of_birth: 'Date de naissance', place_of_birth: 'Lieu de naissance', nationality: 'Nationalité',
  id_document_number: 'N° CNI ou passeport', id_issue_date: 'Délivrée le', id_expiry_date: 'Expire le', father_name: 'Père', mother_name: 'Mère', maiden_name: 'Nom de jeune fille', mother_first_name: 'Prénom de la mère', mother_last_name: 'Nom de la mère',
  address: 'Adresse', phone_personal: 'Téléphone personnel', phone_work: 'Téléphone professionnel', email_personal: 'E-mail personnel', email_work: 'E-mail professionnel',
  emergency_contact_name: 'Personne à prévenir', emergency_contact_phone: 'Téléphone d’urgence', ipres_number: 'N° IPRES', css_number: 'N° CSS',
  marital_status: 'Situation de famille', spouses_count: 'Conjoint(e)s', children_count: 'Enfants à charge', trimf_parts: 'Parts TRIMF', ir_parts: 'Parts IR',
  designation_id: 'Emploi', employment_type: 'Type de contrat', department_id: 'Département', agreement_code: 'Convention collective', grade_id: 'Catégorie',
  date_of_joining: 'Date d’entrée', contract_start: 'Début du contrat', contract_end: 'Fin du contrat',
  payment_mode: 'Mode de paiement', bank_name: 'Banque', bank_account: 'RIB',
  hire_declaration_ref: 'Référence de la déclaration d’embauche', hire_declared_on: 'Date de la déclaration d’embauche', affiliation_date: 'Date d’affiliation à la sécurité sociale',
  from_date: 'En vigueur à partir du', base_salary: 'Salaire de base', sursalaire: 'Sursalaire', fees: 'Honoraires', other_fixed: 'Autre élément fixe', transport_mode: 'Transport',
}
const STEP_FIELDS: Record<string, string[]> = {
  identite: ['gender', 'first_name', 'last_name', 'date_of_birth', 'place_of_birth', 'nationality', 'id_document_number', 'id_issue_date', 'id_expiry_date', 'father_name', 'maiden_name', 'mother_first_name', 'mother_last_name'],
  coordonnees: ['address', 'phone_personal', 'phone_work', 'email_personal', 'email_work', 'emergency_contact_name', 'emergency_contact_phone', 'ipres_number', 'css_number'],
  famille: ['marital_status', 'spouses_count', 'children_count', 'trimf_parts', 'ir_parts'],
  contrat: ['designation_id', 'employment_type', 'department_id', 'agreement_code', 'grade_id', 'date_of_joining', 'contract_start', 'contract_end'],
  paiement: ['payment_mode', 'bank_name', 'bank_account'],
  declarations: ['hire_declaration_ref', 'hire_declared_on', 'affiliation_date'],
  remuneration: ['from_date', 'base_salary', 'sursalaire', 'fees', 'other_fixed', 'transport_mode'],
}

const num = (v: unknown, d: string | number = ''): string | number => (v === null || v === undefined || v === '' ? d : Number(v))

type CreateResult = { id: string; employee_number: string; structure_assigned: boolean; sursalaire: number | null; gross_pay: string | null; net_pay: string | null }
type Sim = { sursalaire: number; gross_pay: string; net_pay: string }
type DupRow = { id: string; employee_number: string; first_name: string; last_name: string; date_of_birth: string | null; id_document_number: string | null }

export function EmployeeWizard({ open, onClose, draftId }: { open: boolean; onClose: () => void; draftId?: string }) {
  const { can, session } = useAuth()
  const canPayroll = can('paie')
  const nav = useNavigate()
  const qc = useQueryClient()
  const designations = useDesignations()
  const agreements = useAgreements()
  const contractTypes = useContractTypes()
  const paymentModes = usePaymentModes()
  const departments = useQuery({ queryKey: ['departments'], queryFn: async () => unwrap(await dataApi.from('departments').select('id, name').order('name')) })
  const requirements = useQuery({
    queryKey: ['document_requirements_active'],
    queryFn: async () => unwrap(await dataApi.from('document_requirements').select('code, title, required, sort_order').eq('active', true).order('sort_order')),
  })

  const [draft, setDraft] = useState<Draft>(INITIAL)
  const [assign, setAssign] = useState<Draft>(INITIAL_ASSIGN)
  const [withPayroll, setWithPayroll] = useState(true)
  const [receipts, setReceipts] = useState<string[]>([])
  const [index, setIndex] = useState(0)
  const [reached, setReached] = useState(0)
  const [tried, setTried] = useState(false)
  const [confirmCancel, setConfirmCancel] = useState(false)
  const [result, setResult] = useState<CreateResult | null>(null)
  const [netOpen, setNetOpen] = useState(false)
  // parts saisies à la main : le calcul automatique ne les écrase plus (une alerte rouge signale l'écart)
  const [manualParts, setManualParts] = useState<{ ir: boolean; trimf: boolean }>({ ir: false, trimf: false })
  // saisie mise en attente en base (reprise depuis la page « Saisies en cours »)
  const [serverDraftId, setServerDraftId] = useState<string | null>(draftId ?? null)
  const heading = useRef<HTMLHeadingElement>(null)

  const grades = useGrades(draft.agreement_code as string | undefined)
  const steps = useMemo(() => stepsFor(canPayroll), [canPayroll])
  // parts TRIMF et IR : calcul automatique (référentiel 2026) tant que la saisie n'est pas manuelle
  const autoParts = senegalParts({ gender: draft.gender, marital: draft.marital_status, spouses: draft.spouses_count, children: draft.children_count })
  useEffect(() => {
    setDraft((d) => {
      const ir = manualParts.ir ? d.ir_parts : autoParts.ir
      const trimf = manualParts.trimf ? d.trimf_parts : autoParts.trimf
      return ir === d.ir_parts && trimf === d.trimf_parts ? d : { ...d, ir_parts: ir, trimf_parts: trimf }
    })
  }, [autoParts.ir, autoParts.trimf, manualParts.ir, manualParts.trimf])
  const step = steps[index]
  const payrollRequested = canPayroll && withPayroll
  const merged: Draft = { ...draft, ...(payrollRequested ? { ...assign, from_date: assign.from_date || draft.date_of_joining } : {}) }
  const effectiveAssign: Draft = { ...assign, from_date: assign.from_date || draft.date_of_joining }
  const questions = contractQuestions(draft.employment_type)

  useEffect(() => { heading.current?.focus() }, [index, result])

  /* brouillon dans le navigateur : conservé 7 jours sur ce poste, effacé à la création et à l'abandon */
  const draftKey = `soma.assistant-salarie.brouillon.${session?.user.id ?? 'anonyme'}`
  const [saved, setSaved] = useState<SavedDraft | null>(null)
  useEffect(() => {
    if (!open || draftId) return
    try { setSaved(parseDraft(localStorage.getItem(draftKey))) } catch { setSaved(null) }
  }, [open, draftKey, draftId])
  useEffect(() => {
    if (!open || result || saved || !draftHasContent(draft)) return
    const t = setTimeout(() => {
      try { localStorage.setItem(draftKey, serializeDraft({ draft, assign, receipts, index, reached, withPayroll })) } catch { /* brouillon non conservé */ }
    }, 400)
    return () => clearTimeout(t)
  }, [open, result, saved, draft, assign, receipts, index, reached, withPayroll, draftKey])
  /* saisie mise en attente en base : reprise depuis la page « Saisies en cours » */
  const loadedDraft = useRef<string | null>(null)
  const serverDraft = useQuery({
    queryKey: ['employee_draft', draftId],
    enabled: open && !!draftId,
    queryFn: async () => unwrap(await dataApi.from('employee_drafts').select('id, data').eq('id', draftId!).single()),
  })
  useEffect(() => {
    if (!serverDraft.data || loadedDraft.current === serverDraft.data.id) return
    loadedDraft.current = serverDraft.data.id
    const sd = serverDraft.data.data as unknown as Partial<{ draft: Draft; assign: Draft; receipts: string[]; index: number; reached: number; withPayroll: boolean; manualParts: { ir: boolean; trimf: boolean } }>
    setDraft({ ...INITIAL, ...(sd.draft ?? {}) }); setAssign({ ...INITIAL_ASSIGN, ...(sd.assign ?? {}) }); setReceipts(sd.receipts ?? []); setWithPayroll(sd.withPayroll ?? true)
    setManualParts(sd.manualParts ?? { ir: false, trimf: false })
    const i = Math.min(Math.max(0, sd.index ?? 0), steps.length - 1)
    setIndex(i); setReached(Math.min(Math.max(sd.reached ?? 0, i), steps.length - 1))
    setServerDraftId(serverDraft.data.id)
  }, [serverDraft.data, steps.length])
  const clearDraft = () => { try { localStorage.removeItem(draftKey) } catch { /* rien à effacer */ } }
  function resumeDraft() {
    if (!saved) return
    const i = Math.min(saved.index, steps.length - 1)
    setDraft(saved.draft); setAssign(saved.assign); setReceipts(saved.receipts); setWithPayroll(saved.withPayroll)
    setIndex(i); setReached(Math.min(Math.max(saved.reached, i), steps.length - 1)); setSaved(null)
  }
  function discardDraft() { clearDraft(); setSaved(null) }

  /* doublons probables : même numéro de pièce, ou mêmes nom, prénom et date de naissance (avertissement, jamais bloquant) */
  const dupFirst = String(draft.first_name ?? '').trim()
  const dupLast = String(draft.last_name ?? '').trim()
  const dupDoc = String(draft.id_document_number ?? '').trim()
  const dups = useQuery({
    queryKey: ['wizard-duplicates', dupFirst, dupLast, draft.date_of_birth, dupDoc],
    enabled: open && (step.id === 'identite' || step.id === 'revue') && ((dupFirst.length >= 2 && dupLast.length >= 2) || dupDoc.length >= 4),
    queryFn: async () => {
      const cols = 'id, employee_number, first_name, last_name, date_of_birth, id_document_number'
      const found = new Map<string, DupRow>()
      if (dupFirst.length >= 2 && dupLast.length >= 2) {
        const prefix = dupLast.replace(/[%,()*_]/g, ' ').trim().slice(0, 2)
        for (const r of unwrap(await dataApi.from('employees').select(cols).ilike('last_name', `${prefix}%`).limit(200)) as DupRow[]) found.set(r.id, r)
      }
      if (dupDoc.length >= 4) {
        for (const r of unwrap(await dataApi.from('employees').select(cols).eq('id_document_number', dupDoc).limit(10)) as DupRow[]) found.set(r.id, r)
      }
      return [...found.values()].filter((x) => isLikelyDuplicate(draft, x))
    },
  })

  /* n° de CNI ou de passeport : unique (espaces et casse ignorés) ; la base refuse aussi tout doublon */
  const docKey = (v: string) => v.replace(/\s/g, '').toLowerCase()
  const docTaken = useQuery({
    queryKey: ['wizard-doc-taken', docKey(dupDoc)],
    enabled: open && docKey(dupDoc).length >= 3,
    queryFn: async () => {
      const rows = unwrap(await dataApi.from('employees').select('id, employee_number, last_name, id_document_number').ilike('id_document_number', `%${docKey(dupDoc).split('').join('%')}%`).limit(20))
      return rows.filter((r) => docKey(r.id_document_number ?? '') === docKey(dupDoc))
    },
  })
  const docIssues = (docTaken.data ?? []).slice(0, 1).map((x) => ({ field: 'id_document_number', message: `Ce numéro de CNI ou de passeport est déjà attribué au salarié ${x.employee_number} ${x.last_name}.` }))

  const set = (k: string) => (e: React.ChangeEvent<HTMLInputElement | HTMLSelectElement>) => {
    const v = e.target.type === 'number' ? (e.target.value === '' ? null : Number(e.target.value)) : e.target.value
    setDraft((d) => ({ ...d, [k]: v }))
  }
  // noms de personnes : mise en forme (Prénom, Nom) à la sortie du champ ; la base applique la même règle
  const nameProps = (k: string) => ({
    value: String(draft[k] ?? ''),
    onChange: set(k),
    onBlur: () => setDraft((d) => (String(d[k] ?? '').trim() === '' ? d : { ...d, [k]: personName(d[k]) })),
  })
  const setA = (k: string) => (e: React.ChangeEvent<HTMLInputElement | HTMLSelectElement>) => {
    const v = e.target.type === 'number' ? (e.target.value === '' ? null : Number(e.target.value)) : e.target.value
    setAssign((a) => ({ ...a, [k]: v }))
  }

  const issues = [...validateStep(step.id, merged, { payrollRequested }), ...(step.id === 'identite' ? docIssues : [])]
  const warnings = softWarnings(step.id, merged)
  const reviewBase = reviewIssues(merged, steps.map((s) => s.id), { payrollRequested })
  const review = docIssues.length ? [...reviewBase.filter((r) => r.step !== 'identite'), { step: 'identite' as const, issues: [...(reviewBase.find((r) => r.step === 'identite')?.issues ?? []), ...docIssues] }] : reviewBase

  function reset() {
    setDraft(INITIAL); setAssign(INITIAL_ASSIGN); setReceipts([]); setIndex(0); setReached(0); setTried(false); setResult(null); setWithPayroll(true); setConfirmCancel(false)
    setManualParts({ ir: false, trimf: false }); setServerDraftId(draftId ?? null); loadedDraft.current = null
  }
  function close() { clearDraft(); reset(); onClose() }
  // la croix de l'en-tête garde le brouillon pour une reprise ; « Abandonner » l'efface
  function leave() { reset(); onClose() }
  function next() {
    setTried(true)
    if (issues.length > 0) return
    setTried(false)
    const n = Math.min(index + 1, steps.length - 1)
    setIndex(n); setReached((r) => Math.max(r, n))
  }
  const goTo = (i: number) => { if (i >= 0 && i <= reached) { setTried(false); setIndex(i) } }

  const create = useMutation({
    mutationFn: async () => unwrap(await dataApi.rpc('create_employee_from_wizard', {
      p_employee: toPayload(normalizeNames(draft)) as unknown as Json,
      p_assignment: (payrollRequested ? toPayload(effectiveAssign) : null) as unknown as Json,
      p_receipts: receipts,
    })) as unknown as CreateResult,
    onSuccess: async (r) => {
      clearDraft(); setResult(r); qc.invalidateQueries({ queryKey: ['employees'] }); qc.invalidateQueries({ queryKey: ['next-employee-number'] })
      if (serverDraftId) { await dataApi.from('employee_drafts').delete().eq('id', serverDraftId); setServerDraftId(null); qc.invalidateQueries({ queryKey: ['employee_drafts'] }) }
    },
  })

  /* mise en attente : la saisie est enregistrée en base (sans créer de fiche) et se reprend depuis « Saisies en cours » */
  const standby = useMutation({
    mutationFn: async () => {
      const data = { draft, assign, receipts, index, reached, withPayroll, manualParts } as unknown as Json
      if (serverDraftId) { unwrap(await dataApi.from('employee_drafts').update({ data }).eq('id', serverDraftId).select('id').single()); return serverDraftId }
      return unwrap(await dataApi.from('employee_drafts').insert({ data }).select('id').single()).id
    },
    onSuccess: () => { qc.invalidateQueries({ queryKey: ['employee_drafts'] }); clearDraft(); reset(); setServerDraftId(null); onClose(); nav('/salaries/en-cours') },
  })

  const label = (k: string, v: unknown): string => {
    if (v === null || v === undefined || v === '') return ''
    if (k === 'designation_id') return designations.data?.find((d) => d.id === v)?.name ?? String(v)
    if (k === 'department_id') return departments.data?.find((d) => d.id === v)?.name ?? String(v)
    if (k === 'agreement_code') return agreements.data?.find((a) => a.code === v)?.name ?? String(v)
    if (k === 'grade_id') { const g = grades.data?.find((x) => x.id === v); return g ? `${g.code} — ${g.staff_status}` : String(v) }
    if (k === 'employment_type') { const c = contractTypes.data?.find((x) => x.code === v); return c ? `${v} — ${c.label}` : String(v) }
    if (k === 'payment_mode') return paymentModes.data?.find((m) => m.code === v)?.label ?? String(v)
    if (k === 'gender') return v === 'M' ? 'Masculin' : v === 'F' ? 'Féminin' : String(v)
    if (['base_salary', 'sursalaire', 'fees', 'other_fixed'].includes(k)) return `${fcfa(Number(v))} F`
    return String(v)
  }

  /* ----------------------------------------------------------- écran de résultat */
  if (result) {
    return (
      <Modal open={open} onClose={close} persistent wide title="Salarié créé"
        footer={<>
          <Button variant="ghost" onClick={() => { close(); nav('/salaries') }}>Aller à la liste</Button>
          <Button onClick={reset}>Créer un autre salarié</Button>
          <Button variant="primary" onClick={() => { const id = result.id; close(); nav(`/salaries/${id}`) }}>Ouvrir la fiche</Button>
        </>}>
        <h3 ref={heading} tabIndex={-1} className="text-base font-semibold outline-none">Matricule {result.employee_number}</h3>
        <p className="mt-2 text-sm">La fiche de {String(draft.first_name)} {String(draft.last_name)} est créée.</p>
        {result.structure_assigned ? (
          <p role="status" className="mt-2 rounded border border-river/30 bg-river-light px-3 py-2 text-sm text-river-dark">
            Structure salariale affectée : sursalaire {fcfa(Number(result.sursalaire ?? 0))} F, brut {fcfa(Number(result.gross_pay ?? 0))} F, net {fcfa(Number(result.net_pay ?? 0))} F (mois de référence).
          </p>
        ) : (
          <p role="note" className="mt-2 rounded border border-phosphate bg-phosphate-light px-3 py-2 text-sm">
            La structure salariale reste à affecter par le service paie : sans elle, le salarié n’aura pas de bulletin. Elle s’affecte sur la fiche, section « Structure salariale ».
          </p>
        )}
        {receipts.length > 0 && <p className="mt-2 text-sm text-ink-soft">{receipts.length} pièce(s) enregistrée(s) comme reçue(s). Les fichiers se téléversent dans « Dossiers administratifs ».</p>}
      </Modal>
    )
  }

  /* ------------------------------------------------------------------- étapes */
  const fieldErrors = tried ? issues : []
  const alertsParts = partsAlerts(draft)
  const setPart = (k: 'ir_parts' | 'trimf_parts') => (e: React.ChangeEvent<HTMLInputElement | HTMLSelectElement>) => {
    setManualParts((m) => ({ ...m, [k === 'ir_parts' ? 'ir' : 'trimf']: true }))
    set(k)(e)
  }
  const partsBlock = (
    <div className="space-y-2 sm:col-span-3">
      {alertsParts.length > 0 && (
        <div role="alert" className="rounded border border-signal/50 bg-signal-light px-3 py-2 text-sm font-medium text-signal">
          <ul className="list-disc pl-4">{alertsParts.map((a) => <li key={a.field}>{a.message}</li>)}</ul>
          <Button size="sm" className="mt-2" onClick={() => setManualParts({ ir: false, trimf: false })}>Appliquer le calcul automatique ({String(autoParts.ir).replace('.', ',')} part(s) IR, {autoParts.trimf} part(s) TRIMF)</Button>
        </div>
      )}
      <div className="rounded border border-line bg-paper px-3 py-2 text-xs text-ink-soft">
        <p className="font-medium text-ink">Calcul automatique des parts : formules utilisées</p>
        <ul className="mt-1 list-disc space-y-0.5 pl-4">{PARTS_MEMO.map((m) => <li key={m}>{m}</li>)}</ul>
        <p className="mt-1">Les parts se recalculent tant que vous ne les modifiez pas ; vous pouvez les saisir à la main (une alerte rouge signale alors tout écart).</p>
      </div>
    </div>
  )
  const banner = saved && (
    <div role="status" className="mb-3 flex flex-wrap items-center gap-2 rounded border border-river/30 bg-river-light px-3 py-2 text-sm text-river-dark">
      <span>Un brouillon du {new Date(saved.savedAt).toLocaleString('fr-FR')} est disponible ({String(saved.draft.first_name ?? '')} {String(saved.draft.last_name ?? '')}).</span>
      <Button size="sm" variant="primary" onClick={resumeDraft}>Reprendre</Button>
      <Button size="sm" onClick={discardDraft}>Repartir de zéro</Button>
    </div>
  )
  const dupPanel = (step.id === 'identite' || step.id === 'revue') && (dups.data ?? []).length > 0 && (
    <div role="note" className="mb-3 rounded border border-phosphate bg-phosphate-light px-3 py-2 text-sm text-ink">
      <p className="font-medium">Un salarié semble déjà exister :</p>
      <ul className="mt-1 list-disc pl-5">
        {(dups.data ?? []).map((x) => (
          <li key={x.id}>{x.employee_number} {x.first_name} {x.last_name}{x.date_of_birth ? ` (né(e) le ${x.date_of_birth})` : ''} — <a className="underline" href={`/salaries/${x.id}`} target="_blank" rel="noreferrer">ouvrir la fiche (nouvel onglet)</a></li>
        ))}
      </ul>
      <p className="mt-1 text-xs">Vérifiez avant de continuer : il peut s’agir d’un homonyme.</p>
    </div>
  )
  const body = () => {
    switch (step.id) {
      case 'identite': return (
        <div className="grid gap-3 sm:grid-cols-2">
          <SelectField label="Sexe" value={String(draft.gender ?? '')} onChange={set('gender')}><option value="">—</option><option value="M">Masculin</option><option value="F">Féminin</option></SelectField>
          <span />
          <TextField label="Prénom" required {...nameProps('first_name')} />
          <TextField label="Nom" required {...nameProps('last_name')} />
          {asksMaidenName(draft) && <TextField label="Nom de jeune fille" {...nameProps('maiden_name')} />}
          <TextField label="Date de naissance" type="date" value={String(draft.date_of_birth ?? '')} onChange={set('date_of_birth')} />
          <TextField label="Lieu de naissance" value={String(draft.place_of_birth ?? '')} onChange={set('place_of_birth')} />
          <TextField label="Nationalité" value={String(draft.nationality ?? '')} onChange={set('nationality')} />
          <TextField label="N° CNI ou passeport" required value={String(draft.id_document_number ?? '')} onChange={set('id_document_number')} hint="Obligatoire et unique : deux salariés ne peuvent pas avoir le même numéro." />
          <TextField label="Délivrée le" type="date" value={String(draft.id_issue_date ?? '')} onChange={set('id_issue_date')} />
          <TextField label="Expire le" type="date" value={String(draft.id_expiry_date ?? '')} onChange={set('id_expiry_date')} />
          <TextField label="Père (nom et prénom)" {...nameProps('father_name')} />
          <span />
          <TextField label="Prénom de la mère" {...nameProps('mother_first_name')} />
          <TextField label="Nom de la mère" {...nameProps('mother_last_name')} />
        </div>)
      case 'coordonnees': return (
        <div className="grid gap-3 sm:grid-cols-2">
          <TextField label="Adresse" className="sm:col-span-2" value={String(draft.address ?? '')} onChange={set('address')} />
          <TextField label="Téléphone personnel" value={String(draft.phone_personal ?? '')} onChange={set('phone_personal')} hint="Sert aussi à l’accès par téléphone du salarié." />
          <TextField label="Téléphone professionnel" value={String(draft.phone_work ?? '')} onChange={set('phone_work')} />
          <TextField label="E-mail personnel" type="email" value={String(draft.email_personal ?? '')} onChange={set('email_personal')} />
          <TextField label="E-mail professionnel" type="email" value={String(draft.email_work ?? '')} onChange={set('email_work')} />
          <TextField label="Personne à prévenir" value={String(draft.emergency_contact_name ?? '')} onChange={set('emergency_contact_name')} />
          <TextField label="Téléphone d'urgence" value={String(draft.emergency_contact_phone ?? '')} onChange={set('emergency_contact_phone')} />
          <TextField label="N° IPRES" value={String(draft.ipres_number ?? '')} onChange={set('ipres_number')} />
          <TextField label="N° allocations familiales (CSS)" value={String(draft.css_number ?? '')} onChange={set('css_number')} />
        </div>)
      case 'famille': return (
        <div className="grid gap-3 sm:grid-cols-3">
          <SelectField label="Situation de famille" value={String(draft.marital_status ?? '')} onChange={set('marital_status')}>
            {['Marié(e)', 'Célibataire', 'Divorcé(e)', 'Veuf(ve)'].map((s) => <option key={s}>{s}</option>)}
          </SelectField>
          <TextField label="Conjoint(e)s" type="number" min={0} value={num(draft.spouses_count, 0)} onChange={set('spouses_count')} />
          <TextField label="Enfants à charge" type="number" min={0} value={num(draft.children_count, 0)} onChange={set('children_count')} />
          <TextField label="Parts TRIMF" type="number" step="0.5" min={1} value={num(draft.trimf_parts, 1)} onChange={setPart('trimf_parts')} hint={manualParts.trimf ? 'Saisie manuelle' : 'Calcul automatique'} />
          <TextField label="Parts IR (quotient familial)" type="number" step="0.5" min={1} max={5} value={num(draft.ir_parts, 1)} onChange={setPart('ir_parts')} hint={manualParts.ir ? 'Saisie manuelle (de 1 à 5 parts)' : 'Calcul automatique (de 1 à 5 parts)'} />
          {partsBlock}
        </div>)
      case 'contrat': return (
        <div className="grid gap-3 sm:grid-cols-2">
          <SelectField label="Type de contrat" value={String(draft.employment_type ?? '')} onChange={set('employment_type')}>
            {selectable(contractTypes.data, (c) => c.code === draft.employment_type).map((c) => <option key={c.code} value={c.code}>{c.code} — {c.label}</option>)}
          </SelectField>
          <TextField label="Date d'entrée" type="date" required value={String(draft.date_of_joining ?? '')} onChange={set('date_of_joining')} />
          {questions.note && <p className="rounded border border-line bg-paper px-3 py-2 text-xs text-ink-soft sm:col-span-2">{questions.note}</p>}
          {questions.fixedTerm && <>
            <TextField label="Début du contrat en cours" type="date" required value={String(draft.contract_start ?? '')} onChange={set('contract_start')} />
            <TextField label="Fin du contrat en cours" type="date" required value={String(draft.contract_end ?? '')} onChange={set('contract_end')} />
          </>}
          <SelectField label="Emploi" value={String(draft.designation_id ?? '')} onChange={set('designation_id')}>
            <option value="">—</option>
            {selectable(designations.data, (d) => d.id === draft.designation_id).map((d) => <option key={d.id} value={d.id}>{d.name}</option>)}
          </SelectField>
          <SelectField label="Département" value={String(draft.department_id ?? '')} onChange={set('department_id')}>
            <option value="">— aucun —</option>
            {(departments.data ?? []).map((d) => <option key={d.id} value={d.id}>{d.name}</option>)}
          </SelectField>
          <SelectField label="Convention collective" className="sm:col-span-2" value={String(draft.agreement_code ?? '')} onChange={(e) => setDraft((d) => ({ ...d, agreement_code: e.target.value || null, grade_id: null }))}>
            <option value="">—</option>
            {selectable(agreements.data, (a) => a.code === draft.agreement_code).map((a) => <option key={a.code} value={a.code}>{a.name}</option>)}
          </SelectField>
          <SelectField label="Catégorie" className="sm:col-span-2" value={String(draft.grade_id ?? '')} onChange={set('grade_id')} disabled={!draft.agreement_code}
            hint="Le salaire minimum de la catégorie sert de base quand le salaire de base reste vide.">
            <option value="">—</option>
            {selectable(grades.data, (g) => g.id === draft.grade_id).map((g) => (
              <option key={g.id} value={g.id}>{g.code} — {g.staff_status}{g.grade_class ? ` (classe ${g.grade_class})` : ''} — {Number(g.base_salary) > 0 ? `${fcfa(g.base_salary)} F` : 'minimum non renseigné'}</option>
            ))}
          </SelectField>
        </div>)
      case 'paiement': return (
        <div className="grid gap-3 sm:grid-cols-2">
          <SelectField label="Mode de paiement" value={String(draft.payment_mode ?? '')} onChange={set('payment_mode')}>
            {selectable(paymentModes.data, (m) => m.code === draft.payment_mode).map((m) => <option key={m.code} value={m.code}>{m.label}</option>)}
          </SelectField>
          <TextField label="Banque" value={String(draft.bank_name ?? '')} onChange={set('bank_name')} />
          <TextField label="RIB" className="sm:col-span-2" value={String(draft.bank_account ?? '')} onChange={set('bank_account')} />
        </div>)
      case 'declarations': return (
        <div className="grid gap-3 sm:grid-cols-2">
          <TextField label="Référence de la déclaration d'embauche" value={String(draft.hire_declaration_ref ?? '')} onChange={set('hire_declaration_ref')} />
          <TextField label="Date de la déclaration d'embauche" type="date" value={String(draft.hire_declared_on ?? '')} onChange={set('hire_declared_on')} />
          <TextField label="Date d'affiliation à la sécurité sociale" type="date" value={String(draft.affiliation_date ?? '')} onChange={set('affiliation_date')} />
        </div>)
      case 'remuneration': return (
        <div className="space-y-3">
          <label className="flex items-center gap-2 text-sm">
            <input type="checkbox" checked={withPayroll} onChange={(e) => setWithPayroll(e.target.checked)} />
            <span>Affecter la structure salariale maintenant</span>
          </label>
          {withPayroll && (
            <div className="grid gap-3 sm:grid-cols-2">
              <TextField label="En vigueur à partir du" type="date" value={String(effectiveAssign.from_date ?? '')} onChange={setA('from_date')} />
              <TextField label="Salaire de base (vide = minimum de la catégorie)" type="number" value={num(assign.base_salary)} onChange={setA('base_salary')} />
              <TextField label="Sursalaire" type="number" step="0.01" value={num(assign.sursalaire, 0)} onChange={setA('sursalaire')} />
              <TextField label={questions.fees ? 'Honoraires (prestataire)' : 'Honoraires (prestataires)'} type="number" value={num(assign.fees, 0)} onChange={setA('fees')} />
              <TextField label="Autre élément fixe" type="number" value={num(assign.other_fixed, 0)} onChange={setA('other_fixed')} />
              <SelectField label="Transport" value={String(assign.transport_mode ?? 'Prime de transport')} onChange={setA('transport_mode')}>
                <option>Prime de transport</option><option>Indemnité kilométrique</option><option>Aucun</option>
              </SelectField>
              <div className="rounded border border-line bg-paper p-3 sm:col-span-2">
                <p className="text-sm font-medium">Partir du net souhaité</p>
                <p className="mb-2 text-xs text-ink-soft">Ouvre la fenêtre de calcul : indiquez le net à payer voulu, l’assistant calcule le sursalaire correspondant et le reprend ici une fois validé.</p>
                <Button icon={<Calculator className="h-4 w-4" />} onClick={() => setNetOpen(true)}>Calculer le sursalaire à partir du net…</Button>
              </div>
            </div>
          )}
        </div>)
      case 'pieces': return (
        <div>
          {requirements.isLoading ? <Spinner /> : (
            <ul className="divide-y divide-line rounded border border-line">
              {(requirements.data ?? []).map((r) => (
                <li key={r.code}>
                  <label className="flex items-center gap-3 px-3 py-2 text-sm">
                    <input type="checkbox" checked={receipts.includes(r.code)} onChange={(e) => setReceipts((x) => e.target.checked ? [...x, r.code] : x.filter((c) => c !== r.code))} />
                    <span className="flex-1">{r.title}</span>
                    <span className="text-xs text-ink-soft">{r.required ? 'requise' : 'facultative'}</span>
                  </label>
                </li>
              ))}
              {(requirements.data ?? []).length === 0 && <li className="px-3 py-2 text-sm text-ink-muted">Aucune pièce n’est définie.</li>}
            </ul>
          )}
          <p className="mt-2 text-xs text-ink-soft">{receipts.length} pièce(s) cochée(s). Cocher ne téléverse rien : les fichiers s’ajoutent ensuite dans « Dossiers administratifs ».</p>
        </div>)
      case 'revue': return (
        <div className="space-y-4">
          {review.length > 0 && (
            <div role="alert" className="rounded border border-signal/30 bg-signal-light px-3 py-2 text-sm text-signal">
              <p className="font-medium">À corriger avant la création :</p>
              <ul className="mt-1 list-disc pl-5">
                {review.flatMap((r) => r.issues.map((i) => (
                  <li key={r.step + i.field}>{steps.find((s) => s.id === r.step)?.title} : {i.message} <button type="button" className="underline" onClick={() => goTo(steps.findIndex((s) => s.id === r.step))}>Corriger</button></li>
                )))}
              </ul>
            </div>
          )}
          {steps.filter((s) => STEP_FIELDS[s.id]).map((s) => {
            const isPay = s.id === 'remuneration'
            const rows = STEP_FIELDS[s.id].filter(() => !isPay || payrollRequested).map((f) => [f, label(f, isPay ? effectiveAssign[f] : merged[f])] as const).filter(([, v]) => v !== '')
            return (
              <section key={s.id} className="rounded border border-line">
                <header className="flex items-center justify-between border-b border-line bg-paper px-3 py-2">
                  <h4 className="text-sm font-semibold">{s.title}</h4>
                  <button type="button" className="text-xs text-river hover:underline" onClick={() => goTo(steps.findIndex((x) => x.id === s.id))}>Modifier</button>
                </header>
                {rows.length === 0 ? <p className="px-3 py-2 text-sm text-ink-muted">Rien de renseigné.</p> : (
                  <dl className="grid gap-x-4 gap-y-1 px-3 py-2 text-sm sm:grid-cols-2">
                    {rows.map(([f, v]) => <div key={f} className="flex gap-2"><dt className="text-ink-muted">{LABELS[f] ?? f} :</dt><dd className="font-medium">{v}</dd></div>)}
                  </dl>
                )}
              </section>
            )
          })}
          {!canPayroll && <p role="note" className="rounded border border-phosphate bg-phosphate-light px-3 py-2 text-sm">La structure salariale sera à affecter par le service paie après la création (votre compte n’a pas le rôle paie).</p>}
          <p className="text-sm text-ink-soft">Pièces reçues : {receipts.length}. Le matricule sera attribué à la création.</p>
          <ErrorNote error={create.error} />
        </div>)
    }
  }

  const isLast = index === steps.length - 1
  return (
    <>
      <Modal open={open} onClose={leave} persistent wide fullscreenOnMobile title="Nouveau salarié — assistant de saisie"
        footer={<>
          {confirmCancel ? (
            <>
              <span className="mr-auto self-center text-sm text-signal">Abandonner la saisie ? Rien n’est enregistré.</span>
              <Button variant="ghost" onClick={() => setConfirmCancel(false)}>Continuer la saisie</Button>
              <Button onClick={close}>Abandonner</Button>
            </>
          ) : (
            <>
              <Button variant="ghost" className="mr-auto" onClick={() => setConfirmCancel(true)}>Annuler</Button>
              <Button icon={<PauseCircle className="h-4 w-4" />} loading={standby.isPending} disabled={!draftHasContent(draft)} onClick={() => standby.mutate()}
                title="Enregistrer la saisie sans créer de fiche : elle se reprend depuis « Saisies en cours »">Mettre en attente</Button>
              <Button icon={<ChevronLeft className="h-4 w-4" />} disabled={index === 0} onClick={() => { setTried(false); setIndex(index - 1) }}>Précédent</Button>
              {isLast
                ? <Button variant="primary" loading={create.isPending} disabled={review.length > 0} icon={<Check className="h-4 w-4" />} onClick={() => create.mutate()}>Créer le salarié</Button>
                : <Button variant="primary" onClick={next}>Valider et continuer</Button>}
            </>
          )}
        </>}>
        <nav aria-label="Étapes de l’assistant" className="mb-4">
          <ol className="flex flex-wrap gap-1.5 text-xs">
            {steps.map((s, i) => (
              <li key={s.id}>
                <button type="button" disabled={i > reached} onClick={() => goTo(i)} aria-current={i === index ? 'step' : undefined}
                  className={`rounded border px-2 py-1 ${i === index ? 'border-river bg-river text-white' : i <= reached ? 'border-river/40 bg-river-light text-river-dark hover:border-river' : 'border-line text-ink-muted'}`}>
                  {i + 1}. {s.title}
                </button>
              </li>
            ))}
          </ol>
        </nav>
        <h3 ref={heading} tabIndex={-1} className="text-base font-semibold outline-none">{index + 1}. {step.title}</h3>
        <p className="mb-3 text-sm text-ink-soft">{step.help}</p>
        {banner}
        <ErrorNote error={standby.error} />
        {dupPanel}
        {fieldErrors.length > 0 && (
          <div role="alert" className="mb-3 rounded border border-signal/30 bg-signal-light px-3 py-2 text-sm text-signal">
            <ul className="list-disc pl-4">{fieldErrors.map((i) => <li key={i.field + i.message}>{i.message}</li>)}</ul>
          </div>
        )}
        {warnings.length > 0 && step.id !== 'revue' && (
          <div role="note" className="mb-3 rounded border border-phosphate bg-phosphate-light px-3 py-2 text-xs text-ink">
            <ul className="list-disc pl-4">{warnings.map((i) => <li key={i.field + i.message}>{i.message}</li>)}</ul>
          </div>
        )}
        {body()}
      </Modal>
      <NetCalculator open={open && netOpen} onClose={() => setNetOpen(false)} draft={draft} assign={effectiveAssign}
        onApply={(sim, target) => { setAssign((a) => ({ ...a, sursalaire: sim.sursalaire, target_net: target })); setNetOpen(false) }} />
    </>
  )
}

/* ------------------------------------------------------ fenêtre de calcul du net (H1) */
function NetCalculator({ open, onClose, draft, assign, onApply }: { open: boolean; onClose: () => void; draft: Draft; assign: Draft; onApply: (s: Sim, target: number) => void }) {
  const [target, setTarget] = useState('')
  const [month, setMonth] = useState('')
  const refMonth = month || firstFullMonth(draft.date_of_joining as string | undefined).slice(0, 7)
  const mid = !!draft.date_of_joining && String(draft.date_of_joining).slice(8, 10) !== '01'
  const sim = useMutation({
    mutationFn: async () => unwrap(await dataApi.rpc('simulate_net_for_draft', {
      p_employee: toPayload(draft) as unknown as Json,
      p_assignment: toPayload({ ...assign, sursalaire: null }) as unknown as Json,
      p_target_net: Number(target),
      p_period_start: `${refMonth}-01`,
    })) as unknown as Sim,
  })
  return (
    <Modal open={open} onClose={onClose} persistent title="Calcul du salaire à partir du net"
      footer={<>
        <Button variant="ghost" onClick={onClose}>Fermer</Button>
        <Button variant="primary" disabled={!sim.data} onClick={() => sim.data && onApply(sim.data, Number(target))}>Valider et reprendre dans la saisie</Button>
      </>}>
      <p className="mb-3 text-sm text-ink-soft">Rien n’est enregistré : le calcul utilise le moteur de la paie sur les informations saisies jusqu’ici (contrat, catégorie, famille).</p>
      <div className="flex flex-wrap items-end gap-2">
        <TextField label="Net à payer souhaité (F CFA)" type="number" value={target} onChange={(e) => { setTarget(e.target.value); sim.reset() }} className="w-56" />
        <TextField label="Mois de référence" type="month" value={refMonth} onChange={(e) => { setMonth(e.target.value); sim.reset() }} className="w-44"
          hint={mid ? 'Choisissez un mois complet : une entrée en cours de mois est payée au prorata.' : undefined} />
        <Button variant="primary" loading={sim.isPending} disabled={!(Number(target) > 0)} icon={<Calculator className="h-4 w-4" />} onClick={() => sim.mutate()}>Calculer</Button>
      </div>
      {sim.data && (
        <dl role="status" className="mt-4 grid grid-cols-3 gap-3 rounded border border-line bg-paper p-3 text-sm">
          <div><dt className="text-xs text-ink-muted">Sursalaire</dt><dd className="font-semibold">{fcfa(sim.data.sursalaire)} F</dd></div>
          <div><dt className="text-xs text-ink-muted">Brut</dt><dd className="font-semibold">{fcfa(Number(sim.data.gross_pay))} F</dd></div>
          <div><dt className="text-xs text-ink-muted">Net à payer</dt><dd className="font-semibold">{fcfa(Number(sim.data.net_pay))} F</dd></div>
        </dl>
      )}
      <div className="mt-3"><ErrorNote error={sim.error} /></div>
    </Modal>
  )
}
