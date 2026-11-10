# Prompt Claude Code — Correctifs issus de la simulation 10 → 200 salariés (RPR-01 à RPR-15)

Tu travailles **uniquement** dans `C:\IT-Mozaic\soma-rh-main` (dépôt actif, GitHub `mdiene/soma-rh-main`, branche `main`) : React 18/Vite/TS, Postgres 17 + PostgREST, gateway `api/server.mjs`, DB `soma_rh`, conteneurs `soma-rh-local-postgres-1`, `-api-1`, `-postgrest-1`. Ne lis, n'écris et ne lance rien dans `C:\IT-Mozaic\SOMA-RH-local` (ancien dossier de simulation, conservé tel quel) : tous les chemins relatifs de ce document (`docs/`, `db/`, `tests/`, `scripts/`, `web/`, `api/`) se résolvent depuis `C:\IT-Mozaic\soma-rh-main`. Langue de travail : français.

## 0. À lire d'abord
`docs/recette/simulation-200/RAPPORT_VERT_ROUGE.md`, `DOSSIER_DE_REPRISE.md`, `JOURNAL_PALIERS.md`, `PROPOSITION_PAIEMENTS_INDIVIDUELS.md`, `docs/recette/PROMPT_SIMULATION_200_SALARIES.md` (§11), les migrations `20261107120000_d43_…`, `20261107130000_d30_d53_…`, `20261109170000_d64_…`.

## 1. Décisions du propriétaire (09/11/2026) — à appliquer, ne pas rediscuter
1. **Prorata D-56** : pour une entrée ou une sortie en cours de mois, le salaire est payé au prorata des **jours travaillés**. Base : jours ouvrables effectivement travaillés depuis la date d'entrée (ou jusqu'à la date de sortie) ÷ jours ouvrables du mois, hors jours fériés. Prévoir un paramètre `proration_basis` (défaut `ouvrables`, alternative `calendaires`) modifiable par l'admin, et vérifier la cohérence avec `docs` du Code du travail et de la CCNI avant de figer la formule. Le bulletin doit afficher le nombre de jours payés.
2. **Approbation de la paie** : le rôle approbateur est **l'administrateur et le détenteur du rôle paie** (pas le rôle rh). Aligner la base (`transition_payroll_entry`, migration D-43 corrigée par une nouvelle migration) sur l'écran. Garder la séparation des tâches : l'approbateur ne peut pas être la personne qui a envoyé en revue, sauf dérogation admin avec motif. Le rôle rh n'approuve pas ; il peut consulter la page Gouvernance en lecture seule.
3. **Plafond de retenue sur prêt** : variable de configuration globale, valeur par défaut **1/3 du salaire (33,33 %)**, **modifiable au niveau du salarié** (surcharge). Qui modifie : admin, rh et paie, avec journalisation (ancienne et nouvelle valeur, auteur). Corriger l'écart entre `set_loan_max_rate` en base (admin seul) et le fichier de migration du dépôt (admin/rh/paie) : une seule source de vérité, plus de demande de modification de constantes. Règle D-30 : le net ne devient jamais négatif.
4. **Paiements individuels** : **ne rien implémenter**. Une proposition est dans `PROPOSITION_PAIEMENTS_INDIVIDUELS.md` ; seulement la relire et signaler tout point bloquant pour le futur.
5. **Base** : conserver la base simulée. Ne jamais restaurer ni vider, ne jamais modifier la référence de `verify-payroll.ps1`.

