# SOMA-RH — consignes pour Claude Code

Application RH et paie de la Société Minière Africaine (Sénégal). Interface et données en **français**.

## Structure
- `web/` : React 18 + Vite + TypeScript + Tailwind + TanStack Query/Table. Pages dans `web/src/pages`, composants partagés dans `web/src/components`.
- `db/migrations/` : schéma, RLS, moteur de paie PL/pgSQL, vues d'états. Base PostgreSQL locale (Docker), sans service externe : on reste en local.
- `docs/ANALYSE_EXCEL.md` : règles de paie issues du classeur Excel (référence fonctionnelle).

## Règles
- Le classeur Excel n'est plus la référence de la paie (la base de test évolue en permanence). Le garde-fou est la non-régression interne : après toute modification de `compute_salary_slip`, lancer `scripts/verify-payroll.ps1` (échec = empreinte différente de la référence enregistrée) ; après une évolution voulue, `scripts/verify-payroll.ps1 -Save`. Les anciens chiffres (25 bulletins, brut 4 929 179,09, net 4 662 739,89) et l'écart 26≠25 ne sont plus à prendre en compte.
- Toujours passer par une migration (`db/migrations/AAAAMMJJHHMMSS_nom.sql`) puis l'appliquer sur la base locale (psql dans le conteneur `soma-rh-local-postgres-1`) ; régénérer `web/src/lib/database.types.ts` ensuite.
- Après avoir appliqué une migration qui crée ou modifie une fonction, une vue ou une table sur la base en marche, recharger PostgREST : `docker exec soma-rh-local-postgres-1 psql -U soma -d soma_rh -c "notify pgrst, 'reload schema'"` (sinon l'application affiche « Could not find the function … in the schema cache »).
- Toute nouvelle table : RLS activée + politiques par rôle (`has_role(array['rh'|'paie'])`), index sur les clés étrangères.
- Montants en pleine précision (`numeric`) en base ; arrondi uniquement à l'affichage (`fcfa()` de `web/src/lib/format.ts`).
- Design : palette `ink / paper / river / phosphate / signal` (voir `web/tailwind.config.js`), police Archivo, chiffres tabulaires.
- Données personnelles des salariés : ne jamais les copier dans des fichiers suivis par Git.

## Skills utiles
- `supabase-postgres-best-practices` : schéma, RLS, performances (bonnes pratiques PostgreSQL).
- `frontend-design`, `ui-ux-pro-max`, `ui-styling`, `web-design-guidelines` : interface.
- `vercel-react-best-practices`, `vercel-composition-patterns` : code React.
- `graphify` : carte du code (`/graphify .`, résultat dans `graphify-out/`).
- `xlsx` : lecture des classeurs Excel de paie.

## Contrôles qualité (ECC)

Avant de commiter, selon ce qui a changé (depuis `web/` sauf mention) :

| Quoi | Commande | Agent / skill ECC |
|---|---|---|
| Types + lint | `npm run check` (le build fait `tsc -b`, `tsc -p .` seul ne vérifie rien) | `ecc:build-fix` si échec ; `ecc:react-build-resolver` |
| Build | `npm run build` | |
| Tests unitaires | `node --test ../tests/unit/*.test.mjs` | `ecc:tdd-guide` |
| Tests SQL | `scripts/test-sql.ps1` (tout) ou `scripts/test-sql.ps1 audit_*` | `ecc:database-reviewer` avant de commiter une migration |
| Non-régression paie | `scripts/verify-payroll.ps1` | |
| Interface (menu par rôle, pages sans plantage) | `npm run e2e` ou `npx playwright test e2e/menu.spec.ts` | `ecc:e2e-runner` |
| Accessibilité (WCAG A/AA) | `npx playwright test e2e/a11y.spec.ts` | `ecc:a11y-architect`, `ecc:accessibility` |
| Revue du diff | `/ecc:code-review` | `ecc:react-reviewer`, `ecc:typescript-reviewer`, `ecc:security-reviewer` (API, auth), `ecc:silent-failure-hunter` |
| Planifier une évolution | `/ecc:plan` | `ecc:architect`, `ecc:code-explorer` |

Les tests e2e (`web/e2e`) :
- demandent l'application lancée sur `http://localhost:5173` et les comptes de `tests/.env.qa` (hors Git) ; ils ne modifient aucune donnée ;
- se connectent **une fois par rôle** (`auth.setup.ts`, session réutilisée) : l'API limite `POST /auth/v1/token` à 30 par 15 minutes et par IP, ne pas contourner cette limite ;
- s'ouvrent en deux lots si la mémoire manque (Chromium + Docker) : un fichier à la fois.

Toute modification du menu (`web/src/lib/nav.ts`, `Layout.tsx`) ou d'une page doit garder `menu.spec.ts` et `a11y.spec.ts` au vert.

## graphify

This project has a knowledge graph at graphify-out/ with god nodes, community structure, and cross-file relationships.

Rules:
- For codebase questions, first run `graphify query "<question>"` when graphify-out/graph.json exists. Use `graphify path "<A>" "<B>"` for relationships and `graphify explain "<concept>"` for focused concepts. These return a scoped subgraph, usually much smaller than GRAPH_REPORT.md or raw grep output.
- If graphify-out/wiki/index.md exists, use it for broad navigation instead of raw source browsing.
- Read graphify-out/GRAPH_REPORT.md only for broad architecture review or when query/path/explain do not surface enough context.
- After modifying code, run `graphify update .` to keep the graph current (AST-only, no API cost).
