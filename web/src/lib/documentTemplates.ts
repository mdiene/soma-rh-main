/** Modèles de documents (L6-04) : champs disponibles et remplacement. Texte brut, paragraphes séparés par une ligne vide. */

export const TEMPLATE_FIELDS: { key: string; label: string }[] = [
  { key: 'societe', label: 'Raison sociale' },
  { key: 'civilite', label: 'Madame / Monsieur' },
  { key: 'prenom', label: 'Prénom' },
  { key: 'nom', label: 'Nom (majuscules)' },
  { key: 'matricule', label: 'Matricule' },
  { key: 'naissance', label: 'Naissance, avec sa virgule (« , né le … à … »), vide si inconnue' },
  { key: 'etat', label: '« est » ou « a été »' },
  { key: 'employe', label: '« employé » ou « employée »' },
  { key: 'fonction', label: 'Fonction, avec son préfixe (« en qualité de … »), vide si inconnue' },
  { key: 'date_embauche', label: "Date d'entrée" },
  { key: 'fin', label: 'Date de sortie (« jusqu’au … »), vide si en poste' },
  { key: 'e', label: 'Accord au féminin : « e » ou vide' },
  { key: 'effectif', label: 'Phrase « fait toujours partie de notre effectif » (vide si sorti)' },
  { key: 'salaire', label: 'Phrase de rémunération du dernier bulletin validé' },
  { key: 'date_du_jour', label: 'Date du jour' },
  { key: 'lieu', label: 'Lieu de signature' },
]

const COMMON = "Nous soussignés, {{societe}}, attestons que {{civilite}} {{prenom}} {{nom}}{{naissance}}, matricule {{matricule}}, {{etat}} {{employe}} au sein de notre société{{fonction}} depuis le {{date_embauche}}{{fin}}."
const CLOSING = "La présente attestation est délivrée à l'intéressé{{e}}, sur sa demande, pour servir et valoir ce que de droit."

/** Texte de secours si le modèle n'est pas en base (identique aux modèles de départ de la migration). */
export const DEFAULT_TEMPLATES: Record<'attestation_travail' | 'attestation_salaire', string> = {
  attestation_travail: `${COMMON}\n\n{{effectif}}\n\n${CLOSING}`,
  attestation_salaire: `${COMMON}\n\n{{salaire}}\n\n${CLOSING}`,
}

const KNOWN = new Set(TEMPLATE_FIELDS.map((f) => f.key))
const FIELD_RE = /\{\{\s*([a-z0-9_]+)\s*\}\}/g

/** Champs écrits dans le texte qui n'existent pas (faute de frappe) : à signaler avant l'enregistrement. */
export function unknownFields(body: string): string[] {
  return [...new Set([...body.matchAll(FIELD_RE)].map((m) => m[1]).filter((k) => !KNOWN.has(k)))]
}

/** Remplace les champs ; un champ inconnu reste visible tel quel (jamais effacé en silence). Retire les paragraphes devenus vides. */
export function renderTemplate(body: string, values: Record<string, string>): string[] {
  return body
    .split(/\n\s*\n/)
    .map((p) => p.replace(FIELD_RE, (m, k: string) => (k in values ? values[k] : m)).replace(/[ \t]+/g, ' ').trim())
    .filter((p) => p.length > 0)
}
