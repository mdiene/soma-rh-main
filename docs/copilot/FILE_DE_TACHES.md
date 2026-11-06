# File de tâches Copilot

Alimentée par Claude. Statuts : `À FAIRE` → `EN COURS` → `À REVOIR` → `FAIT` (Claude seul) ou `À REPRENDRE`.
Règles : `.github/copilot-instructions.md`. Comptes rendus : `docs/copilot/RETOURS.md`.

## Verrous (fichiers que Claude édite : Copilot n'y touche pas)
`db/migrations/**`, `db/rollback/**`, `web/src/lib/database.types.ts`, `scripts/verify-payroll.ps1`, et les fichiers déjà modifiés dans `git status` (comparatif, qa-reset-scenario.ps1, isolation.test.mjs, api.ts, PayrollBookPrintPage.tsx, PayrollEntryPage.tsx, ReportsPage.tsx, vite.config.ts).

| ID | Tâche | Assignée | Statut | Périmètre autorisé |
|---|---|---|---|---|
| CP-01 | Proposer 5 retours manquants (les `_backup`/`_fixed` de Dev04 sont exclus) | Claude (Copilot a échoué) | À REVOIR | écrire dans `docs/copilot/propositions/` |
| CP-02 | CI : ajouter les tests unitaires JS et un contrôle des migrations | Copilot | FAIT, relu et corrigé par Claude | `.github/workflows/ci.yml`, `.gitattributes`, `scripts/` (nouveaux fichiers) |
| CP-03 | Audit de `web/src` (lecture seule) | Copilot (refait par Claude) | FAIT (A à D traités par Claude ; correctifs à décider) | écrire seulement dans `docs/copilot/RETOURS.md` |
| CP-04 | Interface : motifs de sortie lus dans `exit_reasons` | Claude (repris) | FAIT (lint/build verts) | `web/src/pages/EmployeeDetailPage.tsx` uniquement |

---

## CP-01 — Proposer les retours (rollbacks) manquants
Analyse uniquement, aucun changement dans `db/`.
```
Lis .github/copilot-instructions.md puis docs/copilot/FILE_DE_TACHES.md (tâche CP-01).
Ces migrations n'ont pas de fichier de retour dans db/rollback/ :
 20261104150000_equipe_soldes, 20261105090000_Dev03_journal_comptable, 20261105100000_Dev04_IPRES_DGID,
 20261106100000_Dev05_notifications_log, 20261108090000_Dev09_recrutement_formation_evaluation.
Pour chacune, lis la migration et écris la proposition de retour dans docs/copilot/propositions/<timestamp>_<nom>_down.sql
 (drop dans l'ordre inverse, policies et triggers inclus, "if exists" partout, aucune suppression de données hors objets créés).
Fais comme db/rollback/20261109090000_c26_referentiels_legaux_down.sql pour le style. Ne les ajoute PAS à db/rollback/.
Dans RETOURS.md, par proposition : ce qu'elle supprime, ce qui serait perdu (données), et les objets d'une autre migration qui en dépendent.
```

## CP-02 — Renforcer la CI
```
Lis .github/copilot-instructions.md puis la tâche CP-02 de docs/copilot/FILE_DE_TACHES.md.
1. Dans .github/workflows/ci.yml, ajoute au job web une étape qui lance les tests de tests/unit/*.test.mjs avec "node --test tests/unit".
   Vérifie en local que cette commande passe avant de la committer dans le workflow (ne committe rien : laisse le diff).
2. Ajoute un job "migrations" sans base de données qui échoue si : deux fichiers de db/migrations/ ont le même préfixe de 14 chiffres
   (liste les cas actuels connus en liste d'exceptions dans un fichier scripts/migrations-allowlist.txt), ou si un nom de fichier contient un caractère non ASCII.
   Écris la logique dans un nouveau scripts/check-migrations.sh.
3. Crée .gitattributes pour fixer les fins de ligne (texte LF pour .sql .sh .md .ts .tsx .mjs ; .ps1 CRLF) et dis-moi l'effet sur "git status" avant de l'appliquer.
Compte rendu dans RETOURS.md : commandes lancées, résultat, ce que la CI actuelle ne couvre toujours pas.
```

## CP-03 — Audit de web/src (lecture seule)
```
Lis .github/copilot-instructions.md puis la tâche CP-03 de docs/copilot/FILE_DE_TACHES.md. Ne modifie aucun fichier de web/.
Parcours web/src et rapporte dans RETOURS.md, avec fichier:ligne, sous quatre titres :
 A. Montants arrondis ailleurs que dans fcfa() (Math.round, toFixed sur des montants).
 B. Appels API/RPC qui supposent un rôle (rh, paie) sans contrôle côté interface, ou affichent des données personnelles dans la console/le localStorage.
 C. Textes d'interface non français, ou couleurs hors palette ink/paper/river/phosphate/signal.
 D. Requêtes TanStack Query sans gestion d'erreur ou sans clé de cache stable.
Pour chaque constat : gravité (haute/moyenne/basse) et correctif proposé en une ligne. Ne corrige rien.
```

## CP-04 — Motifs de sortie dans la fiche salarié
```
Lis .github/copilot-instructions.md puis la tâche CP-04 de docs/copilot/FILE_DE_TACHES.md.
Dans web/src/pages/EmployeeDetailPage.tsx (vers la ligne 177), la liste « Motif de sortie » est codée en dur
(DEMISSION, LICENCIEMENT, RETRAITE, DECES, FIN DE CONTRAT). Remplace-la par une requête TanStack Query sur la table
exit_reasons (colonnes code, label, is_legacy, sort_order), triée par sort_order. Masque les motifs is_legacy = true
sauf si le salarié en a déjà un (pour ne pas perdre la valeur existante). Affiche label, enregistre code.
Utilise le client de données existant dans web/src/lib/api.ts SANS le modifier (ce fichier est verrouillé) : fais l'appel depuis la page.
Gère le chargement et l'erreur, en français. Ne modifie pas database.types.ts.
Avant de rendre : dans web/, npm run lint puis npm run build doivent passer.
Compte rendu dans docs/copilot/RETOURS.md.
```
