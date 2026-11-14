# Agents nommés de SOMA-RH

Huit agents Claude Code, chacun avec un rôle, un périmètre, ses skills et sa mémoire. Chaque session porte un **nom** (`soma-<agent>-<lot>`) pour être reprise facilement. Définitions (source, suivies par Git) : `docs/agents/definitions/soma-*.md`, copiées dans `.claude/agents/` par `.\scripts\agents.ps1 installer` (à relancer après toute modification d'une définition). Lanceur : `scripts/agents.ps1`.

| Agent | Rôle | Écrit dans | Skills préchargées |
|---|---|---|---|
| `soma-controle` | Chef de chantier : découpe en lots, fiches d'ordre, vérification, avis GO / NO-GO | `docs/agents/` | graphify |
| `soma-codage` | Interface React et passerelle API | `web/src`, `api/`, `tests/unit` | graphify, vercel-react-best-practices, vercel-composition-patterns |
| `soma-base` | Migrations, RLS, moteur de paie ; **seul à appliquer des migrations** | `db/`, `tests/sql` | supabase-postgres-best-practices, graphify |
| `soma-tests` | Tests unitaires, SQL, e2e, accessibilité, non-régression ; relève les défauts | `tests/`, `web/e2e`, `docs/qa`, `docs/recette` | webapp-testing, graphify |
| `soma-design` | Écrans, parcours, composants, accessibilité | `web/src/pages`, `web/src/components`, captures | frontend-design, ui-ux-pro-max, ui-styling, web-design-guidelines, design-system |
| `soma-securite` | Audit sécurité, étanchéité, sauvegardes ; prescrit sans corriger | `docs/agents/relais` | supabase-postgres-best-practices, supabase, graphify |
| `soma-doc` | Guide utilisateur, passations, registre, feuille de route | `docs/` | graphify |
| `soma-recherche` | Benchmark, juridique, carnet « logiciel HR » | `docs/audit`, `docs/comparatif` | graphify |

Les agents ECC (`ecc:code-reviewer`, `ecc:database-reviewer`, `ecc:security-reviewer`, `ecc:e2e-runner`, `ecc:tdd-guide`, `ecc:a11y-architect`…) restent disponibles dans chaque session pour les revues.

## Lancer, reprendre, lister (PowerShell, à la racine du dépôt)

```powershell
.\scripts\agents.ps1 installer                               # une fois, puis après chaque modification des définitions
.\scripts\agents.ps1 liste                                   # agents + sessions enregistrées
.\scripts\agents.ps1 lancer controle phase1 -Consigne "Lis docs/audit/DOCUMENT_MAITRE_SOMA_RH_2026-11-14.md §6 et ouvre les fiches d'ordre de ROAD-01 à ROAD-08"
.\scripts\agents.ps1 lancer securite road01 -Fenetre          # nouvelle fenêtre, en parallèle
.\scripts\agents.ps1 reprendre securite road01                # reprend la session « soma-securite-road01 »
.\scripts\agents.ps1 bifurquer codage road02                  # nouvelle branche de conversation, l'originale reste intacte
.\scripts\agents.ps1 tableau                                  # vue « claude agents » des sessions en cours
```

Équivalent sans le script : `claude --agent soma-codage --name soma-codage-road02`, puis `claude --resume soma-codage-road02`. Dans une session déjà ouverte : `/rename soma-codage-road02`. Si votre version de Claude Code n'a pas `--name`, le script vous le dit et vous demande de taper `/rename`.

Règle de nommage du lot : minuscules, chiffres et tirets (`road02`, `rpr11`, `audit-1114`). Le registre `docs/agents/sessions.csv` garde date, session, agent, lot et branche.

## Circuit de travail

1. `soma-controle` écrit une **fiche d'ordre** `docs/agents/relais/AAAA-MM-JJ_<lot>_ordre.md` (objectif, branche, fichiers, critères d'acceptation, contrôles, agent, nom de session).
2. L'agent désigné est lancé avec ce nom de session ; il commence par lire sa fiche d'ordre.
3. En fin de session, il écrit sa **fiche de relais** `docs/agents/relais/AAAA-MM-JJ_<agent>_<lot>.md`.
4. `soma-controle` vérifie (diff, contrôles) et rend son avis dans `docs/agents/TABLEAU_DE_BORD.md`.
5. Fusion, `git push` et déploiement : **uniquement sur votre accord**.

## Parallélisme : ce qui est sûr

- En parallèle sans risque : `soma-recherche`, `soma-securite` (lecture), `soma-doc`, `soma-design` sur des écrans différents.
- **Jamais deux agents qui appliquent des migrations** : seul `soma-base` le fait, un lot à la fois (une seule base locale).
- Tests e2e : une seule session Playwright à la fois (limite de connexions de l'API, mémoire).
- Une branche par lot ; si deux agents travaillent en même temps sur du code, utiliser des copies de travail séparées (`git worktree add ../soma-rh-<lot> <branche>`).

## Mémoire des agents

`memory: project` : chaque agent garde ses notes dans `.claude/agent-memory/<agent>/` (suivi par Git). **Aucune donnée personnelle, aucun secret** : le scan PII de la CI s'applique.
