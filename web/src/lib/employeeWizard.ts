/**
 * Règles de l'assistant de création d'un salarié : étapes, champs obligatoires, contrôles de format, questions selon le contrat.
 * Fonctions pures (aucun accès réseau ni DOM), testables sous Node. Aucune valeur légale n'est codée ici : l'assistant avertit,
 * les contrôles définitifs restent ceux de la base de données.
 */

export type StepId = 'identite' | 'coordonnees' | 'famille' | 'contrat' | 'paiement' | 'declarations' | 'remuneration' | 'pieces' | 'revue'

export type Step = { id: StepId; title: string; help: string }

export const STEPS: Step[] = [
  { id: 'identite', title: 'Identité', help: 'État civil du salarié. Le prénom et le nom sont obligatoires ; le matricule est attribué à la fin.' },
  { id: 'coordonnees', title: 'Coordonnées', help: 'Pour joindre le salarié et sa personne à prévenir. Le téléphone personnel sert aussi à l’accès par téléphone.' },
  { id: 'famille', title: 'Famille et fiscalité', help: 'La situation de famille et les enfants à charge influencent l’impôt retenu au bulletin.' },
  { id: 'contrat', title: 'Contrat et classification', help: 'Le type de contrat et la catégorie déterminent le calcul de la paie. Les questions s’adaptent au contrat choisi.' },
  { id: 'paiement', title: 'Paiement', help: 'Comment le salaire sera versé. Pour un virement, renseignez la banque et le RIB.' },
  { id: 'declarations', title: 'Déclarations et affiliations', help: 'Déclaration d’embauche et affiliations. Ces informations peuvent aussi être complétées plus tard sur la fiche.' },
  { id: 'remuneration', title: 'Rémunération', help: 'Structure salariale du salarié (service paie). Vous pouvez partir du net souhaité pour calculer le sursalaire.' },
  { id: 'pieces', title: 'Pièces du dossier', help: 'Cochez les pièces déjà reçues. Le téléversement des fichiers se fait ensuite dans « Dossiers administratifs ».' },
  { id: 'revue', title: 'Revue et sauvegarde', help: 'Relisez chaque section, corrigez si besoin, puis créez le salarié.' },
]

/** Étapes proposées selon les droits : la rémunération n'est affichée qu'au service paie (ou à l'administrateur). */
export const stepsFor = (canPayroll: boolean): Step[] => STEPS.filter((s) => s.id !== 'remuneration' || canPayroll)

export type Draft = Record<string, string | number | boolean | null | undefined>
export type Issue = { field: string; message: string }

const blank = (v: unknown) => v === null || v === undefined || String(v).trim() === ''
const today = () => new Date().toISOString().slice(0, 10)
const digits = (v: unknown) => String(v ?? '').replace(/\D/g, '')

/** Types de contrat à durée limitée : début et fin du contrat en cours demandés. */
export const FIXED_TERM = ['CDD', 'STAGE', 'APPRENTISSAGE']
export const isFixedTerm = (code: unknown) => FIXED_TERM.includes(String(code ?? ''))

/** Questions supplémentaires selon le type de contrat (code). */
export function contractQuestions(code: unknown): { fixedTerm: boolean; fees: boolean; note: string } {
  const c = String(code ?? '')
  if (c === 'CDD') return { fixedTerm: true, fees: false, note: 'Contrat à durée déterminée : indiquez le début et la fin du contrat en cours.' }
  if (c === 'STAGE') return { fixedTerm: true, fees: false, note: 'Stage : indiquez les dates de début et de fin du stage.' }
  if (c === 'APPRENTISSAGE') return { fixedTerm: true, fees: false, note: 'Apprentissage : indiquez les dates de début et de fin du contrat.' }
  if (c === 'PRESTATION') return { fixedTerm: false, fees: true, note: 'Prestation de services : la rémunération se saisit en honoraires (étape Rémunération).' }
  if (c === 'COD') return { fixedTerm: false, fees: false, note: 'Ouvrier journalier : aucune date de fin demandée.' }
  return { fixedTerm: false, fees: false, note: '' }
}

