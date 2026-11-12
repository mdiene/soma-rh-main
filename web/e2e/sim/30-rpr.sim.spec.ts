import { test } from '@playwright/test'

// Suivi des fiches du dossier de reprise (docs/recette/simulation-200/DOSSIER_DE_REPRISE.md).
// État au 11/11/2026 : RPR-01 à 15 sont corrigées. Parcours Playwright écrits dans 31-rpr-mutating.sim.spec.ts : RPR-01, 02, 04, 06, 10, 12, 14. Restent `fixme` (couverts par SQL/API/unitaires) : RPR-03, 05, 07, 08, 11, 13, 15.
// Couverture actuelle : tests SQL (tests/sql/rpr*.sql, alertes_verrouillage_paie_incomplete), tests API (tests/api/login.lock.test.mjs), contrôles manuels scriptés.
// RPR-09 corrigée le 10/11/2026 : test SQL tests/sql/rpr09_prorata.sql (le parcours Playwright reste à écrire sur un mois ouvert).
// Quand une fiche est corrigée : écrire le parcours, retirer `.fixme` et passer la fiche au vert dans le dossier de reprise.
const FICHES: [string, string][] = [
  ['RPR-03', 'verrouillage de connexion par couple compte + adresse, pas collectif (X-01, D-58)'],
  ['RPR-05', 'période réouverte : bouton Recalculer (P3-02)'],
  ['RPR-07', 'date d’effet par défaut d’une structure (P1-07)'],
  ['RPR-08', 'plafond de retenue sur prêt : base et dépôt alignés (R-08, R-09, D-30/D-53)'],
  ['RPR-11', 'ergonomie, textes et données (P1-01 à P1-05, P1-13)'],
  ['RPR-13', 'déclaration d’embauche signalée plus tôt (P1-08)'],
  ['RPR-15', 'performance à 175–200 salariés (P8-01, P9-01)'],
]

for (const [ref, intitule] of FICHES) {
  test.fixme(`${ref} — ${intitule}`, async () => {})
}
