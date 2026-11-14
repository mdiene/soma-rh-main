# Relais soma-tests — ROAD-05 (partie tests SQL) — 2026-11-14

**Branche** : `ci/road05-tests-sql` (worktree `../soma-rh-road05`, issue de `chore/agents-audit`). **Pas de push.**

## Ajouté
- `.github/workflows/ci.yml`, job `rebuild` : rejeu `--keep`, puis `ci-sql-tests.sh rpc_droits` (SEC-06), puis `ci-sql-tests.sh` (tous les tests).
- `scripts/ci-sql-tests.sh` : joue `tests/sql/*.sql` dans `soma-pg-replay` avec `ON_ERROR_STOP=1`, exit 1 au moindre échec.
- `tests/sql/ci-scenario.txt` : liste (vide) des tests à ignorer faute de données de scénario (QA-01).

## SEC-06 : pas de nouveau test
`tests/sql/rpc_droits.sql` vérifie déjà qu'aucune fonction `public` (`prokind` f/p) n'est exécutable par `anon`, et que les privilèges par défaut retirent EXECUTE à PUBLIC. Il est exécuté en étape dédiée. Non couvert : « chaque `security definer` commence par un contrôle de rôle » (heuristique sur `prosrc` fragile ; à décider avec soma-securite).

## Résultats
**Rien n'a été exécuté** : Docker Desktop est arrêté sur ce poste. Seul `bash -n` sur le script est passé. Aucun chiffre de tests.

## Défauts / points ouverts
- Les tests de scénario (QA-01, 14 échecs au 12/11) échoueront probablement sur base neuve : au premier passage, lister les noms dans `ci-scenario.txt` ou faire charger un scénario fictif par `soma-base`.
- Le worktree principal `C:\IT-Mozaic\soma-rh-main` est sur `fix/road06-doublons-migrations` (changé en cours de session, `docs/audit` y est absent) : j'ai donc travaillé dans un worktree séparé.

## Reste à faire
1. Démarrer Docker, lancer `bash scripts/replay-migrations.sh --keep && bash scripts/ci-sql-tests.sh`, classer les échecs.
2. Preuve de CI rouge sur 2 cas volontaires (test cassé, fonction accordée à `anon`).
3. Empreinte de paie : bloquée par DEC-03 ; jeu fictif versionné à préparer par soma-base. Aucun `-Save`.
4. Dépend de ROAD-06 (rejeu vert).
