# SOMA-RH — instructions pour GitHub Copilot

Équivalent de `CLAUDE.md` pour Copilot. Lis aussi `CLAUDE.md` à la racine : ses règles s'appliquent à toi.
Application RH et paie de la Société Minière Africaine (Sénégal). Interface, données, commentaires et commits en **français**.

## Comment tu reçois du travail
1. Ouvre `docs/copilot/FILE_DE_TACHES.md`. Prends **uniquement** les tâches au statut `À FAIRE` qui te sont assignées (« Copilot »).
2. Passe la tâche à `EN COURS`, travaille dans le périmètre indiqué, puis passe à `À REVOIR`.
3. Écris ton compte rendu dans `docs/copilot/RETOURS.md` (une section par tâche : fait / pas fait / questions). Ne touche à aucun autre fichier de suivi.
4. Claude (autre session) relit, puis passe la tâche à `FAIT` ou `À REPRENDRE`. Tu ne passes jamais une tâche à `FAIT`.

## Interdits (sans exception)
- Pas de `psql`, `docker exec` sur la base, ni aucune écriture en base. Les migrations sont appliquées par Claude seulement. Tu peux **proposer** du SQL dans `docs/copilot/propositions/` ; tu ne l'ajoutes pas à `db/migrations/`.
- Ne modifie pas `compute_salary_slip`, `sortie_salarie` ni aucun fichier de `db/migrations/` existant.
- Ne touche pas aux fichiers que Claude édite : voir la colonne « Verrou » de `FILE_DE_TACHES.md`. Si un fichier y figure, laisse-le.
- Aucun commit, aucun push. Laisse les changements dans l'arbre de travail.
- Aucune donnée personnelle de salarié dans un fichier suivi par Git ; n'invente aucune valeur légale (ce qui manque reste « à fournir »).

## Conventions du projet
- `web/` : React 18 + Vite + TypeScript + Tailwind + TanStack Query/Table. Pages dans `web/src/pages`, composants dans `web/src/components`.
- Montants : `numeric` en base, arrondi à l'affichage seulement, avec `fcfa()` de `web/src/lib/format.ts`.
- Design : palette `ink / paper / river / phosphate / signal` (`web/tailwind.config.js`), police Archivo, chiffres tabulaires.
- `web/src/lib/database.types.ts` est généré : ne l'édite pas à la main.
- Vérifier avant de rendre : dans `web/`, `npm run lint` puis `npm run build` doivent passer (c'est la CI).
- Nouvelle table (en proposition) : RLS activée, politiques `has_role(array['rh'|'paie'])`, index sur les clés étrangères.
