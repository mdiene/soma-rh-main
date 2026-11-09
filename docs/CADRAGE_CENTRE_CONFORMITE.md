# Cadrage — Centre de contrôle de conformité, dérogations et constantes légales

Page d'administration : `/centre-conformite` (rôle `admin`, lecture `rh`/`paie` sur l'onglet A).
Statut : cadrage, aucun code écrit. Date : 2026-11-09.

## 1. Objectif

1. **Scan** : un bouton lance tous les contrôles de cohérence et rend un état global 🟢 / 🟠 / 🔴, repris en pastille sur le tableau de bord.
2. **Décision** : pour chaque écart, l'admin déroge (motif écrit, durée, trace) ou corrige le salarié / la constante.
3. **Constantes** : toutes les constantes légales sont éditables, avec valeur active, texte de loi, article, et réinitialisation à la valeur d'origine. Une modification ne touche que les paies **non calculées**.

## 2. Écarts entre le prompt initial et le projet (à ne pas suivre à la lettre)

| Prompt initial | Réalité SOMA-RH | Décision |
|---|---|---|
| Next.js, Server Actions | React 18 + Vite, PostgREST (`dataApi.rpc`) | Fonctions RPC PL/pgSQL + TanStack Query |
| Service TypeScript `ComplianceCheckerService` | Les contrôles vivent en SQL (`detecter_conformite`, vues `v_conformite_*`) ; le front n'a pas toutes les données | **Moteur de scan en SQL**, étendu. Pas de service TS |
| `legal_constants_versioned` (nouvelle table) | `payroll_settings` est **déjà versionnée** (1 ligne par `effective_from`) ; `app_parameters` (plafond prêt) ; barèmes `overtime_rates`, `notice_scales`, `garnishment_scale`, `severance_scales`, `tax_slab*` ; `legal_sources` porte déjà source/article/statut | Pas de table de valeurs en double : **un catalogue de métadonnées** au-dessus de l'existant (§4.1) |
| `payroll_compliance_scans` + `tenant_id` | Mono-société (`company_id`), pas de `tenant_id` | Table `compliance_scans` sans tenant |
| `compliance_exceptions` | `compliance_findings.waived_by/waiver_reason` + `deroger_constat` (réservé `rh`) existent | Registre `compliance_waivers` **durable** (survit à la résolution/réouverture d'un constat), dérogation ouverte à `admin` |
| Rôle ADMIN seul | Policies actuelles `has_role(array['rh','paie'])` ; `admin` passe via `can()` côté UI | Vérifier que `has_role` laisse bien passer `admin` en base avant de s'y fier |

Briques à réutiliser telles quelles : [CompliancePage.tsx](../web/src/pages/CompliancePage.tsx) (devient l'onglet A), [SettingsPage.tsx](../web/src/pages/SettingsPage.tsx) (`settingsSaveMode`, champs `SETTING_FIELDS`), trigger `business_audit()`, `audit_events`, composants `ui.tsx` (`Modal`, `Section`, `Button`, `TextField`, `ErrorNote`).

## 3. Structure de la page (3 onglets)

**A. Cohérence** — pastille globale + compteurs (bloquants / alertes / salariés impactés), bouton « Lancer le scan », tableau des écarts filtrable par sévérité et par domaine. Actions par ligne : `Déroger` (modale : motif obligatoire, date d'expiration, pièce/référence), `Corriger` (lien vers fiche salarié ou vers la constante en cause), `Voir la règle`.

**B. Constantes légales** — tableau groupé par domaine (Cotisations sociales, Impôt, Temps de travail, Intérim, Gardiennage, Prêts…). Colonnes : libellé, valeur active, valeur d'origine, en vigueur depuis, statut de la source (`confirmé` / `à confirmer`). Dépliant : texte de loi, article, décret. Actions : `Modifier` (nouvelle valeur + date d'effet), `Réinitialiser` (remet la valeur d'origine). Bandeau permanent : « Les modifications s'appliquent uniquement aux paies non encore calculées. »

**C. Registre des dérogations** — salarié, règle, motif, auteur, date, expiration, statut (`active`/`expirée`/`révoquée`), bouton `Révoquer`. Lecture seule sinon.

**Tableau de bord** — widget « Conformité » (pastille + date du dernier scan + lien), visible `admin`/`rh`/`paie`.

## 4. Base de données (une migration par lot, voir §7)

### 4.1 Catalogue des constantes — `parameter_catalog`
Ne stocke **pas** la valeur : il décrit où elle vit et ce qu'elle signifie.

| Colonne | Rôle |
|---|---|
| `code` pk | ex. `css_ceiling`, `precarity_rate`, `loan_max_rate` |
| `domain`, `label`, `unit` (`FCFA`,`%`,`h`,`nb`), `sort` | affichage |
| `store` | `payroll_settings` \| `app_parameters` \| `module_parameter_value` |
| `column_name` | colonne ou code dans le store |
| `default_value numeric` | valeur d'origine, figée à l'amorçage depuis les valeurs actuelles |
| `min_value`, `max_value` | bornes de saisie (validées côté base) |
| `source_code` → `legal_sources(code)` | réutilise article/document/statut existants |
| `legal_text` | explication courte de ce que la loi prévoit |

Barèmes multi-lignes : éditables aussi (décision 3, §8).

### 4.2 Modification versionnée et verrou
- `set_parameter(code, value, effective_from)` : insère une **nouvelle ligne** `payroll_settings` (copie de la courante + valeur changée), jamais d'`update` en place. Pour `app_parameters`, l'historique passe par `audit_log` (déjà branché) ; ajouter `effective_from` si la valeur influence le calcul.
- `reset_parameter(code)` : même mécanique avec `default_value`.
- **Date d'effet minimale** = premier jour de la première période dont le statut est `Brouillon`/`Annulée` (jamais ≥ `Calculée`). Refus sinon.
- Trigger de garde sur `payroll_settings` : `update`/`delete` interdits si une période `Calculée`+ s'appuie sur cette ligne. Cela corrige le mode « correction » actuel de `SettingsPage`, qui modifie la ligne en place.
- Vérification d'impact : lancer `scripts/verify-payroll.ps1` avant/après ; la modification de constantes ne doit pas changer l'empreinte des bulletins existants.

### 4.3 Scan et dérogations
- `compliance_scans(id, scanned_at, scanned_by, status 'vert'|'orange'|'rouge', nb_bloquants, nb_alertes, nb_salaries, summary jsonb)`.
- `compliance_findings` : ajouter `scan_id`, `domain`, `suggested_action` (texte), `employee_id` (aujourd'hui seulement `entity/entity_id`).
- `compliance_waivers(id, rule_id, entity, entity_id, employee_id, reason not null, parameter_code, parameter_value, status, granted_by, granted_at, ended_at, ended_by)`, index sur chaque FK, unique partiel `(rule_id, entity_id) where status='active'`. Pas d'expiration (§8-2) : une dérogation active masque l'écart jusqu'à remplacement, levée ou révocation ; le scan la prend en compte même après résolution/réouverture du constat.
- `run_compliance_scan()` : appelle `detecter_conformite()` étendu, écrit la ligne de scan, renvoie le statut. Règle d'état : 🔴 si un bloquant non dérogé ; 🟠 si une alerte non dérogée ; sinon 🟢.
- `grant_waiver`, `revoke_waiver` (rôle `admin`, motif obligatoire), tous deux écrits dans `audit_events`.
- RLS : lecture `admin`/`rh`/`paie` ; écriture uniquement par RPC `security definer` ; `revoke` sur `anon`.

### 4.4 Règles de scan (état cible)

| Règle demandée | Source existante probable | Action |
|---|---|---|
| Salaire < plancher légal (SMIG/JO 4091) ou barème conventionnel | `20261119090000_c26_jo4091_plancher_legal` | Brancher la vue/fonction existante |
| Retenues > quotité cessible / plafond 2/3 | `RET-04`, `RET-PLAFOND` | Déjà en place |
| Déclaration d'embauche / affiliation | `EMB-DECL`, `EMB-AFFIL` | Déjà en place |
| Attestations de régularité sociale, agrément ETT | `societe_numeros_alertes_legales`, `societe_ett_agrement_taux_at` | Brancher alertes existantes |
| CDD / intérim : durée max, renouvellements, motif | `interim_duree_max_mission`, `interim_motif_cumul` | Brancher |
| Heures sup. : contingent | `lotg_hs_preavis`, `m5_equivalence_heures_sup` | Brancher |
| Équivalence gardiennage 56 h / 48 h | `m5_equivalence_heures_sup`, `gardiennage_alertes` | Brancher |
| Habilitations / transport / nettoyage | `industrie_mines_habilitations`, `m7_alertes_*` | Brancher |
| Cohérence des constantes (hors bornes, date d'effet manquante, valeur ≠ défaut non confirmée) | nouveau | À écrire |

« Probable » = repéré par nom de migration, non relu en détail : chaque ligne est à confirmer en début de lot 2 (lire la vue, vérifier qu'elle renvoie des lignes par salarié).

## 5. Points juridiques à ne pas inventer
Le prompt cite « Décret 2019-106 / Art. L.195 » et « Art. 292 » : **non vérifiés**. Le texte de loi et l'article de chaque constante se saisissent dans `legal_sources` avec statut `a_confirmer` jusqu'à revue du juriste (convention déjà en vigueur dans le projet). Le lot 1 amorce uniquement ce que `legal_sources` et les en-têtes de migrations documentent déjà ; le reste est marqué « à fournir ».

## 6. Frontend
- Route `/centre-conformite` dans `App.tsx` ; entrée de menu dans `nav.ts` (groupe administration, `roles: ['admin']`). Garder `menu.spec.ts` et `a11y.spec.ts` au vert.
- Fichiers : `pages/ComplianceCenterPage.tsx` (onglets), `components/compliance/{Scorecard,FindingsTable,WaiverModal,ConstantsTable,ConstantEditor,WaiversRegister}.tsx`, `lib/compliance.ts` (types, libellés de sévérité, règle d'état). `CompliancePage.tsx` est absorbée dans l'onglet A puis supprimée (route `/conformite` redirigée).
- Accessibilité : pastille avec texte (pas la couleur seule), onglets `role="tablist"`, modales focus-piégées (déjà dans `Modal`).
- Montants affichés via `fcfa()`, pourcentages avec la précision de la base (arrondi à l'affichage uniquement).
- Régénérer `web/src/lib/database.types.ts` après chaque migration ; recharger PostgREST.

## 7. Découpage en lots

| Lot | Contenu | Contrôles de sortie |
|---|---|---|
| **L1** Constantes | `parameter_catalog` + amorçage, `set_parameter`, `reset_parameter`, verrou des périodes calculées, rollback | `scripts/test-sql.ps1` (nouveau `tests/sql/constantes_*.sql` : pas d'impact sur paie calculée, réinitialisation, borne, date d'effet), `verify-payroll.ps1` inchangé |
| **L2** Scan et dérogations | `compliance_scans`, `compliance_waivers`, `run_compliance_scan`, nouvelles règles branchées, `grant/revoke_waiver` | tests SQL (état vert/orange/rouge, dérogation expirée, rôle refusé) ; revue `ecc:database-reviewer` |
| **L3** UI constantes | onglet B | `npm run check`, `build`, e2e menu |
| **L4** UI cohérence et registre | onglets A et C, modale de dérogation | e2e + `a11y.spec.ts` |
| **L5** Tableau de bord | widget, redirection `/conformite`, doc de la page | e2e menu par rôle |

Chaque lot : migration + rollback dans `db/rollback/`, application dans `soma-rh-local-postgres-1`, `notify pgrst, 'reload schema'`, types régénérés, `graphify update .`, `/ecc:code-review` avant commit.

## 8. Décisions prises (2026-11-09) — elles prévalent sur le reste du document

1. **Saisie RH, validation admin.** `rh` (et `paie` pour les constantes) *saisit* une dérogation ou une modification de constante ; elle reste « en attente » jusqu'à décision de l'`admin` dans une **fenêtre de validation**. L'admin qui saisit lui-même est approuvé d'office (la trace garde les deux rôles). Hypothèse retenue : la règle vaut pour les dérogations **et** les constantes — à corriger si elle ne vaut que pour l'un des deux.
   - Table `approval_requests(id, kind 'derogation'|'constante', payload jsonb, status 'en_attente'|'approuvée'|'refusée', requested_by, requested_at, decided_by, decided_at, decision_note)`. Une demande ne produit aucun effet tant qu'elle n'est pas approuvée ; l'approbation exécute `grant_waiver` / `set_parameter`. Refus : motif obligatoire.
   - Quatrième onglet **D. À valider** (admin) + compteur sur le tableau de bord et dans le menu. Le demandeur voit l'état de ses demandes.
2. **Pas d'expiration des dérogations.** Colonne `expires_on` supprimée. Une dérogation reste `active` jusqu'à ce que (a) une nouvelle dérogation soit saisie pour la même règle et la même entité (l'ancienne passe `remplacée`), ou (b) la constante concernée soit réinitialisée à son défaut (les dérogations liées passent `levée`), ou (c) l'admin la révoque. Statuts : `active`, `remplacée`, `levée`, `révoquée`. Une dérogation liée à une constante mémorise le `parameter_code` et la valeur au moment de l'octroi.
3. **Tout est éditable, barèmes compris** (IR, TRIMF, réductions familiales, heures sup., préavis, quotité cessible, indemnités). Principe unique : **un barème = un jeu de lignes daté**. Modifier = créer un nouveau jeu complet à partir de l'actuel, avec sa date d'effet ; jamais d'`update` des lignes d'un jeu déjà utilisé par une paie `Calculée`+. À vérifier en L1b : les tables sans `effective_from` (`overtime_rates`, `notice_scales`, `garnishment_scale`, `severance_scales`) reçoivent cette colonne (valeur = date d'entrée en vigueur actuelle) et les fonctions de calcul sont adaptées pour lire le jeu en vigueur à la date de la paie — **ce point touche `compute_salary_slip` : `verify-payroll.ps1` obligatoire**. Les barèmes passent dans le catalogue avec `kind = 'bareme'` et un éditeur de tableau (ajout/suppression de tranches, contrôle de continuité des bornes).
4. **Références légales : amorçage depuis l'existant, puis réglage par l'admin.** L'amorçage reprend `legal_sources` et les en-têtes de migrations, plus `docs/CODE_TRAVAIL_2026_SPECIFICATION_SOMA_RH.md` et `docs/modules/INVENTAIRE_PARAMETRES.md` ; aucune référence n'est inventée, ce qui manque reste « à fournir ». Ensuite l'admin peut ajuster texte de loi, article, décret et statut (`à confirmer` → `confirmé`) depuis la page, chaque changement tracé dans `audit_log`.

Impact sur les lots (§7) : L1 se scinde en **L1a** (constantes simples, catalogue, références) et **L1b** (barèmes datés + éditeur de tableau) ; un lot **L2b** ajoute la file de validation (onglet D) entre L2 et L3.

## 9. Avancement et file d'attente (mis à jour le 2026-11-09, pause pour la recette utilisateur)

### Livré et commité
| Lot | Contenu | Commit |
|---|---|---|
| L1a | Catalogue des constantes (28), modification versionnée, réinitialisation, verrou des paies calculées | `35b6b937` |
| L1b | Barèmes datés et éditables (impôt, heures sup., quotité cessible, licenciement, retraite, préavis) ; `severance_coefficient` lit enfin son barème | `57eebd20` |
| L2 | Scan vert / orange / rouge, registre durable des dérogations, règles CDD-DUREE et constantes non confirmées | `82b409ca` |
| L2b | File de validation : le RH et la paie saisissent, l'administrateur valide | `087e2073` |
| L3 | Page `/centre-conformite` (constantes, barèmes, À valider), compteur de menu, écritures directes réservées à l'administrateur | `d8f7b073` |

### En file d'attente (non commencé)
- **L4 — onglets Cohérence et Dérogations** : pastille verte / orange / rouge et bouton « Lancer le scan » (`run_compliance_scan`), tableau des écarts (`compliance_open_findings`) filtrable par gravité et domaine, actions par ligne « Déroger » (modale : motif obligatoire, via `request_waiver`) et « Corriger » (lien selon `fix_target` : salarié, société, paramètre, planning, paie), registre des dérogations (statut, auteur, demandeur, révocation par l'administrateur via `revoke_waiver`). L'onglet par défaut de la page devient Cohérence.
- **L5 — intégration** : widget « Conformité » sur le tableau de bord (`compliance_status`, pastille + date du dernier scan + lien), redirection de l'ancienne page `/conformite` vers le centre puis suppression de `CompliancePage.tsx`, mise à jour de `docs/` et de la matrice de recette.

### Suites identifiées (à arbitrer après la recette)
1. **Règles non couvertes faute de donnée** : renouvellements et cumul de 4 ans des CDD (aucun compteur en base) ; contingent annuel d'heures supplémentaires (aucun paramètre, valeur à fournir).
2. **Références légales** : seules `DEC_2009_1412` et `IFC_INTERIM` sont confirmées ; toutes les autres sont « à confirmer » (revue du juriste). L'administrateur peut les régler depuis la page.
3. **Trois règles de calcul** (base de l'indemnité de licenciement, IPM des prestataires, transport en cas d'absence) restent modifiables directement par l'administrateur depuis Paramètres, sans circuit de validation : ce ne sont pas des constantes du catalogue.
4. **`v_conformite_retenues`** juge les anciens bulletins avec le barème de quotité cessible du jour (contrôle, pas calcul de paie).
5. **Tests d'interface** : pas de compte QA `rh` / `paie` (le parcours « le RH envoie une demande » n'est couvert qu'en SQL) ; `a11y.spec.ts` instable sous charge (échecs différents d'un passage à l'autre, tous verts isolément) à relancer sur une machine peu chargée.
6. **Ancien bouton « Déroger »** (page Conformité) : il crée désormais une demande, l'écart n'apparaît « dérogé » qu'après approbation de l'administrateur.

### Points à observer pendant les tests utilisateurs
- Un RH modifie une constante : la demande apparaît chez l'administrateur (compteur du menu, onglet À valider), rien ne change avant approbation ; le refus exige un motif et notifie le demandeur.
- Date d'effet : impossible avant le premier mois libre (des paies sont calculées jusqu'au mois précédent) ; une paie calculée ne change jamais, vérifier par `scripts/verify-payroll.ps1`.
- Réinitialisation : la valeur d'origine revient, y compris sur les versions futures encore modifiables.
- Barème : continuité des tranches (départ à 0, pas de trou, dernière tranche sans limite) ; majoration d'heures sup. refusée sous le minimum légal.
- Écran Paramètres : en lecture seule pour le RH et la paie, renvoi vers le centre.
