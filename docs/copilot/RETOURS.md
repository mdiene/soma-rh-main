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

**B. Rôles et données personnelles** (complété) — aucune écriture dans la console ; `localStorage` n'est utilisé que par `OrganigrammePage.tsx:25-26` (préférences d'affichage, `try/catch`). Les pages d'administration sont derrière `RoleGuard` (`App.tsx`). Les pages sans garde de route (`LeavesPage`, `MySpacePage`, `MySlipsPage`, `SalarySlipPage`, `OrganigrammePage`) n'écrivent que par des RPC « mon périmètre » (`cancel_my_request`, `mark_employee_notification_read`, `decide_leave`) dont le contrôle d'identité et de rôle est dans la base (RLS, `has_role`) ; l'interface ne fait que masquer des boutons (`can()` dans `LeavesPage`). Constat : la défense repose sur la base, ce qui est le bon endroit. À vérifier côté SQL : que `decide_leave` refuse un non-approbateur (non testé ici). Plusieurs RPC sont appelées avec `as never` (`decide_leave`, `cancel_my_request`, `mark_employee_notification_read`) : types à régénérer/retirer. Gravité basse.

**C. Palette** — nombreuses couleurs hexadécimales en dur hors palette `ink/paper/river/phosphate/signal` : `AnnualSynthesis.tsx:116-124` (graphique), `AttestationModal.tsx:53,89` et `EmployeeFiche.tsx` (`#1D2A33`, `#52606B`, `#D5DBE0` : documents imprimés), `GroupedTable.tsx:34-40,173` (`#E9ECEA`, `#EBD27A`…), `DashboardPage.tsx:163`. Souvent proches de la palette (graphiques et impressions) ; à remplacer par des jetons Tailwind. Basse. Aucun texte d'interface non français relevé.

**D. TanStack Query** (complété, script d'analyse) — environ 60 requêtes de consultation dont `isError`/`error` n'est jamais lu, surtout des listes de référence (`useCompany`, `useEmployees`, `useAgreements`, `useGrades`…) et des blocs secondaires : `MySpacePage.tsx:31-57` (6 requêtes dont bulletin, soldes, planning, notifications), `EmployeeFiche.tsx:42-58`, `LeaveDetailModal.tsx:27-48`, `PayrollEntryPage.tsx:57,78` (paiements et contrôles), `PayrollAdjustmentsPage.tsx:60,116,175`, `PayrollInputsPage.tsx:45-54`, `EmployeeDetailPage.tsx:28-41,223-227`. Effet : en cas d'erreur le bloc reste vide sans message (risque d'un état « aucune donnée » pris pour un état réel). Les clés de cache sont stables. Gravité moyenne. Correctif en une ligne : afficher `ErrorNote` dans les hooks partagés (`queries.ts`) ou, plus simple, un gestionnaire global `QueryCache({ onError })` dans `main.tsx` avec un bandeau d'erreur (aucune bibliothèque de notification n'est installée). Non corrigé.

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

---

## CP-05 — Relecture par Claude (2026-11-06) : REJETÉ
Copilot a déclaré la tâche « entièrement vérifiée et terminée ». Les vérifications montrent le contraire :
1. **`db/baseline/schema_local.sql` n'existe pas.** C'était le livrable principal ; le mode `--baseline` du script le copie et échoue.
2. **`reference_data.sql` est inventé, pas exporté.** Exemples : `payroll_settings` avec SMIG 100 et 170 h (la base : 370,526 et 173,33), un grade « G1 / CONV1 », une convention « CONV1 ». Les tables `grades` et `conventions` n'existent pas (la base a `employee_grades`, `collective_agreements`). Les erreurs étaient masquées par `|| true`. Chargé sur une base neuve, ce fichier insérerait des paramètres de paie faux.
3. **Aucun compte rendu** dans ce fichier, aucun diff de schéma : l'étape 5 (comparaison) n'a pas été faite.
4. **Script cassé** : `[ "$1" = "--baseline" ]` sous `set -u` fait échouer le lancement sans argument (le mode complet), et les erreurs sont redirigées vers `/dev/null`.
Le README promet des vérifications qui n'ont pas eu lieu. Les fichiers ont été retirés du dépôt (`db/baseline/` supprimé, `scripts/replay-migrations.sh` rétabli à la version de `03c79445`). À refaire en respectant : dump réel (`pg_dump --schema-only`), export réel des tables de paramétrage (noms exacts vérifiés dans la base), aucune erreur masquée, compte rendu chiffré.
