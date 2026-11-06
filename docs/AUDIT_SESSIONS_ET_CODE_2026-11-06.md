# Audit sessions et code — 2026-11-06 (premier passage)

Périmètre de ce passage : lecture de l'arborescence, des réglages et des métadonnées de sessions. **Non fait** : lecture du contenu des sessions Claude (le plus lourd fait 32 Mo), exécution des tests, revue ligne à ligne du code TypeScript et PL/pgSQL (`compute_salary_slip`), car la base est arrêtée.

## 1. Sessions

| Source | Constat | Action |
|---|---|---|
| Claude Code (VS Code) | 12 sessions dans `~/.claude/projects/c--IT-Mozaic-SOMA-RH-local` (3 au 6 nov.). Une de 32 Mo (`d61bd51e…`, 4 nov.) et deux de 4-7 Mo : lourdes, sources de compactages. Il existe aussi des dossiers parallèles `c--IT-Mozaic-SOMA-RH` (ancien dépôt, 2 sessions) et `…-docs`. | Une session par lot ; ne plus reprendre la 32 Mo. Archiver l'ancien dossier `SOMA-RH` si abandonné. |
| Copilot Chat | Une seule session (3 nov., mode agent), **0 requête** : vide. Aucun `.github/copilot-instructions.md` : Copilot ne lit pas `CLAUDE.md`. | Créer `.github/copilot-instructions.md` qui renvoie à `CLAUDE.md` (règles migration, PII, FCFA). |
| Hooks Claude | `graphify hook-guard` sur Bash/Grep/Read/Glob (impose `graphify query` avant grep) ; GateGuard exige une déclaration avant la première commande Bash. Fonctionnent, mais ralentissent les sessions longues. | Normal ; à connaître. |
| Environnement | Conteneurs `soma-rh-local-*` **Exited (255) depuis 19 h**. | `docker compose up -d` puis `scripts/local-health.ps1` avant tout lot. |

## 2. Code et dépôt

| # | Constat | Gravité |
|---|---|---|
| 1 | Timestamps de migration en doublon : `20261104150000`, `…160000`, `…180000`, `20261105100000` (**trois** fichiers : `Dev04_IPRES_DGID`, `_backup`, `_fixed`), `20261107120000`. Un runner qui applique tout le dossier exécute `_backup` et `_fixed` en plus de l'original. | Haute |
| 2 | 7 migrations récentes sans retour dans `db/rollback/` : `equipe_soldes`, `Dev03_journal_comptable`, les 3 `Dev04…`, `Dev05_notifications_log`, `Dev09_…`. Viole la règle « une migration, son retour ». | Moyenne |
| 3 | `20261108090000_Dev09_recrutement_formation_évaluation.sql` : accent dans le nom de fichier, risque d'encodage sous Windows/psql/CI. | Moyenne |
| 4 | 31 fichiers non suivis (lot c26, Dev04-09, docs, tests SQL) et 8 modifiés, aucun commit depuis `8f8428ba`. Rien n'est protégé par Git ; avertissements LF→CRLF sans `.gitattributes`. | Haute |
| 5 | CI (`.github/workflows/ci.yml`) : scan PII + lint + build web seulement. Aucun test SQL (`tests/sql/`, 23 fichiers), API ni `verify-payroll`. | Moyenne |
| 6 | Pas de suivi central « migration appliquée sur la base » vérifiable par script avant le lot A. | Moyenne |

## 3. Un « mod » de suivi du développement

Un mod Claude Code est un petit module (3 fichiers) qui ajoute à la session un volet, une ligne d'état ou des garde-fous. Proposition, `soma-suivi`, du plus utile au moins utile :

1. **Garde-fous (hook `tool.call`)** : refuser `verify-payroll.ps1 -Save` sans confirmation ; refuser toute édition d'un fichier de `db/migrations/` déjà appliqué ; refuser un `psql` sur la base sans `ON_ERROR_STOP=1`.
2. **Ligne d'état** : `git: 8 modifiés / 31 non suivis · migrations sans retour : 7 · base : arrêtée`.
3. **Volet latéral** (à côté du chat) : lit `docs/TACHES_ET_RECOMMANDATIONS_RECETTE.md` et affiche les lots A à G avec leur état, plus le dernier résultat de `verify-payroll`.

Je ne l'ai pas créé : l'écrire déclenche une question d'activation à laquelle vous seul répondez. Dites « crée le mod » (version 1 + 2 d'abord, la plus simple).

## 4. Ordre recommandé

1. Démarrer Docker, bloc 0 du prompt (`docs/PROMPT_C26_LOT_A_B.md`).
2. Trancher les doublons `20261105100000` et ajouter les 7 retours manquants (nouvelle migration/rollback, pas d'édition des fichiers appliqués).
3. Commit des fichiers non suivis par lots (après revue du diff).
4. Ajouter `copilot-instructions.md` et les tests SQL à la CI.
5. Lots A puis B.
