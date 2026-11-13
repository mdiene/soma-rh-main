/** Identité et versions de l'application (page « À propos » et « Sauvegardes et versions »). */

export const APP_NAME = 'SOMA-RH'

export type Release = { version: string; date: string; title: string; changes: string[] }

/** Journal des versions : la plus récente en premier. La numérotation a été introduite avec la version 1.0.0 ; l'historique antérieur est dans Git. */
export const RELEASES: Release[] = [
  {
    version: '1.0.1', date: '2026-11-13', title: 'Menu latéral façon Supabase',
    changes: [
      'La colonne d’icônes s’élargit au survol et affiche le nom des espaces, avec leurs compteurs.',
      'Le volet d’un espace s’ouvre devant le contenu de la page, y compris devant les colonnes des tableaux.',
    ],
  },
  {
    version: '1.0.0', date: '2026-11-13', title: 'Saisie des salariés, menu et pages d’information',
    changes: [
      'Assistant de saisie : n° de CNI ou de passeport obligatoire et unique, noms mis en forme (Prénom, Nom), nom de jeune fille, prénom et nom de la mère.',
      'Parts TRIMF et IR calculées automatiquement (référentiel 2026), saisie manuelle possible avec alerte rouge en cas d’écart.',
      'Saisies mises en attente, reprises depuis « Saisies en cours » avec l’avancement et les points manquants.',
      'Menu latéral : déploiement au survol, fermeture au clic ou à la sortie de la souris, bouton pour l’épingler ouvert.',
      'Menu « À propos » : aide, informations, tarification et services, conditions d’utilisation, confidentialité, sauvegardes et versions.',
    ],
  },
]

/** Étapes antérieures à la numérotation, datées d'après le journal du projet (sans numéro de version). */
export const HISTORY: { date: string; title: string; changes: string[] }[] = [
  { date: '2026-11-12', title: 'Connexion par téléphone, cotisations, conformité', changes: [
    'Connexion des salariés par numéro de téléphone (autorisation par l’administrateur), en local et en ligne.',
    'Suivi des versements de cotisations par mois et par caisse ; fiche du constat et corrections ciblées du Centre de conformité.',
    'Verrou de connexion persistant en base ; corrections issues des revues de sécurité.',
  ] },
  { date: '2026-11-11', title: 'Corrections de la simulation à 200 salariés', changes: [
    'Prorata d’entrée et de sortie, recalcul d’une paie rouverte, plafond de prêt, matricule paramétrable, départements, contrôles avant envoi en revue.',
  ] },
]

export const APP_VERSION = RELEASES[0].version

/** Identification du build (vide en développement si Git est absent). */
export const BUILD = { commit: typeof __APP_COMMIT__ === 'string' ? __APP_COMMIT__ : '', date: typeof __APP_BUILD_DATE__ === 'string' ? __APP_BUILD_DATE__ : '' }

/** Coordonnées de l'éditeur et du support : renseignées par l'administrateur du déploiement (variables d'environnement), jamais codées en dur. */
export const CONTACT = {
  editor: (import.meta.env.VITE_EDITOR_NAME as string | undefined) ?? '',
  email: (import.meta.env.VITE_SUPPORT_EMAIL as string | undefined) ?? '',
  phone: (import.meta.env.VITE_SUPPORT_PHONE as string | undefined) ?? '',
}

/** Environnement détecté d'après l'adresse de l'API. */
export const environment = () => {
  const url = String(import.meta.env.VITE_API_URL ?? '')
  return /localhost|127\.0\.0\.1/.test(url) ? 'Local (poste de développement)' : 'En ligne'
}
