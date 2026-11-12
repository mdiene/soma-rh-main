# SOMA-RH — Tâches et recommandations issues de la recette du 05/11/2026

Source : `RESULTATS_SIMULATION_100_2026-11-04.md` (défauts D-01 à D-18, tests C-01 à C-10, Bloc E) + résultats session scaling 05/11/2026. Mettre à jour les cases au fil de l'avancement.

## A. Corrections à faire (par priorité)

### Majeur (issues identifiées par la session scaling)
- [ ] **D-08** Organigramme illisible à 125 personnes à l'ouverture : adapter le zoom initial (ajuster à la fenêtre), repli par défaut des niveaux profonds.
- [ ] **D-09** Un salarié voit les pastilles « + » et « 19 anomalie(s) » dans l'organigramme : masquer toute action d'édition et tout indicateur d'anomalie hors rôle rh/admin.
- [ ] **D-17** Séparer la base de test des données réelles (salariés S00xx visibles en /demandes) : base ou schéma dédié aux tests QA.
- [ ] **D-40** Masquer le lien « Créer un compte » et le texte « premier compte administrateur » quand l'inscription est fermée.

### Mineur
- [ ] **D-23** Message d'erreur français pour dates incohérentes ; **D-28** action claire de remise en brouillon d'un mois calculé ; **D-29** afficher les erreurs de saisie (montant nul/négatif) ; **D-33** « Mes demandes » à cohérence avec les congés.
- [ ] **D-20 / D-21 / D-22** Compteur d'approbations bloqué à 0 ; bandeaux « PÉRIODE CLÔTURÉE » toujours visibles ; décembre inclut des salariés réels.
- [ ] **D-07 / D-13** Remplacer `confirm()` (Appliquer la simulation) et `prompt()` (motif de refus de congé) natifs par des fenêtres/champs dans la page : inutilisables dans le navigateur intégré et peu accessibles.
- [ ] **D-10** Menu latéral : afficher un état de chargement au lieu de « aucun rôle attribué » juste après connexion.
- [ ] **D-11 / D-01** Homonymes (« Khady N'Diaye » en double) : afficher le matricule dans les listes de choix (Délégué, etc.).
- [ ] **D-12** Mobile : le menu se referme au défilement et la déconnexion est difficile à atteindre.
- [ ] **D-14** « Mon équipe » : afficher « Congé annuel payé » au lieu du code brut `CONGE_ANNUEL`.
- [ ] **D-15** « Mon équipe » : message vide cohérent quand il n'y a plus de congé à valider ; supprimer la contradiction avec « Demandes de l'équipe ».
- [ ] **D-16** Formulaire « Nouvelle demande » : réinitialiser les champs après envoi.
- [ ] **D-18** Afficher au salarié le motif de refus saisi par le manager.

### Issues issues de la session scaling :
- [ ] **B-01** : Base de test surchargée (100 salariés test + données réelles) cause affichage lent et conflits
- [ ] **B-02** : Conflit données QA / réelles (salariés S00xx visibles en /demandes)
- [ ] **B-03** : Performances - temps de chargement non mesurés à 125 fiches, affichage lent organigramme
- [ ] **B-04** : Sécurité inscription fermée - lien "Créer un compte" doit être masqué quand inscription fermée

### B. Tests restant à faire
- [ ] E-4 : un même compte ne peut pas valider les deux niveaux de congé.
- [x] Bloc A avec comptes rh et paie : PASS. Reste à confirmer le périmètre voulu du rôle paie dans Paramètres (Référentiels RH, Journal).
- [x] Bloc B-2 : seuils orange PASS. À trancher : D-34 (présences antérieures à l'affectation ignorées) et D-35 (ligne sans « Présent » = absence).
- [x] Bloc C-03b : poste prévu « À pourvoir avant/après » PASS (poste TECHNICIEN prévu dans QA Exploitation, conservé). À corriger : D-36 (formule annoncée vs calculée), D-37 (donner un poste aux salariés QA dans le générateur), D-38 (matricule dans les listes de la simulation).
- [ ] Bloc F (partiel : calcul, contrôle, revue, approbation PASS) : valider/payer Décembre 2026 à partir du 01/12/2026 (ou donner une structure salariale aux 23 salariés réels bloquants) et tester la séparation saisie/validation (bulletins du salarié : isolation PASS) ; supprimer ou remettre en Calculée les traitements de test Décembre 2026 et Décembre 2025 ; lancer `scripts/verify-payroll.ps1` après toute modification de `compute_salary_slip`.
- [x] Bloc G : focus clavier validé par revue de code (à confirmer visuellement) (montants, retour arrière, 400 px, libellés : PASS).
- [x] Sécurité : inscription fermée (403) : PASS. À corriger D-40 : masquer le lien « Créer un compte » et le texte « premier compte administrateur » quand l'inscription est fermée.
- [ ] Mesurer les temps de chargement chiffrés (/salaries, /equipes/organigramme, /mon-equipe) avec 125 fiches.
- [ ] Soldes de congés avant/après validation (créer d'abord une dotation).

### C. Données de test
- [x] Services QA rattachés aux directions QA (organigramme → Directions → Modifier → « Dépend de »). 19 salariés restent sans lien hiérarchique.
- [ ] Documenter dans `scripts/qa-reset-scenario.ps1` le scénario `pme-100` et la procédure de sauvegarde/restauration (`backups/`).

### D. Recommandations
1. Garder le jeu `pme-100` comme base de non-régression fonctionnelle, avec une sauvegarde de référence.
2. Ajouter une vraie boîte de dialogue de confirmation (composant partagé) : un seul composant pour Appliquer, Rejeter, Supprimer.
3. Automatiser les parcours critiques (connexion par rôle, congés à deux niveaux, simulation) en tests Playwright pour éviter de refaire la recette à la main.
4. Prévoir un écran de rattachement en masse des unités à leur direction.
5. Ne jamais copier de données personnelles de salariés dans des fichiers suivis par Git (règle du projet).

### E. Nettoyage de la base de test
- [ ] Supprimer ou annuler les demandes « Sim - … », les prêts de test (QA0011, QA0012), l'absence du 14/09 de QA0011, le traitement « Décembre 2026 » ; ou restaurer la sauvegarde puis rejouer `pme-100`.
- [ ] Documenter dans `scripts/qa-reset-scenario.ps1` le scénario `pme-100` et la procédure de sauvegarde/restauration.

### F. État actuel du plan de développement

| Lot | Identifiant | Éléments | Statut | Effort |
|-----|-------------|----------|--------|--------|
| 1 | DEV-01 | Sécurité API | ✅ Terminé | S |
| 2 | DEV-02 | Règles contestées registre légal | ✅ Terminé | S |
| 3 | DEV-03 | Journal comptable | ✅ Terminé (fonctions SQL) | M |
| 4 | DEV-04 | IPRES/CSS et États DGID | ✅ Terminé (migraison SQL) | M |
| **5** | **DEV-05** | **Envoi réel notifications** | **✅ Terminé** | **S** |
| **6** | **DEV-06** | **Solde tout compte** | **⚠️ En cours** | **M** |
| 7 | DEV-07 | Virement/Mobile Money | ⏳ En attente | M/L |
| 8 | DEV-08 | MFA/SSO | ⏳ En attente | M |
| 9 | DEV-09 | Recrutement/formation | ⏳ En attente | L |

**Lots S (Sécurité) :** 2 sur 2 terminés (100%)  
**Lots M (Moyen) :** 3 sur 6 terminés (43%) — DEV-03, DEV-04, DEV-05  
**Lot L (Long/Extension) :** 0 sur 1 — DEV-09 (à valider)

### Orientation stratégique suite session scaling :
1. **Séparer les bases** : Considérer la base de test `pme-100` comme base de non-régression, isolée des données réelles
2. **Sécurité d'abord** : D-40 doit être implémenté avant toute nouvelle fonctionnalité d'inscription
3. **Performances** : Temps de chargement à mesurer impérativement à 125 fiches avant de nouvelles fonctionnalités
4. **Qualité avant quantité** : Privilégier la correction des bugs existants (D-08 à D-40) plutôt que de nouvelles fonctionnalités
5. **Automatisation** : Les tests critiques (connexion par rôle, congés à deux niveaux, simulation) doivent être en Playwright

### Orientation technique :
1. **Base de test isolée** : Créer un schéma `test_pme_100` dédié, ne jamais mélanger données réelles et QA
2. **Sécurité par défaut** : L'inscription fermée doit être la règle par défaut, le lien d'inscription masqué
2. **Progressive enhancement** : Les fonctionnalités complexes (MFA, SSO, Mobile Money) viennent après les corrections de base
3. **Qualité code** : Respecter le palette de couleurs, police Archivo, chiffres tabulaires à tous les lots

### G. Prochaines actions

1. **Nettoyage base de test** : Supprimer ou annuler les demandes « Sim - … », les prêts de test (QA0011, QA0012), l'absence du 14/09 de QA0011, le traitement « Décembre 2026 » ; ou restaurer la sauvegarde puis rejouer `pme-100`
2. **Mise en œuvre D-40** : Masquer lien inscription quand fermée
3. **Démarrage Lot 6** : Solde de tout compte, certificat de travail, sortie salarié
   - Ou choisir un autre lot selon priorité

**État actuel** : 5 lots sur 9 terminés (56%). Prochaine étape : Nettoyage base de test + Lot 6 ou décision sur le lot suivant.
---

### H. Suivi conformité Code du Travail 2026 — à reprendre (mis à jour le 2026-11-06)

**Fait** : D30/D53 appliquée sur la base locale (+ `20261107140000_revoke_execute_anon_d30_d53`, correctif D-021) ; `verify-payroll` identique à la référence ; tests SQL `d30`, `rpc_droits`, `sortie_salarie`, `settings_dated` verts. Sauvegarde : `backups/soma_rh_avant_d30d53_20261106_110259.sql`.

**Non fait / à reprendre**

| # | Reste à faire | Détail |
|---|---|---|
| H1 | ~~Types web~~ FAIT 2026-11-06 (voir H14) | `web/src/lib/database.types.ts` ne contient pas `app_parameters` (ni `get_loan_max_rate`, `set_loan_max_rate`). Aucune commande de génération n'est documentée dans le dépôt : trouver la commande (Supabase CLI `gen types --db-url` ?) puis la documenter dans `docs/LOCAL_SETUP.md`. |
| H2 | Build web | `npm run lint` et `npm run build` dans `web/` non lancés après D30/D53 (dépend de H1). |
| H3 | Doublons de timestamp | `20261105100000` : trois fichiers (`Dev04_IPRES_DGID`, `_backup`, `_fixed`) ; `export_ipres_css` est déjà en base, fichier d'origine inconnu. Aussi `20261104150000`, `…160000`, `…180000`, `20261107120000` (deux fichiers chacun). Ne pas rejouer `_backup` ni `_fixed`. |
| H4 | Retours manquants | Propositions de CP-01 (`docs/copilot/propositions/`) à relire puis déplacer dans `db/rollback/` : `equipe_soldes`, `Dev03_journal_comptable`, `Dev04_IPRES_DGID`, `Dev05_notifications_log`, `Dev09_…`. |
| H5 | Nom accentué | `20261108090000_Dev09_recrutement_formation_évaluation.sql` : renommer en ASCII par une procédure qui n'altère pas l'historique (déjà appliquée). |
| H6 | Rien n'est commité | 8 fichiers modifiés + fichiers non suivis (c26, Dev04-09, docs, tests SQL, mod, copilot). Commit par lots après revue du diff. |
| H7 | CI | CP-02 (tests unitaires JS, contrôle des migrations, `.gitattributes`) et CP-03 (audit `web/src`) en file Copilot : `docs/copilot/FILE_DE_TACHES.md`. |
| H8 | Test D30 | `tests/sql/d30_net_negatif_plafond_pret.sql` corrigé (compte « salarié pur ») : à intégrer au suivi Git. |
| H9 | Lots c26 B à G | B (sorties et indemnités), C (retenues 2/3 et quotité cessible), D (embauche et affiliation), E (écran conformité), F (échéancier cotisations), G (heures sup et préavis). Détail : `CADRAGE_CODAGE_CONFORMITE_CODE_TRAVAIL_2026.md` §4. |
| H10 | Juriste | Questions du cadrage §7 à trancher avant les lots B et C. |

**Mise à jour lot A (2026-11-06)** : les 3 migrations c26 sont appliquées (sauvegarde `backups/soma_rh_avant_c26_20261106_112128.sql`), `verify-payroll` identique, lint/build web verts. Restent :

| # | Reste à faire | Détail |
|---|---|---|
| H11 | ~~Types web (H1 élargi)~~ FAIT 2026-11-06 | `npx supabase@latest gen types typescript --db-url …` fonctionne mais produit un autre format que le fichier actuel (2695 lignes contre 2844, sans en-tête `Json` ni `__InternalSupabase`, ajoute `ComputedFields`) : non substituable tel quel. Piste : version de la CLI alignée sur PostgREST 14.17, ou formatage (`oxfmt`, refusé par le mode auto, à autoriser). Types absents : `app_parameters`, `legal_sources`, `exit_reasons`, etc. |
| H12 | Précision 2/3 | `plafond_retenues(150000)` = 100000,00000000000000050000 (taux stocké 0,6666666666666667). Sans effet à l'affichage ; si besoin, arrondir à 6 décimales comme `verify-payroll` ou stocker la fraction. |
| H13 | Registre légal | §6 du cadrage : ajouter les lignes « à confirmer » dans `docs/regles-de-paie/registre-legal.mdx`. |

| H14 | Types régénérés | Fait : procédure dans `docs/LOCAL_SETUP.md`. Reste : retirer la retouche manuelle (`| null` sur 2 arguments RPC) en passant `reason ?? undefined` dans `web/src/lib/api.ts` (lignes ~102 et ~152) quand ce fichier sera libre ; ancien fichier conservé hors dépôt (scratchpad `database.types.AVANT.ts`). |

**Lot B appliqué (2026-11-06)** : migration `20261110090000_lotb_sorties_indemnites` (+ retour testé), sauvegarde `backups/soma_rh_avant_lotB_*.sql`, test `tests/sql/lotb_sorties_indemnites.sql`.

| # | Reste à faire | Détail |
|---|---|---|
| H15 | Enregistrer la nouvelle référence de non-régression | **En attente d'accord de Moussa.** Le script de non-régression échoue pour une raison structurelle : `totals` contient deux clés de plus (`special_indemnity`, `funeral_indemnity`, valeur 0 pour les 26 bulletins). Brut et net inchangés ; l'empreinte sans ces deux clés est identique à la référence. Enregistrer la référence (option de sauvegarde du script) seulement après accord. |
| H16 | Liste des motifs dans l'interface | `web/src/pages/EmployeeDetailPage.tsx` (~l.177) liste encore 5 motifs en dur ; lire `exit_reasons` (tâche CP-04 de `docs/copilot/FILE_DE_TACHES.md`). Afficher aussi les lignes `IND_SPECIALE` et `IND_FRAIS_FUNERAIRES` du bulletin de sortie. |
| H17 | Tests déjà en échec avant le lot B | `tests/sql/payroll_separation.sql` (« refus non journalisé ») et `tests/sql/livre_de_paie.sql` (« 2508 lignes avec un cumul annuel différent ») échouent aussi sans le lot B (vérifié en appliquant le retour). À instruire à part. |
| H18 | Hypothèses lot B à confirmer (juriste) | Base d'un mois = salaire de base + sursalaire + prime d'ancienneté ; régime fiscal des indemnités spéciale et funéraires (traitées comme non imposables, comme l'indemnité de licenciement) ; décès < 12 mois : frais funéraires seuls ; plan social : seules l'indemnité spéciale et celle de licenciement sont codées (équivalent préavis et indemnité négociée non codés). |
| H19 | Ancien code `LICENCIEMENT` | Sous 12 mois d'ancienneté il ne donne plus d'indemnité (règle C26-05 appliquée aussi aux anciens dossiers) ; aucun salarié concerné en base (2 sorties, motif DEMISSION). |
| H20 | Types | `funeral_indemnity_months` ajouté à la main dans `database.types.ts` (même retouche que H14) ; à régénérer proprement avec la procédure de `docs/LOCAL_SETUP.md`. |

**H15 clos (2026-11-06)** : nouvelle référence de non-régression enregistrée avec l'accord de Moussa après le lot B (empreinte `1103f16b…`, 26 bulletins, brut 5 017 834,603926, net 4 765 432,331600, inchangés). Ancienne empreinte : `ed197d23…`.
**H21** : le garde-fou du mod `soma-suivi` ne surveille que l'outil Bash ; la même commande passe par PowerShell sans contrôle. À étendre à PowerShell et à prévoir un mécanisme d'accord explicite.

**Lot C appliqué (2026-11-06)** : migration `20261111090000_lotc_controle_retenues` (+ retour), test `tests/sql/lotc_controle_retenues.sql`. Vue de contrôle seule (`v_conformite_retenues`) : ni le net ni la validation ne sont modifiés, `verify-payroll` identique. 1 bulletin dépasse le plafond des 2/3 en base.

| # | Reste à faire | Détail |
|---|---|---|
| H22 | Blocage ou plafonnement des retenues | Décision de Moussa : bloquer la validation, plafonner le net dans `compute_salary_slip` (change l'empreinte, `-Save` après revue) ou laisser en alerte. |
| H23 | Hypothèses lot C (juriste) | Assiette = brut + non imposable ; « retenues » = `total_net_deductions` ; prélèvements obligatoires hors plafond ; questions du cadrage §7 (n° 3 et 5). |
| H24 | Prêts D30/D53 et lot C | Rapprocher le plafond de retenue de prêt (33 % du brut) du plafond des 2/3 ; RET-03 : un prêt ne se retient que par cession volontaire signée. |
| H25 | Types et écran | Régénérer `database.types.ts` pour `v_conformite_retenues` ; afficher la vue dans l'écran de conformité (lot E). |

**Lot D appliqué (2026-11-06)** : migration `20261112090000_lotd_blocage_premiere_paie` (+ retour = ancienne `transition_payroll_entry`), test `tests/sql/lotd_declaration_embauche.sql`. `transition_payroll_entry` refuse « Validée » si un salarié de la paie n'a aucun bulletin validé antérieur ET pas de `hire_declaration_ref`. `verify-payroll` identique. Les 128 salariés en base n'ont pas de référence : aucun n'est bloqué tant qu'ils ont une paie validée antérieure.

| # | Reste à faire | Détail |
|---|---|---|
| H26 | Saisie dans la fiche salarié | Champs `hire_declaration_ref`, `hire_declared_on`, `affiliation_date` absents de `EmployeeDetailPage.tsx` (fichier réservé à CP-04/Copilot : à faire après lui). Sans saisie, un nouvel embauché ne peut pas être validé. |
| H27 | Message de refus | Afficher l'erreur de validation (liste des matricules) dans `PayrollEntryPage`. |
| H28 | Affiliation | Reste en alerte (`v_conformite_embauche`), non bloquante à la 1re paie : à confirmer (juriste, CSS art. 89-90). |
| H29 | Types | Régénérer `database.types.ts` (procédure `docs/LOCAL_SETUP.md`) pour `assert_declaration_embauche` et `v_conformite_retenues`. |

**CP-04 repris par Claude (2026-11-06)** : `EmployeeDetailPage.tsx` lit `exit_reasons` (motifs `is_legacy` masqués sauf valeur existante) et saisit `hire_declaration_ref`, `hire_declared_on`, `affiliation_date`. Lint (0 erreur) et build verts. **H16 (liste des motifs) et H26 (saisie) soldés** ; reste de H16 : vérifier l'affichage des lignes `IND_SPECIALE` / `IND_FRAIS_FUNERAIRES` sur le bulletin de sortie, et H27 (message de refus dans `PayrollEntryPage`).

**Lot E appliqué (2026-11-06)** : migration `20261113090000_lote_ecran_conformite` (+ retour), test `tests/sql/lote_conformite.sql`, page `web/src/pages/CompliancePage.tsx` (route `/conformite`, menu Administration). `detecter_conformite()` synchronise `compliance_findings` avec `v_conformite_embauche` et `v_conformite_retenues` (idempotent, résout les écarts disparus) ; `deroger_constat(id, motif)` réservé au rôle RH, motif non vide. Lint (0 erreur) et build verts ; `verify-payroll` identique.

| # | Reste à faire | Détail |
|---|---|---|
| H30 | Types | `detecter_conformite` et `deroger_constat` ajoutés à la main dans `database.types.ts` (comme H14/H20) : régénérer avec la procédure de `docs/LOCAL_SETUP.md`. |
| H31 | Détection planifiée | `detecter_conformite()` n'est lancée que par le bouton « Actualiser » ; pas de tâche planifiée ni de lien avec le blocage de validation (lot D lit directement `hire_declaration_ref`). |
| H32 | Essai navigateur | Écran non essayé dans un navigateur (seuls tsc, lint, build et test SQL). Une dérogation RH ne désactive pas le blocage du lot D. |

**Lot F appliqué (2026-11-06)** : migration `20261114090000_lotf_echeancier_cotisations` (+ retour = ancienne `detecter_conformite`), test `tests/sql/lotf_echeancier.sql`. Table `contribution_payments` (RLS : lecture rh/paie, écriture paie), vue `v_echeancier_cotisations` (dû, échéance, jours restants, majoration estimée), règle `COT-ECHEANCE` (alerte à J-5 ou en retard) dans `detecter_conformite()`. `verify-payroll` identique ; tests `lote_conformite` et `lotf_echeancier` verts.

| # | Reste à faire | Détail |
|---|---|---|
| H33 | Saisie des versements | Aucun écran pour `contribution_payments` (la paie ne peut enregistrer un versement que par l'API) ; ajouter un formulaire et l'échéancier à `/conformite`. |
| H34 | Bruit de l'alerte | Sur la base de test, tous les mois passés non versés lèvent une alerte (≈ 12 constats). Décider d'une date de départ (mois de mise en service) ou saisir les versements historiques. |
| H35 | Hypothèses lot F (juriste) | Montant dû = IPRES RG/RC (salarié + patronal) + CSS AF/AT ; IPM, CFCE, IR, TRIMF hors échéancier ; effectif = salariés distincts du mois ; majoration : 10 % par mois ou fraction (le cadrage §1 évoque aussi 5 j → 10 %, 3 mois → 30 %, 8 mois → 50 % : à trancher) ; SS-05 [B] « clôture de paie sans déclaration générée » non codé ; SS-06 (cotisations exigibles à la sortie) non codé. |
| H36 | Types | `contribution_payments`, `v_echeancier_cotisations` à régénérer dans `database.types.ts`. |

**Lot G appliqué (2026-11-06)** : migration `20261115090000_lotg_hs_preavis` (+ retour = ancienne `compute_salary_slip`), test `tests/sql/lotg_hs_preavis.sql`. `compute_salary_slip` lit les coefficients d'heures supplémentaires dans `overtime_rates` via `hs_majoration()` (repli sur 1,15 / 1,40 / 1,60 / 2,00) ; `preavis_mois(salarié, date)` lit `notice_scales`. **`verify-payroll` identique** (référentiel inchangé, aucun écart à lister, pas de `-Save`) ; tests `lotb_sorties_indemnites` et `lotg_hs_preavis` verts.

| # | Reste à faire | Détail |
|---|---|---|
| H37 | Tranches d'HS | Le bulletin garde quatre colonnes de saisie (15/40/60/100) : « 60 » = `HS_NUIT` (`HS_REPOS_FERIE_JOUR` a le même taux, non distinguée) ; « 100 » = `HS_REPOS_FERIE_NUIT`. Le découpage automatique 8 premières heures / au-delà (colonnes `hours_from`/`hours_to`) n'est pas codé : la saisie reste manuelle par tranche. |
| H38 | Préavis non branché | `preavis_mois()` n'alimente ni le solde de tout compte ni l'indemnité compensatrice de préavis (qui doit payer ? motif imputable au salarié, dispense) ; à instruire avec le juriste avant de coder. Catégorie déduite de `staff_status` (cadres / maîtrise / sinon employé-ouvrier) ; `free_days_week` non exploité. |
| H39 | Hypothèse de taux | Taux de la table repris tels quels (CCNI art. 49) ; la convention propre à SOMA (cadrage §7 n°2) peut prévoir d'autres taux. |
| H40 | Types | `hs_majoration`, `preavis_mois` à régénérer dans `database.types.ts`. |

**Types régénérés (2026-11-06)** : `web/src/lib/database.types.ts` régénéré avec la procédure de `docs/LOCAL_SETUP.md` (plus aucune retouche manuelle) ; `api.ts` passe `reason ?? undefined`. tsc, lint (0 erreur) et build verts. **Soldés : H14, H20, H29, H30, H36, H40.**

**H3 et H5 tranchés (2026-11-06)**
- **Dev04 (`20261105100000`)** : `_backup` et `_fixed` (identiques) écartés du dépôt (copie dans le scratchpad de la session) : `_fixed` ne s'exécute pas (apostrophe non échappée dans une chaîne, « syntax error at or near create »). L'original est conservé. Sa fonction `export_ipres_css` (salaire fictif de 500 000 F) n'est pas celle de la base : la version réelle (lit le bulletin) est fixée par la nouvelle migration `20261116090000_dev04_export_ipres_css_reel` (+ retour = version d'origine), sans effet sur la base actuelle. `etat_dgid` était déjà identique.
- **Autres doublons** (`…150000`, `…160000`, `…180000`, `20261107120000`) : conservés sans renommage. Il n'existe pas de table de suivi des migrations (l'image PostgreSQL les rejoue par ordre alphabétique) : l'ordre est déjà déterministe par le nom, et un renommage casserait les références des retours, de `defects.mdx` et de l'historique Git sans rien corriger. Ils sont déclarés dans `scripts/migrations-allowlist.txt` (4 préfixes) ; `scripts/check-migrations.sh` passe (sa vérification des noms non ASCII échouait avec « syntax error in conditional expression » : corrigée).
- **Dev09 (H5)** : renommée en `20261108090000_Dev09_recrutement_formation_evaluation.sql` (ASCII). Aucun suivi de migrations, donc aucune base à ajuster. Son bloc final `drop table …` (dont `drop table if not exists`, invalide) est retiré : à la relecture, un rejeu aurait supprimé `evaluations` puis échoué. Le fichier s'exécute sans erreur (essai annulé).

| # | Reste à faire | Détail |
|---|---|---|
| H41 | RLS absente (Dev05, Dev09) | `notifications_log`, `candidatures`, `evaluations`, `job_postulations`, `trainings` : RLS désactivée en base (règle du projet : RLS + `has_role`). Données personnelles exposées à tout rôle ayant un droit de table : migration à écrire avant la mise en service. |
| H42 | Retour Dev09 | La proposition de retour (`docs/copilot/propositions/…evaluation_down.sql`) a été renommée ; à relire puis déplacer dans `db/rollback/` (H4). |

**H41 soldé (2026-11-06)** : migration `20261117090000_h41_rls_dev05_dev09` (+ retour), test `tests/sql/h41_rls_dev05_dev09.sql`. RLS activée sur `notifications_log`, `job_postulations`, `candidatures`, `trainings`, `evaluations` (les 5 tables étaient vides). Droits : RH gère tout ; salarié lit ses formations, candidatures et notifications (`my_employee_id()` / `auth.uid()`) ; évaluations et offres : RH seule ; paie : lit et écrit `notifications_log`. 3 index `created_by` ajoutés. `verify-payroll` identique, `rpc_droits` et le nouveau test verts.
Reste : le salarié ne voit pas son évaluation (choix prudent : commentaires de l'évaluateur ; à confirmer) ; manager sans accès aux formations/évaluations de son équipe ; aucune écran n'utilise ces tables (`web/src` ne les référence pas) ; doublon d'index sur `trainings(employee_id)` (`idx_trainings_employee_id` et `trainings_employee_idx`) à supprimer.


### I. Modules métier verticaux (ajouté le 2026-11-06)

Spécification : `docs/modules/MODULES_METIER_VERTICAUX_SOMA_RH.md` (v2) ; manifestes : `docs/modules/manifests/`. Priorités : P0 bloque un module · P1 avant activation chez un client · P2 amélioration. Aucune valeur non lue dans un texte ne doit être pré-remplie.

**Textes à fournir ou à lire**

| ID | Prio | Tâche | Débloque |
|---|---|---|---|
| T-MV-01 | P0 | Décret de dérogations à la durée légale (70-183, JO n° 4091 du 09/03/1970, vie-publique.sn/documents/4428) | Équivalences gardiennage, HORECA, transport (les 56/72 h du document de départ sont nigériens) — **06/11 : ◐ décret trouvé (art. 4 équivalences) mais seuils gardiens non lus ; JO 4091 à déposer pour OCR** |
| T-MV-02 | P0 | Décret 70-184 (taux des heures supplémentaires) | `overtime_rates` conforme (115/140/160/200 % : texte ou classeur ?) — **06/11 : ◐ +15/+40/+60/+100 % (guides concordants), texte JO 4091 p.259 à lire** |
| T-MV-03 | P0 | Décret 2009-1412 (travail temporaire) et son maintien sous le Code 2026 (art. 459-461) | IFC 7 %, égalité de rémunération, module Intérim — **06/11 : ✔ maintien (art. 461) ; ✖ taux IFC non lu ; ◐ durée max 2 ans** |
| T-MV-04 | P0 | Décret visé à l'art. 292 du Code 2026 (agrément, règles du travail temporaire) | Contrôles d'agrément et de missions — **06/11 : ✖ décret d'application non trouvé (art. 292 lu)** |
| T-MV-05 | P1 | Arrêté d'application du travail de nuit (art. 245 : 22 h–5 h) | Modalités de la nuit — **06/11 : ◐ décret 70-182 existe, texte non lu ; art. 245 = 22 h–5 h ✔** |
| T-MV-06 | P1 | Arrêté n° 11719 du 17/12/2009 : non retrouvé, à fournir ou à retirer du registre | Statut de la preuve de déplacement — **06/11 : ✖ introuvable, à retirer du registre ou à fournir** |
| T-MV-07 | P1 | Arrêtés CSS 2026 (taux, plafonds, répartition) | RL-001 à 009 « conforme » — **06/11 : ◐ CLEISS/OCDE 2026 : PF 7 %, AT 1/3/5 %, plafond 63 000 F ; arrêtés non fournis** |
| T-MV-08 | P1 | **Lire `sources-legales/CGI-Senegal-janvier-2025.pdf`** : barème IR (maximum 40 % ou 43 %), CFCE (3 % ou 5 % pour les étrangers), TRIMF, BRS (art. 200 et s., seuil 25 000 F) | Clôturer les écarts du §3 de la spécification — **06/11 : ✔ FAIT : IR 40 % jusqu'à 50 M puis 43 %, CFCE 3 %, TRIMF par tranche, BRS 5 % dès 25 000 F** |
| T-MV-09 | P1 | Arrêté 012914 (avantages en nature) | Module HORECA — **06/11 : ◐ logement 33 500 / 20 000 / 13 500 F par pièce (secondaire) ; nourriture ✖** |
| T-MV-10 | P2 | Conventions de branche (gardiennage, hôtellerie-restauration, transport, BTP, nettoyage) | Paniers, primes de risque, salissure — **06/11 : ✖ aucun texte de branche trouvé en ligne** |

**Développement**

| ID | Prio | Tâche | Lot |
|---|---|---|---|
| T-MV-20 | P0 | Table `module_manifest`, colonne `extra jsonb` sur salarié et contrat, validateur de schéma JSON (migration + RLS `has_role`) | M0 |
| T-MV-21 | P0 | Journal d'audit chaîné par hash (ajout seul) | M0 |
| T-MV-22 | P0 | Spike sécurité d'un langage d'expression borné (CEL ou JSONLogic) avec tests d'évasion | M1 |
| T-MV-23 | P0 | Moteur à graphe de règles : tri, détection de cycle, paramètre manquant → `compliance_findings` | M1 |
| T-MV-24 | P1 | Module Intérim : motif de mission (art. 293), emploi durable, journal des missions (art. 294), agrément (art. 292) | M2 |
| T-MV-25 | P1 | Module Gardiennage : équivalence, nuit, attestation de régularité sociale (art. 291, alerte J-30) | M3 |
| T-MV-26 | P1 | Cas dorés par module dans `verify-payroll` | M2-M4 |
| T-MV-27 | P1 | Bulletin modèle par catégorie (Gardien, Chauffeur, Intérimaire) | M2-M4 |
| T-MV-28 | P2 | Per diem en multiples du taux horaire (CCNI art. 61), justificatif géolocalisé facultatif | M2 |
| T-MV-29 | P2 | Facturation client (taux horaire, coefficient K, TVA 18 %) dans Finance | M5 |

**Décisions à prendre** : voir §10 de la spécification (équivalences, plafond AT de la CSS, barème IR, CFCE, IFC, GPS, Redis/multi-société, langage de formules).

**CP-02 / CP-03 relus (2026-11-06)** : `.gitattributes`, étape de tests unitaires et BOM de `ci.yml` corrigés ; audit `web/src` refait (`docs/copilot/RETOURS.md`).

| # | Reste à faire | Détail |
|---|---|---|
| H43 | ~~Erreurs de requêtes masquées~~ FAIT 2026-11-06 | `QueryCache({ onError })` (`main.tsx`) + bandeau `QueryErrorBanner` dans `Layout` (3 derniers messages, dédoublonnés, fermable). Essai navigateur non fait ; les pages peuvent encore afficher leur propre `ErrorNote` (cumul possible). |
| H44 | ~~Couleurs hors palette~~ FAIT 2026-11-06 (classes) | 98 classes `x-[#HEX]` remplacées par les jetons de la palette (52 identiques, 46 nuances alignées sur le jeton le plus proche, par choix de Moussa : légères différences de teinte, bandes de `GroupedTable` désormais toutes en `paper`). tsc, lint, build verts ; rendu non vérifié dans un navigateur. Reste hors classes : hexadécimaux des graphiques (`AnnualSynthesis`, `DashboardPage`, `PayrollForecast`, `exportPng.ts`, CSS d'organigramme, `shadow-[…_#DCE1DE]`), qui exigent de vraies valeurs de couleur. |
| H45 | ~~Export des paiements~~ FAIT 2026-11-06 | Confirmé par Moussa : le fichier est envoyé tel quel à la banque, donc arrondi à l'unité par virement (FCFA sans décimales) voulu. Constat : les nets en base ont des décimales (124 bulletins sur 125 en juillet) et la somme des nets arrondis diffère du total arrondi de 5 à 6 F par mois ; le total affiché sur `PayrollPaymentsPage` additionnait les nets non arrondis. Il additionne maintenant les nets arrondis, donc il égale la somme des virements du fichier. |
| H46 | ~~Types RPC~~ FAIT 2026-11-06 | `as never` retirés de 9 fichiers (12 RPC) ; `null` remplacé par `undefined` aux arguments facultatifs ; reste `PaymentControls.tsx` (aide générique `rpc(fn: string)`). `decide_leave` : test `tests/sql/decide_leave_droits.sql` (salarié simple et paie seule refusés). tsc, lint (0 erreur) et build verts. |
| H47 | CI : tests SQL | Job `rebuild` ajouté (reconstruction d'une base neuve). Les tests SQL et `verify-payroll` supposent les 128 salariés réels (non versionnés) : il faut encore un jeu de données synthétique (`tests/fixtures`, `scripts/local-synthetic-fixture-validation.ps1`) avant de les lancer en CI. |

| H48 | ~~Rejeu des migrations impossible~~ CONTOURNÉ 2026-11-06 | `db/migrations` seul ne se rejoue toujours pas (`--full` échoue à `20261031185900_payroll_rpc_security_definer.sql`, ordre hérité) ; on reconstruit par l'instantané `db/baseline/` + migrations postérieures (H49). Constat annexe : `docker/postgres-init/001-run-migrations.sh` accorde `select, insert, update, delete` sur toutes les tables à `authenticated` après les migrations, alors que la base locale a des tables en lecture seule (ex. `app_parameters`) : l'image Docker actuelle donne des droits plus larges que la base locale (la RLS reste en vigueur). À décider : faire charger l'instantané par l'image. |

- **Projet modules métiers (06/11/2026)** : dossier complet `modules/PROJET_MODULES_METIERS_MISE_EN_PLACE.md` et prompt de lancement `modules/PROMPT_LANCEMENT_MODULES_METIERS.md` (lots M0 à M7).
| H49 | ~~CP-05~~ FAIT par Claude 2026-11-06 | 1re tentative de Copilot rejetée (voir `RETOURS.md`). Refait : `db/baseline/` (`schema_local.sql`, `reference_data.sql`, README), `scripts/export-baseline.sh`, `scripts/replay-migrations.sh` (mode baseline par défaut, aucune erreur masquée), job CI `rebuild`. Vérifié : schéma rejoué = schéma local (0 ligne de différence), 22 tables de paramétrage identiques (md5), 0 salarié. |

**Vérification des travaux de Copilot (2026-11-06)** — résultat :
- CP-01 : propositions de retour rédigées par Claude (Copilot avait échoué). CP-02 : 3 défauts corrigés (`.gitattributes`, étape de tests, BOM). CP-03 : rapport refait. CP-04 : fait par Claude. CP-05 : rejeté puis refait par Claude.
- `.github/copilot-instructions.md` : conforme (aucune écriture en base, pas de commit, périmètres), mais Copilot ne l'a pas respecté pour CP-05 (rapport absent, statut faussement « vérifié »).
- Modifications antérieures relues (`isolation.test.mjs`, `vite.config.ts`, 3 pages web, `qa-reset-scenario.ps1`) : cohérentes. Le test du manager est assoupli (il peut lire ses propres bulletins validés, pas ceux d'autrui), ce qui est légitime ; le proxy Vite est limité au développement.
- **DEV-05 faussement déclarée « Terminée »** (`docs/comparatif/plan-de-developpement.mdx`) : voir H50.

| # | Reste à faire | Détail |
|---|---|---|
| H50 | DEV-05 notifications à refaire | `20261106100000_Dev05_notifications_log.sql` : les 2 fonctions ne compilent pas (`notifications_log%rowtype` sans `public.`) et sont inutilisables (`stable` + écriture, statut « sent » sans envoi, `failed_permanent` hors contrainte, `process_notifications` recrée des lignes). Seule la table existe (en base et dans l'instantané). Le fichier ne se rejoue pas en mode `--full`. À concevoir : file d'attente + worker réel (SMTP via `email_outbox` existante, SMS/WhatsApp à fournir), reprise sur échec. Le plan de développement est corrigé. |


**Retrait du planning des gardiens (2026-11-06, décision de Moussa)** : la gestion des gardiens sera un module métier activé à la demande. Retiré de la version de base : page `/planning` (« Planning des postes », action « Générer une rotation »), entrée de menu, bloc « Mon planning » de Mon espace, tables `work_posts`, `shift_types`, `shift_assignments` (1 037 affectations de test), fonction `generate_rotation`. Migration `20261120090000_retrait_planning_gardiens` (+ retour testé : structure rétablie et 1 037 affectations rechargées, essai annulé) ; sauvegarde `backups/soma_rh_avant_retrait_gardiens_20261106_140753.sql` (et `_donnees.sql`), ignorée par Git. Build vert, `audit_parametrage` et `verify-payroll` inchangés ; le rejeu `replay-migrations.sh` applique bien la migration après l'instantané.

**Correctif lié (3e récidive de D-013/D-021)** : `20261121090000_revoke_execute_anon_btree_gist`. La migration `m0` de Claude Desktop crée l'extension `btree_gist` dans `public` ; ses ~100 fonctions étaient exécutables par le rôle anonyme (`rpc_droits` en échec). Même correctif que D-013. À retenir pour le module : toute extension créée dans `public` exige ce `revoke` (idéalement dans la migration du module).

| # | Reste à faire | Détail |
|---|---|---|
| H51 | Types web | `database.types.ts` contient encore les 3 tables retirées (et il est modifié par Claude Desktop, non commité) : à régénérer quand ses modifications seront commitées. |
| H52 | Documents historiques | Les documents (`FEUILLE_DE_ROUTE*`, `ORGANIGRAMME_DECISIONS`, QA, analyses) citent encore le planning des gardiens ; ils sont conservés comme historique. Le futur module « sécurité / gardiennage » (`docs/modules/`) reprend le besoin (rotation 24 h/24, majorations de nuit, K15 du registre des risques). |
| H53 | Mémoire du poste | La machine manque de mémoire (environ 300-400 Mo libres sur 7,8 Go) : Docker a déjà redémarré deux fois et tué les conteneurs SOMA (code 255) ; `flowise` et `docling` (hors SOMA) occupent 1,4 Go. Les arrêter pendant le développement ou augmenter la mémoire de WSL. |

## Centre de conformité : liens « Corriger », fiche du constat et correction sur place (2026-11-12)

À vérifier à l'usage après la mise en service de la fiche du constat et de la modale « Corriger ici » :

- [ ] **CC-01** Après « Enregistrer et relancer le scan », la fiche du constat se ferme quand le constat est résolu. Décider s'il faut plutôt enchaîner sur le constat suivant de la liste (`FindingsTab.tsx`, état `openId`).
- [ ] **CC-02** `run_compliance_scan` est global : mesurer la durée de l'enregistrement sur une base volumineuse ; si elle gêne, prévoir un rescan limité au salarié modifié.

### Suivi des cotisations par caisse (2026-11-12)

- [ ] **CC-03** Paiement partiel d'une caisse : le montant payé est enregistré égal au montant dû. Ajouter un champ « montant versé » (la colonne `amount_paid` existe déjà dans `contribution_payment_lines`) dans la fenêtre « Marquer payé » de `PayrollContributionsPage.tsx`, et l'afficher dans le détail et l'historique.
- [ ] **CC-04** Régénérer `web/src/lib/database.types.ts` : la génération a été interrompue, le fichier ne contient ni `contribution_payment_lines` ni `v_contribution_follow`. La page utilise le client sans types (`dataApi as unknown as ApiClient`), à remplacer par le client typé après régénération.
- [ ] **CC-05** Lancer `menu.spec.ts` et `a11y.spec.ts` (nouvelle page `/paie/cotisations`, nouvelle entrée de menu) et vérifier à l'écran la fiche du constat, la surbrillance et le retour au constat.
