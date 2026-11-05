/**
 * Garde-fous de saisie pour la paie : fonctions pures (aucun accès réseau ni DOM), testables sous Node.
 * Elles produisent des avertissements lisibles pour les RH ; elles ne remplacent pas les contrôles de la base.
 * Aucun chiffre légal n'est codé ici : les seuils viennent des paramètres en vigueur (table payroll_settings).
 */

export type Warning = { level: 'erreur' | 'alerte'; field: string; message: string }

/** Champs de payroll_settings concernés par les contrôles (sous-ensemble). */
export type RateSettings = {
  monthly_hours: number | null
  smig_hourly: number | null
  cfce_rate: number | null
  ipres_rg_ceiling: number | null
  ipres_rg_rate: number | null
  ipres_rg_employee_share: number | null
  ipres_rc_ceiling: number | null
  ipres_rc_rate: number | null
  ipres_rc_employee_share: number | null
  css_ceiling: number | null
  css_af_rate: number | null
  css_at_rate: number | null
  ipm_ceiling: number | null
  ipm_rate: number | null
  ipm_employee_share: number | null
}

const RATE_FIELDS: [keyof RateSettings, string][] = [
  ['cfce_rate', 'CFCE'], ['ipres_rg_rate', 'IPRES régime général'], ['ipres_rg_employee_share', 'Part salariale IPRES régime général'],
  ['ipres_rc_rate', 'IPRES cadres'], ['ipres_rc_employee_share', 'Part salariale IPRES cadres'],
  ['css_af_rate', 'CSS prestations familiales'], ['css_at_rate', 'CSS accidents du travail'],
  ['ipm_rate', 'IPM'], ['ipm_employee_share', 'Part salariale IPM'],
]
const CEILING_FIELDS: [keyof RateSettings, string][] = [
  ['ipres_rg_ceiling', 'Plafond IPRES régime général'], ['ipres_rc_ceiling', 'Plafond IPRES cadres'],
  ['css_ceiling', 'Plafond CSS'], ['ipm_ceiling', 'Plafond IPM'],
]

/** SMIG mensuel déduit des paramètres : taux horaire × heures mensuelles. Retourne 0 si l'un des deux manque. */
export function monthlyMinimumWage(s: Pick<RateSettings, 'smig_hourly' | 'monthly_hours'>): number {
  return Math.max(0, (s.smig_hourly ?? 0) * (s.monthly_hours ?? 0))
}

/** Contrôle le salaire de base saisi pour un CDI ou un CDD. Un salaire vide est accepté (la catégorie fixe le minimum). */
export function checkBaseSalary(base: number | null | undefined, s: Pick<RateSettings, 'smig_hourly' | 'monthly_hours'>): Warning[] {
  if (base == null || Number.isNaN(base)) return []
  if (base < 0) return [{ level: 'erreur', field: 'base_salary', message: 'Le salaire de base ne peut pas être négatif.' }]
  const min = monthlyMinimumWage(s)
  if (min > 0 && base > 0 && base < min) {
    return [{ level: 'alerte', field: 'base_salary', message: `Salaire inférieur au SMIG mensuel paramétré (${Math.round(min).toLocaleString('fr-FR')} F). Vérifiez la saisie ou le temps de travail.` }]
  }
  return []
}

/**
 * Contrôle un jeu de paramètres avant enregistrement : taux entre 0 et 1, plafonds positifs, cohérence entre plafonds,
 * et alerte si un plafond ou un taux baisse par rapport à la version précédente (cas inhabituel en droit social).
 */
export function checkRateSettings(next: RateSettings, previous?: RateSettings | null): Warning[] {
  const out: Warning[] = []
  const baisse = (k: keyof RateSettings, label: string, v: number) => {
    const p = previous?.[k]
    if (p != null && v < p) out.push({ level: 'alerte', field: k, message: `${label} : baisse par rapport à la version précédente (${p} → ${v}). Confirmez la source officielle.` })
  }
  for (const [k, label] of RATE_FIELDS) {
    const v = next[k]
    if (v == null) { out.push({ level: 'erreur', field: k, message: `${label} : valeur manquante.` }); continue }
    if (v < 0 || v > 1) out.push({ level: 'erreur', field: k, message: `${label} : un taux s'exprime en fraction entre 0 et 1 (0,056 pour 5,6 %).` })
    baisse(k, label, v)
  }
  for (const [k, label] of CEILING_FIELDS) {
    const v = next[k]
    if (v == null || v <= 0) { out.push({ level: 'erreur', field: k, message: `${label} : doit être strictement positif.` }); continue }
    baisse(k, label, v)
  }
  if (next.ipres_rg_ceiling && next.ipres_rc_ceiling && next.ipres_rc_ceiling <= next.ipres_rg_ceiling) {
    out.push({ level: 'erreur', field: 'ipres_rc_ceiling', message: 'Le plafond IPRES des cadres doit dépasser celui du régime général.' })
  }
  if (!next.smig_hourly || next.smig_hourly <= 0) out.push({ level: 'erreur', field: 'smig_hourly', message: 'SMIG horaire : doit être strictement positif.' })
  if (!next.monthly_hours || next.monthly_hours <= 0) out.push({ level: 'erreur', field: 'monthly_hours', message: 'Heures mensuelles : doit être strictement positif.' })
  return out
}

/**
 * Détermine comment enregistrer une modification de paramètres légaux :
 *  - date postérieure à la version en cours : nouvelle version datée (l'historique est conservé) ;
 *  - même date : correction de la version en cours ;
 *  - date antérieure : refusée, car elle réécrirait des périodes déjà calculées.
 */
export function settingsSaveMode(effectiveFrom: string, currentEffectiveFrom: string): 'nouvelle_version' | 'correction' | 'refus' {
  if (effectiveFrom > currentEffectiveFrom) return 'nouvelle_version'
  if (effectiveFrom === currentEffectiveFrom) return 'correction'
  return 'refus'
}
