# Programme de travail — Modules métiers (M0 à M7)

Version 1 — 6 novembre 2026. Découle de `PROJET_MODULES_METIERS_MISE_EN_PLACE.md` §8. Règle de rythme : **un lot par demande, arrêt et validation à la fin de chaque lot**.

## Principes communs à tous les lots
- Ouverture de lot : `scripts/verify-payroll.ps1` → noter l'empreinte « avant ». Clôture : même commande, modules éteints → empreinte identique.
- Une migration (horodatage > `20261117090000`), son retour dans `db/rollback/`, application dans `soma-rh-local-postgres-1`, `notify pgrst, 'reload schema'`, régénération de `web/src/lib/database.types.ts`.
- Tests écrits avant le code. Clôture : `npm run build` + lint dans `web/`, tests SQL, `graphify update .`, rapport court.
- Aucune valeur légale ✖ pré-remplie : alerte « paramètre manquant » dans `compliance_findings`.
- Qui fait quoi : Claude = migrations, fonctions SQL, `compute_salary_slip`, types, intégration, relecture. Copilot = documents, schémas, gabarits de tests, maquettes, comparatifs (voir `docs/copilot/FILE_DE_TACHES.md`, CP-06 et suivantes). Tout livrable Copilot est relu par Claude avant usage.

## Phases

| Phase | Lots | Objet | Condition de sortie (porte) |
|---|---|---|---|
| 0. Socle | M0 | Tables, RLS, chargeur de manifestes, audit | Empreinte inchangée ; tests RLS verts |
| 1. Cadre d'usage | M1, M2 | Page Métiers, formulaires générés, fiche salarié | Un module de test s'active/désactive sans effet sur la paie ; fiche avec champs sectoriels |
| 2. Moteur | M3 | Éléments de paie, règles, branchement dans `compute_salary_slip` | Cas dorés intérim ; `-Save` après revue et accord explicite |
| 3. Modules | M4, M5, M7 | Intérim, Gardiennage, Industrie/mines, puis Transport, Nettoyage/BTP, HORECA | Un cas doré signé par module |
| 4. Terrain | M6 | Planning, grille de saisie, conformité, mobile | Parcours de bout en bout sur la base de test |

Ordre recommandé : M0 → M1 → M2 → M3 → M4 → M5 → M6 → M7. M6 peut chevaucher M5 si le planning existant le permet (à vérifier).

## Détail par lot

### M0 — Socle (Claude, un lot)
1. Vérifier `btree_gist` disponible (contrainte d'exclusion de `module_parameter_value`) ; sinon trancher avec l'utilisateur.
2. Tests d'abord : `tests/sql/m0_module_rls.sql` (rh écrit, paie lit, salarié ne voit rien d'un autre, anon rien).
3. Migration : `module_manifest`, `module_activation`, `module_parameter_value`, `employee_module_data` + RLS + index sur FK + journal d'audit (trigger sur activation/paramètres, vers la table d'audit existante si elle existe : à chercher avec `graphify query`).
4. Chargeur : lit `docs/modules/manifests/*.json`, valide contre un schéma, calcule le hash, insère en `draft`. Données seulement locales.
5. Retour arrière, types, `reload schema`, `verify-payroll`, build, lint, `graphify update .`.

Points à trancher en cours de lot : où vit le chargeur (script Node dans `scripts/` ou fonction SQL) ; sort des manifestes `draft` (v0.x) à l'activation.

### M1 — Page Métiers
Onglet `parametres/metiers` dans `SettingsPage` ; catalogue (cartes, badge, jauge ✔ ◐ ✖) ; assistant 4 étapes en volet latéral ; saisie tracée des paramètres ; simulation à blanc (`simulate_module_impact` en version vide tant que M3 n'existe pas : zéro écart). Dépend de M0. Maquette et libellés préparés par Copilot (CP-10).

### M2 — Formulaires génériques
`ModuleForm` lisant `custom_fields` ; onglet « Métier » de `EmployeeFiche` visible seulement si un module actif concerne le salarié ; validation par schéma du manifeste ; historique des valeurs. Dépend de M0, M1.

### M3 — Moteur de paie
Décision préalable : langage des formules (spike CP-11, à valider par l'utilisateur). Puis `module_payroll_input`, `module_payroll_line`, `module_active_for`, `module_payroll_adjustments`, branchement minimal dans `compute_salary_slip` (seul lot autorisé à y toucher), section « Éléments métier » du bulletin et `SlipExplain`. Garde-fou : empreinte identique modules éteints, puis `-Save` seulement après revue et accord. Dépend de M0 à M2.

### M4 — Services / Intérim (livré 09/11/2026 : agrément, IFC 7 %, durée 2 ans, cumul, motif art. 293 ; INT-T02 sans objet tant que la facturation n'existe pas)
Contrôles art. 291 à 294, agrément (J-30), durée maximale 2 ans (◐), indemnité de fin de mission 7 % (✖ provisoire, saisie obligatoire). Tests INT-T01, INT-T02 et nouveaux. Dépend de M3 et de la décision utilisateur sur l'IFC.

### M5 — Gardiennage puis Industrie et mines
Gardiennage : seuils d'équivalence saisis par le client (✖), nuit 22 h–5 h (✔ art. 245), majorations 15/40/60/100 (◐). Industrie et mines : module absent de la spécification v2 ; manifeste à rédiger et à confirmer (prérequis §10-1) ; primes par convention ou accord, à saisir. Cas dorés signés par le comptable.

### M6 — Terrain
Modèles de postes dans le planning, grille rapide de saisie (collage Excel), widgets de conformité par module, vue mobile une colonne. Dépend de M3 au minimum.

### M7 — Autres métiers
Transport (CCNI art. 61), Nettoyage/BTP, HORECA (logement ◐ 33 500 / 20 000 / 13 500, nourriture ✖). Un cas doré chacun ; conventions de branche à fournir (✖).

## Prérequis humains
| Décision / pièce | Bloque |
|---|---|
| Confirmer Industrie et mines en priorité 1 | manifeste (CP-12), M5 |
| Valider le langage de formules (CEL ou JSONLogic) | M3 |
| IFC intérim définitif, plafond AT de la CSS | M4 |
| JO n° 4091 (décrets 70-182/183/184) | M5 (sinon seuils saisis par le client) |
| Conventions de branche | M5, M7 |

## Risques
- `compute_salary_slip` est le point sensible : toute modification hors M3 est interdite.
- Les manifestes sont en brouillon (v0.x) : le schéma doit tolérer `null` / `to_provide`.
- Migrations antérieures à régler avant M0 pour partir d'une base propre (Dev04 en trois fichiers, Dev09) : vérifier si c'est déjà fait.