/** Contrôles bloquants d'une étape (champs obligatoires et incohérences certaines). */
export function validateStep(id: StepId, d: Draft, o: { payrollRequested?: boolean } = {}): Issue[] {
  const e: Issue[] = []
  if (id === 'identite') {
    if (blank(d.first_name)) e.push({ field: 'first_name', message: 'Le prénom est obligatoire.' })
    if (blank(d.last_name)) e.push({ field: 'last_name', message: 'Le nom est obligatoire.' })
    if (blank(d.id_document_number)) e.push({ field: 'id_document_number', message: 'Le numéro de CNI ou de passeport est obligatoire (il doit être unique).' })
    if (!blank(d.date_of_birth) && String(d.date_of_birth) > today()) e.push({ field: 'date_of_birth', message: 'La date de naissance ne peut pas être dans le futur.' })
    if (!blank(d.id_issue_date) && !blank(d.id_expiry_date) && String(d.id_expiry_date) < String(d.id_issue_date)) e.push({ field: 'id_expiry_date', message: 'La pièce d’identité expire avant sa date de délivrance.' })
  }
  if (id === 'famille') {
    if (blank(d.marital_status)) e.push({ field: 'marital_status', message: 'La situation de famille est obligatoire.' })
    for (const [k, label] of [['spouses_count', 'conjoints'], ['children_count', 'enfants à charge']] as const) {
      if (Number(d[k] ?? 0) < 0) e.push({ field: k, message: `Le nombre de ${label} ne peut pas être négatif.` })
    }
  }
  if (id === 'contrat') {
    if (blank(d.employment_type)) e.push({ field: 'employment_type', message: 'Le type de contrat est obligatoire.' })
    if (blank(d.date_of_joining)) e.push({ field: 'date_of_joining', message: 'La date d’entrée est obligatoire.' })
    if (isFixedTerm(d.employment_type)) {
      if (blank(d.contract_start)) e.push({ field: 'contract_start', message: 'Le début du contrat est obligatoire pour ce type de contrat.' })
      if (blank(d.contract_end)) e.push({ field: 'contract_end', message: 'La fin du contrat est obligatoire pour ce type de contrat.' })
    }
    if (!blank(d.contract_start) && !blank(d.contract_end) && String(d.contract_end) < String(d.contract_start)) e.push({ field: 'contract_end', message: 'La fin du contrat précède son début.' })
    if (!blank(d.date_of_birth) && !blank(d.date_of_joining) && String(d.date_of_joining) < String(d.date_of_birth)) e.push({ field: 'date_of_joining', message: 'La date d’entrée précède la date de naissance.' })
  }
  if (id === 'paiement' && blank(d.payment_mode)) e.push({ field: 'payment_mode', message: 'Le mode de paiement est obligatoire.' })
  if (id === 'remuneration' && o.payrollRequested) {
    if (blank(d.from_date)) e.push({ field: 'from_date', message: 'La date d’effet de la structure est obligatoire.' })
    for (const k of ['base_salary', 'sursalaire', 'fees', 'other_fixed'] as const) {
      if (!blank(d[k]) && Number(d[k]) < 0) e.push({ field: k, message: 'Ce montant ne peut pas être négatif.' })
    }
  }
  return e
}

