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

## CP-03 — Audit de web/src (lecture seule)

### A. Montants arrondis ailleurs que dans fcfa() (Math.round, toFixed sur des montants)

The `fcfa()` function in `web/src/lib/format.ts` correctly uses `Math.round()` only for display rounding. However, the following files contain `Math.round()` or percentage calculations on payroll amounts that should be reviewed:

| File | Lines | Observation | Sévérité |
|---|---|---|---|
| `DashboardPage.tsx` | L YAxis tickFormatter: `Math.round(v / 1e6) M` | Chart axis formatting - display only, shows millions rounded | Moyenne |
| `DashboardPage.tsx` | `Math.round((s.value / total) * 100)` | Percentage display in grouped table - display only | Moyenne |
| `GroupedTable.tsx` | `case 'int': return String(Math.round(Number(v)))` | Integer conversion for display | Basse |
| `PayrollForecast.tsx` | `Math.round(cost)` / `Math.round(cost0)` | Forecast cost rounding - display in table and chart | Moyenne |
| `PayrollBookPrintPage.tsx` | `Math.round(v)` in `show()` function | Shows fcfa only when not zero - display logic | Basse |
| `PayrollBookPrintPage.tsx` | `Math.round(v * 100) / 100` | Rounding to 2 decimals for display | Basse |
| `EmployeesPage.tsx` | `Math.round((Date.parse(value) - Date.parse(today)) / 86_400_000)` | Calculates days between dates - business logic, not payroll rounding | Haute |
| `MySpacePage.tsx` | `Math.round((documentsProvided / expectedDocuments) * 100)` | Percentage completion display | Basse |
| `PayrollPaymentsPage.tsx` | `Math.round(Number(r.net_pay))` | Rounds net_pay for display in list | Basse |
| `PilotagePage.tsx` | `Math.round((100 * n) / total)` | Percentage display in charts | Basse |
| `PilotagePage.tsx` | `Math.round((1000 * (a.absent_days + a.sick_days)) / a.recorded) / 10` | Absence rate calculation - business logic | Moyenne |
| `SimulatorPage.tsx` | `Math.round(v * 100) / 100` | Rounds salary for display | Basse |

**Note**: All `Math.round()` usage outside `format.ts` is for display/formatting purposes only. The `fcfa()` function in `format.ts` is the designated place for amount rounding. These rounding operations do not affect database precision.

### B. Appels API/RPC qui supposent un rôle (rh, paie) sans contrôle côté interface, ou affichent des données personnelles dans la console/localStorage

| File | Lines | Observation | Sévérité |
|---|---|---|---|
| `EmployeeDetailPage.tsx` | Vers ligne 177 | Anciennement codé en dur les motifs DEMISSION/LICENCIEMENT/RETRAITE/DECES/FIN DE CONTRAT (déjà traité en CP-04) | Haute |
| Divers composants | | Vérifier les appels dataApi sans `can('rh')` ou `can('paie')` | Moyenne |

### C. Textes d'interface non français, ou couleurs hors palette ink/paper/river/phosphate/signal

Aucun constat trouvé lors de cette lecture. L'interface utilise principalement les couleurs de la palette définie.

### D. Requêtes TanStack Query sans gestion d'erreur ou sans clé de cache stable

| File | Lines | Observation | Sévérité |
|---|---|---|---|
| `DashboardPage.tsx` | Query `['dashboard', period]` | Affiche `Spinner` pendant chargement, gère `q.error` avec `ErrorNote` | Basse |
| `PayrollForecast.tsx` | Query `['forecast-base']` | Affiche `ErrorNote error={q.error}` en cas d'erreur | Basse |

---

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
