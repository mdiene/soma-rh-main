# Retours Copilot / Claude

## CP-01 — Retours proposés (rédigés par Claude : la réponse de Copilot ne reposait sur aucune lecture des migrations)

| Proposition | Supprime | Données perdues | Dépendances / risques |
|---|---|---|---|
| equipe_soldes | politique `leave_alloc_select_team` | aucune | les managers perdent la vue des soldes de leur équipe |
| Dev03_journal_comptable | 3 fonctions (journal, équilibre, imputation) | aucune | `export_payroll_journal` est redéfinie par `20261107100000_mois_valides_payes_clotures` (et appelée par `tests/perf`) : défaire celle-ci d'abord, sinon le retour supprime la version récente |
| Dev04_IPRES_DGID | `export_ipres_css`, `etat_dgid` | aucune | les fichiers `_backup` et `_fixed` redéfinissent les mêmes fonctions : doublons à trancher (voir point 1) |
| Dev05_notifications_log | table `notifications_log`, `send_notification`, `process_notifications` | tout l'historique des notifications | aucune autre migration ne les cite |
| Dev09_recrutement… | 4 tables | toutes les candidatures, formations, évaluations saisies | aucune FK entrante trouvée |

### Proposition détaillée : equipe_soldes
- **Supprime** : politique `leave_alloc_select_team` sur `public.leave_allocations`
- **Données perdues** : aucune donnée de table n'est supprimée, seulement la politique d'accès
- **Dépendances / risques** : les managers perdent la vue des soldes de leur équipe ; cette politique devait permettre le filtrage par équipe

### Proposition détaillée : Dev03_journal_comptable
- **Supprime** : 3 fonctions `public.check_journal_imputation`, `public.validate_journal_balance`, `public.export_payroll_journal`
- **Données perdues** : aucune donnée de table n'est supprimée, seulement les fonctions de journal comptable
- **Dépendances / risques** : `20261107100000_mois_valides_payes_clotures` redéfinit `export_payroll_journal` ; cette migration doit être défaitue en premier. Fonction aussi appelée par `tests/perf`

### Proposition détaillée : Dev04_IPRES_DGID
- **Supprime** : fonctions `public.etat_dgid` et `public.export_ipres_css`
- **Données perdues** : aucune donnée de table n'est supprimée, seulement ces 2 fonctions spécifiques
- **Dépendances / risques** : les fichiers `_backup` et `_fixed` redéfinissent les mêmes fonctions : il faut en garder un seul (voir anomalie 1)

### Proposition détaillée : Dev05_notifications_log
- **Supprime** : fonction `public.process_notifications`, fonction `public.send_notification`, table `public.notifications_log`
- **Données perdues** : tout l'historique des notifications est perdu
- **Dépendances / risques** : aucune autre migration ne cite ces objets ; attention à la conformité RLS (voir anomalie 3)

### Proposition détaillée : Dev09_recrutement…
- **Supprime** : tables `public.evaluations`, `public.trainings`, `public.candidatures`, `public.job_postulations`
- **Données perdues** : toutes les candidatures, formations, évaluations saisies sont supprimées
- **Dépendances / risques** : aucune FK entrante trouvée ; ordre inverse des clés étrangères (candidatures dépend de job_postulations) doit être respecté dans le retrait

### Anomalies relevées
1. **Dev04 : trois fichiers au même préfixe `20261105100000`** (`_IPRES_DGID`, `_backup`, `_fixed`). Un seul doit rester.
2. **Dev09 est cassée.** Ses lignes finales exécutent `drop table …` (dont `drop table if not exists`, syntaxe invalide) : la migration échoue, ou supprime ses propres tables. Retirer ce bloc.
3. **Dev09 et Dev05 : aucune RLS ni politique** sur `notifications_log`, `job_postulations`, `candidatures`, `trainings`, `evaluations`, contraire à la règle du projet (RLS + `has_role`). Données personnelles exposées.
4. Dev09 est décrite « si validé » ; son en-tête cite un retour qui n'existait pas.
5. Rien de ceci n'a été testé sur la base ; propositions non copiées dans `db/rollback/`.

---