/** Avertissements non bloquants : formats et cohérences à vérifier (la saisie reste possible). */
export function softWarnings(id: StepId, d: Draft): Issue[] {
  const w: Issue[] = []
  if (id === 'coordonnees') {
    for (const [k, label] of [['phone_personal', 'Le téléphone personnel'], ['phone_work', 'Le téléphone professionnel'], ['emergency_contact_phone', 'Le téléphone d’urgence']] as const) {
      if (!blank(d[k]) && digits(d[k]).length < 8) w.push({ field: k, message: `${label} semble incomplet (moins de 8 chiffres).` })
    }
    for (const [k, label] of [['email_personal', 'L’e-mail personnel'], ['email_work', 'L’e-mail professionnel']] as const) {
      if (!blank(d[k]) && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(String(d[k]))) w.push({ field: k, message: `${label} ne ressemble pas à une adresse valide.` })
    }
    if (!blank(d.emergency_contact_name) && blank(d.emergency_contact_phone)) w.push({ field: 'emergency_contact_phone', message: 'Une personne à prévenir est indiquée sans numéro.' })
  }
  if (id === 'contrat') {
    if (blank(d.designation_id)) w.push({ field: 'designation_id', message: 'Aucun emploi choisi : il est imprimé sur le bulletin.' })
    if (blank(d.agreement_code) || blank(d.grade_id)) w.push({ field: 'grade_id', message: 'Sans convention et catégorie, le salaire de base devra être saisi à la main.' })
    if (!blank(d.date_of_joining) && String(d.date_of_joining) > new Date(Date.now() + 366 * 86400000).toISOString().slice(0, 10)) w.push({ field: 'date_of_joining', message: 'La date d’entrée est à plus d’un an.' })
  }
  if (id === 'paiement' && !blank(d.payment_mode) && String(d.payment_mode) !== 'espèces' && blank(d.bank_account)) w.push({ field: 'bank_account', message: 'Paiement non espèces sans RIB : à compléter avant la première paie.' })
  if (id === 'paiement' && !blank(d.bank_account)) {
    const n = String(d.bank_account).replace(/\s/g, '').length
    if (n < 10) w.push({ field: 'bank_account', message: 'Le RIB semble trop court.' })
  }
  if (id === 'declarations' && blank(d.hire_declaration_ref)) w.push({ field: 'hire_declaration_ref', message: 'Déclaration d’embauche non renseignée : à compléter sur la fiche.' })
  return w
}

/** Toutes les erreurs bloquantes, regroupées par étape (pour la revue). */
export function reviewIssues(d: Draft, steps: StepId[], o: { payrollRequested?: boolean } = {}): { step: StepId; issues: Issue[] }[] {
  return steps.filter((s) => s !== 'revue').map((s) => ({ step: s, issues: validateStep(s, d, o) })).filter((x) => x.issues.length > 0)
}

/** Charge utile de création : champs vides retirés. */
export function toPayload(d: Draft): Record<string, unknown> {
  const out: Record<string, unknown> = {}
  for (const [k, v] of Object.entries(d)) {
    if (v === undefined || v === null || v === '') continue
    out[k] = v
  }
  return out
}

/** Premier mois civil complet à partir d'une date d'entrée (évite le prorata dans la simulation du net). */
export function firstFullMonth(date: string | null | undefined): string {
  const d = date && /^\d{4}-\d{2}-\d{2}$/.test(date) ? date : today()
  const [y, m, day] = d.split('-').map(Number)
  if (day === 1) return `${y}-${String(m).padStart(2, '0')}-01`
  const n = m === 12 ? [y + 1, 1] : [y, m + 1]
  return `${n[0]}-${String(n[1]).padStart(2, '0')}-01`
}

/* --------------------------------------------------------------------------------- parts fiscales proposées */
/**
 * Règle de calcul des parts : à fournir par le propriétaire. Aucune valeur légale n'est codée : tant que la règle vaut null,
 * l'assistant n'affiche aucune proposition et les parts se saisissent à la main.
 */
export type PartsRule = { base: number; married: number; perChild: number; max: number; trimfFollowsIr: boolean }
export const PARTS_RULE: PartsRule | null = null

export function proposeParts(rule: PartsRule | null, marital: unknown, children: unknown): { ir: number; trimf: number | null } | null {
  if (!rule) return null
  const kids = Math.max(0, Number(children ?? 0))
  const raw = rule.base + (String(marital ?? '') === 'Marié(e)' ? rule.married : 0) + rule.perChild * kids
  const ir = Math.min(rule.max, Math.round(raw * 2) / 2)
  return { ir, trimf: rule.trimfFollowsIr ? ir : null }
}

/* ------------------------------------------------------------------------------------------ doublons */
export const normalizeName = (v: unknown) => String(v ?? '').normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase().replace(/\s+/g, ' ').trim()

export type PersonKey = { first_name?: unknown; last_name?: unknown; date_of_birth?: unknown; id_document_number?: unknown }

