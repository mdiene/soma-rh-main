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
  if (id === 'identite' && blank(d.id_document_number)) w.push({ field: 'id_document_number', message: 'Aucun numéro de pièce d’identité : il pourra être complété sur la fiche.' })
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
