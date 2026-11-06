# Prompt — Conformité Code du Travail 2026, lots A et B

Mode d'emploi : coller **un bloc à la fois**, dans une seule session Claude Code, dans l'ordre. Ne coller le bloc suivant qu'après lecture du compte rendu du précédent.

| Bloc | Contenu | Écrit en base ? |
|---|---|---|
| 0 | Pré-vol (lecture seule) | non |
| 1 | Lot A : sauvegarde, 3 migrations, vérifications | oui |
| 2 | Lot B : sorties et indemnités | oui |

---

## Bloc 0 — Pré-vol (lecture seule)

```
Rôle : développeur SOMA-RH. Lis CLAUDE.md, puis docs/CADRAGE_CODAGE_CONFORMITE_CODE_TRAVAIL_2026.md en entier.
Références : docs/CODE_TRAVAIL_2026_SPECIFICATION_SOMA_RH.md et docs/sources-legales/.

Interdits : n'invente aucune valeur légale (ce qui manque reste « à fournir ») ; ne touche pas aux fichiers
déjà modifiés dans git status (docs/comparatif, scripts/qa-reset-scenario.ps1, tests/api/isolation.test.mjs,
web/src/lib/api.ts, PayrollBookPrintPage.tsx, PayrollEntryPage.tsx, ReportsPage.tsx, web/vite.config.ts).

Ne modifie rien. Vérifie et rapporte sous forme de tableau OK / KO :
1. Les conteneurs soma-rh-local-postgres-1, -postgrest-1, -api-1 tournent (sinon : docker compose up -d, puis scripts/local-health.ps1).
2. Quelles migrations de db/migrations/ sont déjà appliquées sur la base (table de suivi, sinon comparaison de l'état du schéma).
   Les 3 migrations c26 (20261109090000, 20261109100000, 20261109110000) sont-elles déjà appliquées ? Si oui, STOP.
3. Doublons de timestamp dans db/migrations/ (notamment 20261105100000 : _IPRES_DGID, _backup, _fixed) :
   lesquels seraient exécutés par un « psql sur tous les fichiers » ? Propose, sans l'appliquer, comment les départager.
4. Chaque migration c26 a son fichier db/rollback/..._down.sql.
5. Résultat de scripts/verify-payroll.ps1 (référence avant changement). Note l'empreinte.
Termine par : « Prêt pour le lot A : oui / non, parce que… ».
```

---

## Bloc 1 — Lot A (seulement si le bloc 0 dit « oui »)

```
Applique le lot A. Contraintes : psql -v ON_ERROR_STOP=1 ; ne jamais modifier une migration déjà appliquée
(corriger par une nouvelle migration) ; jamais de -Save sur verify-payroll.ps1.

1. Sauvegarde : pg_dump dans soma-rh-local-postgres-1 (user soma, base soma_rh) vers un fichier HORS dépôt
   (dossier backups/ est ignoré par Git). Vérifie que le fichier n'est pas vide.
2. Applique dans l'ordre les 3 migrations c26. Erreur => arrête-toi, applique le retour correspondant,
   explique la cause, ne continue pas.
3. notify pgrst, 'reload schema'.
4. Vérifie (affiche chaque résultat attendu / obtenu) :
   quotite_cessible(50000)=10000 ; (150000)=45000 ; (300000)=165000
   plafond_retenues(150000)=100000
   leave_types MATERNITE = 126 jours, extension 21
   exit_reasons = 18 lignes ; tous les salariés existants ont un exit_reason valide
   majoration_retard_cotisations(1000000,'2026-11-15','2027-07-20')=500000
5. Relance verify-payroll.ps1 : empreinte identique au bloc 0, sinon STOP et explique l'écart.
6. Régénère web/src/lib/database.types.ts ; dans web/ lance npm run build (et npm run lint, comme la CI) ; puis graphify update .
7. Lance les tests tests/sql/ liés (sortie_salarie.sql, rpc_droits.sql, settings_dated.sql) et note les échecs.

Compte rendu court en français : fait / échoué / reste. Ne commit pas ; montre git status et git diff --stat.
```

---

## Bloc 2 — Lot B (seulement si le lot A est entièrement vert)

```
Lot B : sortie_salarie et le solde de tout compte lisent la table exit_reasons.

- Une migration (timestamp > 20261109110000) + son retour dans db/rollback/.
- sortie_salarie accepte les 16 motifs de exit_reasons + les 2 anciens codes (plus de liste fixe).
- Indemnité spéciale d'un mois (special_indemnity_months) : LICENCIEMENT_ECONOMIQUE, CESSATION_ACTIVITE, PLAN_SOCIAL.
- Indemnité de licenciement seulement si severance_eligible ET ancienneté >= payroll_settings.severance_min_months (12).
- Décès : indemnité assimilée au licenciement + au moins un mois d'obsèques (CCNI art. 83), marqué « à confirmer ».
- Toute nouvelle table : RLS, politiques has_role(array['rh'|'paie']), index sur les clés étrangères ; montants en numeric.
- Compare avant/après sur des salariés de test, SANS copier de données personnelles dans un fichier suivi par Git.
- Lance verify-payroll.ps1 : liste chaque écart et explique-le. Ne lance PAS -Save : attends mon accord après la liste.
- Ajoute les tâches restantes (lots C à G) dans docs/TACHES_ET_RECOMMANDATIONS_RECETTE.md uniquement.
- Ne commit pas sans m'avoir montré le diff.

Compte rendu court en français : fait / échoué / reste.
```

---

## Pourquoi cette structure

- Le prompt d'origine mélangeait contexte, interdits, deux lots et règles : un échec au milieu laissait la session dans un état flou. Le bloc 0 ne coûte rien et évite d'appliquer à l'aveugle.
- Les conteneurs Docker de SOMA-RH étaient arrêtés (Exited 255) lors de l'audit : sans le point 1 du bloc 0, `verify-payroll` aurait échoué dès l'étape 1.
- Les points de décision (« prêt oui/non », accord avant `-Save`, diff avant commit) sont des arrêts explicites, pas des phrases noyées dans les règles.