## CP-02 — Relecture par Claude (2026-11-06)
Trois défauts corrigés avant commit :
1. `.gitattributes` était invalide (`* .sql eol=lf` : le motif `*` recevait des attributs nommés `.sql`…) et la dernière ligne imposait `eol=crlf` à **tous** les fichiers, y compris `scripts/check-migrations.sh` (un script bash en CRLF échoue sur la CI Linux). Réécrit en `*.sql text eol=lf`, etc., `*.ps1 text eol=crlf`.
2. `ci.yml` : l'étape `node --test tests/unit` s'exécutait dans `web/` (chemin inexistant) et, en local, `node --test <dossier>` échoue sous Node 24. Remplacée par `node --test ../tests/unit/*.test.mjs` (19 tests passent depuis `web/`). Une marque BOM en tête du fichier est retirée.
3. `scripts/check-migrations.sh` : le test des noms non ASCII provoquait « syntax error in conditional expression » ; corrigé (grep en `LC_ALL=C`). L'allowlist contient maintenant les 4 préfixes en doublon connus (H3).
Toujours non couvert par la CI : les tests SQL (`tests/sql`, base requise), `verify-payroll`, les tests d'API (`tests/api`).

## CP-03 — Audit de web/src (refait par Claude : le rapport de Copilot listait des requêtes correctes comme constats et jugeait « Haute » un calcul de jours)

**A. Arrondis hors `fcfa()`** — aucun montant stocké ou transmis n'est arrondi ; tous les cas sont de l'affichage ou de l'export. À noter :
- `PayrollPaymentsPage.tsx:69` : `Math.round(net_pay)` dans l'**export** des paiements (fichier envoyé à la banque ?) : arrondi voulu à confirmer. Gravité moyenne.
- `EmployeeDetailPage.tsx:266`, `SimulatorPage.tsx:32` : surcalaire arrondi à 2 décimales avant d'être saisi/simulé (le montant résolu par la base est tronqué). Basse.
- `PayrollEntryExtras.tsx:23` : comparaison du net actuel et précédent à l'unité près (voulu). Basse.
- `PayrollBookPrintPage.tsx:45-46`, `PayrollForecast.tsx:69`, `DashboardPage.tsx`, `PilotagePage.tsx`, `MySpacePage.tsx`, `GroupedTable.tsx:51` : affichage, pourcentages, graphiques. Basse.
Aucun `toFixed`.

**B. Rôles et données personnelles** — aucune écriture dans la console ; `localStorage` n'est utilisé que par `OrganigrammePage.tsx:25-26` (préférences d'affichage, avec `try/catch`). Les routes sensibles sont gardées par `RoleGuard` dans `App.tsx` ; la base applique la RLS. Une revue page par page des boutons d'écriture sans `can()` n'a **pas** été faite. Gravité : à instruire (moyenne).

**C. Palette** — nombreuses couleurs hexadécimales en dur hors palette `ink/paper/river/phosphate/signal` : `AnnualSynthesis.tsx:116-124` (graphique), `AttestationModal.tsx:53,89` et `EmployeeFiche.tsx` (`#1D2A33`, `#52606B`, `#D5DBE0` : documents imprimés), `GroupedTable.tsx:34-40,173` (`#E9ECEA`, `#EBD27A`…), `DashboardPage.tsx:163`. Souvent proches de la palette (graphiques et impressions) ; à remplacer par des jetons Tailwind. Basse. Aucun texte d'interface non français relevé.

**D. TanStack Query** — non audité de façon exhaustive : le rapport de Copilot ne citait que des requêtes correctes. À faire avec un contrôle automatique (requêtes `useQuery` dont le résultat n'est lu ni par `isError` ni par `ErrorNote`).

## CP-04 — Motifs de sortie dans la fiche salarié

**En cours d'implémentation** - Voir la section ci-dessous pour le détail de la modification en cours.

---

## God Nodes and Graph Analysis (from graphify)

**God Nodes (most connected nodes in the codebase):**
- `unwrap()` - 121 edges (cross-community bridge)
- `fcfa()` - 63 edges
- `monthLabel()` - 50 edges
- `useAuth()` - 47 edges
- `date()` - 45 edges

**Surprising Connections:**
- `ContractEnd()` → `date()` (web/src/pages/EmployeesPage.tsx → web/src/lib/format.ts)
- `renderHeader()` → `date()` (web/src/pages/PayrollBookPrintPage.tsx → web/src/lib/format.ts)
- `MonthlyChart()` → `fcfa()` (web/src/components/AnnualSynthesis.tsx → web/src/lib/format.ts)

**Suggested Questions from graph analysis:**
1. Why does `unwrap()` connect to so many communities? (high betweenness centrality 0.019)
2. Why does `SOMA-RH — Analyse, benchmark et feuille de route` bridge so many communities? (high betweenness centrality 0.007)
3. Why does `dataApi` connect so many components? (high betweenness centrality 0.006)
4. What connects `Pay`, `Slip`, `App` to the rest? (765 weakly-connected nodes)
5. Should `date`, `App.tsx`, or `format.ts` be split into smaller modules? (low cohesion scores)