/** Même personne probable : même numéro de pièce, ou mêmes nom et prénom avec la même date de naissance (ou une date absente d'un côté). */
export function isLikelyDuplicate(a: PersonKey, b: PersonKey): boolean {
  const docA = String(a.id_document_number ?? '').replace(/\s/g, '').toLowerCase()
  const docB = String(b.id_document_number ?? '').replace(/\s/g, '').toLowerCase()
  if (docA && docB && docA === docB) return true
  if (!normalizeName(a.first_name) || !normalizeName(a.last_name)) return false
  if (normalizeName(a.first_name) !== normalizeName(b.first_name) || normalizeName(a.last_name) !== normalizeName(b.last_name)) return false
  const da = String(a.date_of_birth ?? ''), db = String(b.date_of_birth ?? '')
  return !da || !db || da === db
}

/* ------------------------------------------------------------------------------- brouillon dans le navigateur */
export const DRAFT_TTL_MS = 7 * 24 * 3600 * 1000
export type SavedDraft = { v: 1; savedAt: number; draft: Draft; assign: Draft; receipts: string[]; index: number; reached: number; withPayroll: boolean }

/** Un brouillon n'est conservé que s'il contient autre chose que les valeurs par défaut : un prénom ou un nom. */
export const draftHasContent = (d: Draft) => !blank(d.first_name) || !blank(d.last_name)

export const serializeDraft = (s: Omit<SavedDraft, 'v' | 'savedAt'>, now = Date.now()): string => JSON.stringify({ v: 1, savedAt: now, ...s } satisfies SavedDraft)

export function parseDraft(raw: string | null, now = Date.now()): SavedDraft | null {
  if (!raw) return null
  try {
    const s = JSON.parse(raw) as Partial<SavedDraft>
    if (s.v !== 1 || typeof s.savedAt !== 'number' || now - s.savedAt > DRAFT_TTL_MS || now < s.savedAt - 60_000) return null
    if (!s.draft || typeof s.draft !== 'object' || !s.assign || typeof s.assign !== 'object' || !Array.isArray(s.receipts)) return null
    return { v: 1, savedAt: s.savedAt, draft: s.draft, assign: s.assign, receipts: s.receipts.filter((x) => typeof x === 'string'), index: Number(s.index) || 0, reached: Number(s.reached) || 0, withPayroll: s.withPayroll !== false }
  } catch { return null }
}

/* --------------------------------------------------------------------------------- noms de personnes */
/** Champs de nom mis en forme à l'enregistrement (la base applique la même règle : fonction person_name). */
export const NAME_FIELDS = ['first_name', 'last_name', 'maiden_name', 'mother_first_name', 'mother_last_name', 'father_name'] as const

/** Première lettre de chaque mot en majuscule, le reste en minuscule (« n'DIAYE-sow » devient « N'Diaye-Sow »), espaces superflus retirés. */
export function personName(v: unknown): string {
  return String(v ?? '').trim().replace(/\s+/g, ' ').toLowerCase().replace(/(^|[^\p{L}\p{N}])(\p{L})/gu, (_m, sep: string, c: string) => sep + c.toLocaleUpperCase('fr'))
}

/** Mise en forme des noms avant enregistrement ; le nom complet de la mère (colonne historique) est composé de son prénom et de son nom. */
export function normalizeNames(d: Draft): Draft {
  const out: Draft = { ...d }
  for (const k of NAME_FIELDS) if (!blank(out[k])) out[k] = personName(out[k])
  if (!blank(out.mother_first_name) || !blank(out.mother_last_name)) out.mother_name = personName(`${out.mother_first_name ?? ''} ${out.mother_last_name ?? ''}`)
  return out
}

/** Le nom de jeune fille n'est demandé que pour les femmes. */
export const asksMaidenName = (d: Draft) => d.gender === 'F'