## 2. Règles de travail
- Branche `fix/rpr-simulation-200` ; un commit par fiche RPR (message : `fix(rpr-XX): …`).
- Chaque changement de base = une migration horodatée dans `db/migrations/`, un `db/rollback/…_down.sql`, un test `tests/sql/…`. Application : `docker cp` puis `psql -f`, puis `notify pgrst, 'reload schema'`. Accents dans les tests SQL via `U&'…'`. Les périodes clôturées restent immuables.
- Ne pas casser les 9 périodes simulées (2026-01 à 2026-09, 200 salariés) : après chaque lot, `npx playwright test -c playwright.sim.config.ts 20-roles 10-croissance` doit rester vert (les specs sont idempotentes).
- Adapter les specs : plus de compte `sim-rhpaie` pour l'approbation (utiliser `paie` pour envoyer en revue et `paie2` ou `admin` pour approuver) ; l'entrée UC-INTERDIT pour rh sur `/paie/gouvernance` devient une page en lecture seule sans bouton d'étape.
- Après chaque lot : `npm run typecheck`/`tsc`, tests unitaires, tests SQL, specs Playwright concernées, puis mise à jour de `DOSSIER_DE_REPRISE.md` (statut par fiche), `JOURNAL_PALIERS.md`, `BATTERIE_TESTS_RECETTE.md`, `RESULTATS` ; cocher D-30/D-53, D-56, D-58, D-64.
- Une capture d'écran Playwright (`docs/guide-utilisateur/captures-sim/`) pour chaque écran modifié.
- Arrêt et question au propriétaire uniquement pour une décision irréversible ; sinon choisir et documenter.

## 3. Lots, dans cet ordre

### Lot A — bloquants (P1)
- **RPR-01** : un calcul avec des salariés sans structure salariale doit afficher la liste des non-calculés, empêcher « Envoyer en revue » tant qu'il en reste, et ne jamais laisser une paie Calculée avec 0 bulletin sans message.
- **RPR-02** : voir décision 2. Boutons d'étape visibles pour admin et paie selon l'état ; message de refus clair (qui peut faire quoi). Tests SQL + Playwright pour chaque transition et chaque rôle (rh refusé, manager/salarié refusés).
- **RPR-03** : verrouillage de connexion par couple compte + adresse (plus de blocage collectif) ; limite par adresse séparée et plus haute ; alerte à l'admin ; test : N échecs sur A ne bloquent pas B (`api/server.mjs`).

### Lot B — calculs et prêts (P2)
- **RPR-09** : prorata D-56 (décision 1), pour entrées et sorties ; tests chiffrés (entrée le 15/01, S0299 à titre d'exemple de non-régression : l'ancien bulletin clos reste inchangé) ; paramètre `proration_basis`.
- **RPR-08** : plafond de prêt (décision 3), surcharge par salarié, écran de configuration, journal ; net jamais négatif. Migrations + tests SQL.

### Lot C — workflow et formulaires (P2)
- **RPR-04** : champ « motif de dérogation » vide et obligatoire dans les deux chemins (validation directe et revue/approbation) ; ne plus pré-remplir avec le message d'erreur.
- **RPR-05** : bouton « Recalculer » sur statut Réouverte (admin, motif déjà saisi), journalisé.
- **RPR-06** : message explicatif pour le rôle rh sur la section structure (lecture seule) ; bouton Enregistrer inactif tant que la structure n'est pas chargée ; erreur `structure_id` traduite ; confirmation « Fiche enregistrée » persistante.
- **RPR-07** : date d'effet de la structure par défaut = date d'embauche, avertissement si elle est postérieure à la période courante.
- **RPR-12** : refus d'approbation avec la liste des contrôles bloquants ; avertissement dès l'envoi en revue.

### Lot D — confort et référentiels (P2/P3)
- **RPR-10** : écran de gestion des départements et champ sur la fiche ; vérifier `shift_types` et `work_posts` (créer les tables si /planning en dépend).
- **RPR-11** : boutons d'action visibles à 1280 px ; Entrée valide l'ajout d'un référentiel ; corriger la convention « Prestations de services » (catégories) ; corriger le texte Paramètres > Accès (inscription fermée, D-016).
- **RPR-13** : indicateur « déclaration d'embauche manquante » sur la fiche.
- **RPR-14** : séquence de matricule paramétrable (préfixe et départ). Pas d'implémentation des paiements.
- **RPR-15** : indicateur de progression pendant l'enregistrement des variables ; mesurer et optimiser l'écriture (en lot) pour 200 salariés ; temps de chargement de `/paie/variables`.

## 4. Livrable final
Un compte rendu `docs/recette/simulation-200/CORRECTIFS_RESULTATS.md` : par fiche RPR, statut (corrigé, partiel, reporté), fichiers modifiés, migration, test, capture. Résultat des specs Playwright. Liste des points qui nécessitent encore une décision.
