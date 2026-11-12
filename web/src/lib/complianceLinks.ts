/** Lien « Corriger » d'un constat : l'écran où l'on modifie l'élément en cause. */
export type FindingRef = { rule_id?: string; entity: string; entity_id: string; employee_id: string | null; fix_target: string; message: string }

type Field = [key: string, label: string]  // clé `data-fix` de la page ouverte, libellé du lien
const CDD: Field[] = [['contract_start', 'Début du contrat'], ['contract_end', 'Fin du contrat'], ['employment_type', 'Type de contrat'], ['relieving_date', 'Date de sortie']]
const PIECE: Field[] = [['id_document_number', 'N° de la pièce'], ['id_expiry_date', 'Date d’expiration']]
/** Règle → champs à corriger, un lien chacun. */
const FIELDS: Record<string, Field[]> = {
  'EMB-DECL': [['hire_declaration_ref', 'Référence de la déclaration'], ['hire_declared_on', 'Date de la déclaration']],
  'EMB-AFFIL': [['date_of_joining', 'Date d’entrée'], ['affiliation_date', 'Date d’affiliation']],
  'CDD-DUREE': CDD, 'LEGAL-CDD_ECHEANCE': CDD, 'LEGAL-CDD_ECHU': CDD,
  'LEGAL-PIECE_ECHEANCE': PIECE, 'LEGAL-PIECE_EXPIREE': PIECE,
  'LEGAL-SOUS_SMIG': [['base_salary', 'Salaire de base']],
  'LEGAL-HABILITATION_ECHUE': [['ind_habilitation_expiry', 'Échéance de l’habilitation']],
  'LEGAL-HABILITATION_ECHEANCE': [['ind_habilitation_expiry', 'Échéance de l’habilitation']],
  'LEGAL-PERMIS_ECHU': [['tr_permis_expiry', 'Échéance du permis']],
  'LEGAL-PERMIS_ECHEANCE': [['tr_permis_expiry', 'Échéance du permis']],
  'LEGAL-MISSION_INTERIM_DUREE_MAX': [['module_soma-mod-services-interim-sn', 'Fiche métier Intérim']],
  'LEGAL-MISSION_INTERIM_ECHEANCE': [['module_soma-mod-services-interim-sn', 'Fiche métier Intérim']],
  'LEGAL-MISSION_INTERIM_CUMUL': [['module_soma-mod-services-interim-sn', 'Fiche métier Intérim']],
  'LEGAL-AGREMENT_ETT_MANQUANT': [['ett_agreement_number', 'N° d’agrément']],
  'LEGAL-ATTESTATION_REGULARITE_MANQUANTE': [['social_regularity_cert_date', 'Date de l’attestation']],
  'LEGAL-ATTESTATION_REGULARITE_ECHUE': [['social_regularity_cert_date', 'Date de l’attestation']],
  'LEGAL-ATTESTATION_REGULARITE_ECHEANCE': [['social_regularity_cert_date', 'Date de l’attestation']],
  'RET-04': [['retenues', 'Retenues du bulletin']],
  'RET-PLAFOND': [['retenues', 'Retenues du bulletin']],
  'LEGAL-RETENUE_LOGEMENT_PLAFOND': [['retenues', 'Retenues du bulletin']],
  'PLANNING-DUREE_HEBDO_DEPASSEE': [['planning_conformite', 'Conformité de la semaine']],
  'PLANNING-REPOS_HEBDO_MANQUANT': [['planning_conformite', 'Conformité de la semaine']],
}

/** Liens de correction d'un constat : un par champ concerné. `back` = id du constat, pour revenir au centre. */
export function fixLinks(f: FindingRef, back?: string): { to: string; label: string }[] {
  const base = fixLinkBase(f)
  const add = (to: string, p: string) => `${to}${to.includes('?') ? '&' : '?'}${p}`
  const fields = (f.rule_id && FIELDS[f.rule_id]) || null
  const links = fields ? fields.map(([k, label]) => ({ to: add(base.to, `surligne=${k}`), label })) : [base]
  return back ? links.map((l) => ({ ...l, to: add(l.to, `retour=${encodeURIComponent(back)}`) })) : links
}
/** Champs de la fiche salarié corrigeables sur place : clé = colonne de `employees`. */
export const EMPLOYEE_FIELDS: Record<string, { label: string; type: 'date' | 'text' | 'contract' }> = {
  hire_declaration_ref: { label: 'Référence de la déclaration d’embauche', type: 'text' },
  hire_declared_on: { label: 'Date de la déclaration d’embauche', type: 'date' },
  date_of_joining: { label: 'Date d’entrée', type: 'date' },
  affiliation_date: { label: 'Date d’affiliation à la sécurité sociale', type: 'date' },
  contract_start: { label: 'Début du contrat en cours', type: 'date' },
  contract_end: { label: 'Fin du contrat en cours', type: 'date' },
  relieving_date: { label: 'Date de sortie', type: 'date' },
  employment_type: { label: 'Type de contrat', type: 'contract' },
  id_document_number: { label: 'N° CNI ou passeport', type: 'text' },
  id_expiry_date: { label: 'Date d’expiration de la pièce', type: 'date' },
}

/** Clés de champ du constat (même ordre que les liens), pour la correction sur place. */
export const fieldKeys = (f: FindingRef): string[] => (FIELDS[f.rule_id ?? ''] ?? []).map(([k]) => k)
/** Mois de paie (AAAA-MM-01) cité par le constat « Cotisations de MM/AAAA : échéance… ». */
export function contributionMonth(message: string): string | null {
  const m = /(\d{2})\/(\d{4})/.exec(message)
  return m ? `${m[2]}-${m[1]}-01` : null
}
export const fixLink =(f: FindingRef) => fixLinks(f)[0]

function fixLinkBase(f: FindingRef): { to: string; label: string } {
  switch (f.entity) {
    case 'employee':
      return { to: `/salaries/${encodeURIComponent(f.employee_id ?? f.entity_id)}`, label: 'Ouvrir la fiche du salarié' }
    case 'salary_slip':
      return { to: `/bulletins/${encodeURIComponent(f.entity_id)}`, label: 'Ouvrir le bulletin' }
    case 'cotisation':
      return { to: `/paie/cotisations${contributionMonth(f.message) ? `?mois=${contributionMonth(f.message)}` : ''}`, label: 'Enregistrer le versement' }
    case 'planning': {
      // le message cite « semaine du JJ/MM/AAAA » : on ouvre cette semaine
      const m = /semaine du (\d{2})\/(\d{2})\/(\d{4})/.exec(f.message)
      return { to: m ? `/planning?semaine=${m[3]}-${m[2]}-${m[1]}` : '/planning', label: 'Ouvrir le planning' }
    }
    case 'parameter':
      return { to: '/centre-conformite', label: 'Ouvrir les constantes' }
    case 'company':
      return f.fix_target === 'parameter'
        ? { to: '/modules', label: 'Ouvrir les paramètres du module' }
        : { to: '/parametres?onglet=societe', label: 'Ouvrir la fiche société' }
    default:
      return { to: '/centre-conformite', label: 'Ouvrir le centre' }
  }
}