/* ------------------------------------------------------------------------ parts TRIMF et IR (référentiel 2026) */
/**
 * Règle de calcul des parts, d'après le document de référence fourni par le propriétaire (Moteur_Calcul_Paie_Senegal_Complet, Art. 174 CGI) :
 *  - IR : célibataire, veuf(ve) ou divorcé(e) = 1 ; marié(e) = 1,5 ; conjoint sans revenu à charge = +0,5 ; chaque enfant à charge = +0,5 ; plafond 5 parts.
 *  - TRIMF : 1 part (célibataire ou femme mariée salariée) ; homme marié : 1 part + 1 part par épouse sans revenu.
 * Statut : repris du document de référence, non confronté au texte de loi : à confirmer. La saisie manuelle reste possible (alerte si différente).
 */
export type PartsInput = { gender?: unknown; marital?: unknown; spouses?: unknown; children?: unknown }
export const PARTS_MEMO = [
  'Parts IR = 1 (célibataire, veuf(ve), divorcé(e)) ; 1,5 si marié(e) ; + 0,5 si le conjoint est sans revenu et à charge ; + 0,5 par enfant à charge ; plafond 5 parts (Art. 174 CGI).',
  'Parts TRIMF = 1 part (célibataire ou femme mariée salariée) ; homme marié : 1 part + 1 part par épouse sans revenu.',
  'Source : document de référence « Moteur de calcul de paie — Sénégal (référentiel 2026) ». À confirmer auprès du texte de loi.',
]

export function senegalParts(i: PartsInput): { ir: number; trimf: number } {
  const married = String(i.marital ?? '') === 'Marié(e)'
  const spouses = married ? Math.max(0, Math.floor(Number(i.spouses ?? 0)) || 0) : 0
  const kids = Math.max(0, Math.floor(Number(i.children ?? 0)) || 0)
  const ir = Math.min(5, 1 + (married ? 0.5 : 0) + (spouses > 0 ? 0.5 : 0) + 0.5 * kids)
  const trimf = married && String(i.gender ?? '') !== 'F' ? 1 + spouses : 1
  return { ir, trimf }
}

/** Écarts entre les parts saisies et le calcul automatique (alerte rouge, jamais bloquante : la saisie manuelle est permise). */
export function partsAlerts(d: Draft): Issue[] {
  const p = senegalParts({ gender: d.gender, marital: d.marital_status, spouses: d.spouses_count, children: d.children_count })
  const out: Issue[] = []
  const fmt = (n: number) => String(n).replace('.', ',')
  if (!blank(d.ir_parts) && Number(d.ir_parts) !== p.ir) out.push({ field: 'ir_parts', message: `Parts IR saisies (${fmt(Number(d.ir_parts))}) différentes du calcul automatique (${fmt(p.ir)}). Vérifiez la situation de famille.` })
  if (!blank(d.trimf_parts) && Number(d.trimf_parts) !== p.trimf) out.push({ field: 'trimf_parts', message: `Parts TRIMF saisies (${fmt(Number(d.trimf_parts))}) différentes du calcul automatique (${fmt(p.trimf)}). Vérifiez le sexe et les conjoints.` })
  return out
}

/* --------------------------------------------------------------------------- avancement d'une saisie en attente */
export type Missing = { step: StepId; message: string; blocking: boolean }

/** Avancement d'une saisie : part des champs obligatoires renseignés, points bloquants puis points à compléter. */
export function draftSummary(d: Draft, steps: StepId[], o: { payrollRequested?: boolean } = {}): { pct: number; missing: Missing[]; label: string } {
  const required = ['first_name', 'last_name', 'id_document_number', 'marital_status', 'employment_type', 'date_of_joining', 'payment_mode']
  if (isFixedTerm(d.employment_type)) required.push('contract_start', 'contract_end')
  if (o.payrollRequested) required.push('from_date')
  const filled = required.filter((k) => !blank(d[k])).length
  const missing: Missing[] = []
  for (const r of reviewIssues(d, steps, o)) for (const i of r.issues) missing.push({ step: r.step, message: i.message, blocking: true })
  for (const s of steps) if (s !== 'revue') for (const w of softWarnings(s, d)) missing.push({ step: s, message: w.message, blocking: false })
  const name = `${String(d.first_name ?? '').trim()} ${String(d.last_name ?? '').trim()}`.trim()
  return { pct: Math.round((100 * filled) / required.length), missing, label: name ? personName(name) : 'Salarié sans nom' }
}
