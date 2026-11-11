import { test } from '@playwright/test'

// Suivi des fiches du dossier de reprise (docs/recette/simulation-200/DOSSIER_DE_REPRISE.md).
// État au 11/11/2026 : RPR-01 à 15 sont corrigées (voir DOSSIER_DE_REPRISE.md) ; ces entrées restent `fixme` tant que leur parcours Playwright n'est pas écrit.
// Couverture actuelle : tests SQL (tests/sql/rpr*.sql, alertes_verrouillage_paie_incomplete), tests API (tests/api/login.lock.test.mjs), contrôles manuels scriptés.
// RPR-09 corrigée le 10/11/2026 : test SQL tests/sql/rpr09_prorata.sql (le parcours Playwright reste à écrire sur un mois ouvert).
// Quand une fiche est corrigée : écrire le parcours, retirer `.fixme` et passer la fiche au vert dans le dossier de reprise.
const FICHES: [string, string][] = [
  ['RPR-01', 'calcul sans structure salariale : message visible et blocage (P1-06)'],
  ['RPR-02', 'approbation depuis l’écran avec un seul rôle : écran et base alignés (P5-04, P5-06)'],
  ['RPR-03', 'verrouillage de connexion par couple compte + adresse, pas collectif (X-01, D-58)'],
  ['RPR-04', 'dérogation : champ motif dans le dialogue (P1-09, P1-10)'],
  ['RPR-05', 'période réouverte : bouton Recalculer (P3-02)'],
  ['RPR-06', 'création de salarié fiabilisée et découpée (P5-01, P5-02, P7-01)'],
  ['RPR-07', 'date d’effet par défaut d’une structure (P1-07)'],
  ['RPR-08', 'plafond de retenue sur prêt : base et dépôt alignés (R-08, R-09, D-30/D-53)'],
  ['RPR-10', 'référentiels manquants (P1-04, P1-15)'],
  ['RPR-11', 'ergonomie, textes et données (P1-01 à P1-05, P1-13)'],
  ['RPR-12', 'contrôles bloquants lisibles (P5-08, P5-09)'],
  ['RPR-13', 'déclaration d’embauche signalée plus tôt (P1-08)'],
  ['RPR-14', 'paiements individuels et matricules (P1-12, P1-14)'],
  ['RPR-15', 'performance à 175–200 salariés (P8-01, P9-01)'],
]

for (const [ref, intitule] of FICHES) {
  test.fixme(`${ref} — ${intitule}`, async () => {})
}
