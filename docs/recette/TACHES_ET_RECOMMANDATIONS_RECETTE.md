# SOMA-RH — Tâches et recommandations issues de la recette du 04/11/2026

# SOMA-RH — Tâches et recommandations issues de la recette du 05/11/2026

Source : `RESULTATS_SIMULATION_100_2026-11-04.md` (défauts D-01 à D-18, tests C-01 à C-10, Bloc E) + résultats session scaling 05/11/2026. Mettre à jour les cases au fil de l'avancement.

## A. Corrections à faire (par priorité)

### Majeur
- [ ] **D-08** Organigramme illisible à 125 personnes à l'ouverture : adapter le zoom initial (ajuster à la fenêtre), repli par défaut des niveaux profonds.
- [ ] **D-09** Un salarié voit les pastilles « + » et « 19 anomalie(s) » dans l'organigramme : masquer toute action d'édition et tout indicateur d'anomalie hors rôle rh/admin.
- [ ] **D-17** Séparer la base de test des données réelles (salariés S00xx visibles en /demandes) : base ou schéma dédié aux tests QA.

- [ ] **D-19** /paie/gouvernance : afficher « Approuver la paie » au rôle rh (autorisé) et le masquer au rôle paie (refusé par l'API).

- [ ] **D-24** Bloquer une demande de congé qui chevauche un congé approuvé.
- [ ] **D-25** Bloquer ou alerter sur une absence dans un mois de paie validé/clôturé.
- [ ] **D-26** Contrôler le solde de congé (alerte ou blocage si négatif) et la cohérence du type (maternité).
- [ ] **D-27** Alimenter automatiquement la paie (absence non payée, maladie) à partir du congé approuvé, ou signaler clairement la double saisie.
- [ ] **D-30** Plafonner la retenue de prêt (quotité cessible) et ajouter un contrôle « net négatif » avant validation.
- [ ] **D-31** Plafond configurable sur les acomptes (ex. % du salaire).
- [ ] **D-32** Créer automatiquement l'avance/retenue à l'approbation d'un acompte.

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

## B. Tests restant à faire
- [ ] E-4 : un même compte ne peut pas valider les deux niveaux de congé.
- [x] Bloc A avec comptes rh et paie : PASS. Reste à confirmer le périmètre voulu du rôle paie dans Paramètres (Référentiels RH, Journal).
- [x] Bloc B-2 : seuils orange PASS. À trancher : D-34 (présences antérieures à l'affectation ignorées) et D-35 (ligne sans « Présent » = absence).
- [x] Bloc C-03b : poste prévu « À pourvoir avant/après » PASS (poste TECHNICIEN prévu dans QA Exploitation, conservé). À corriger : D-36 (formule annoncée vs calculée), D-37 (donner un poste aux salariés QA dans le générateur), D-38 (matricule dans les listes de la simulation).
- [ ] Bloc F (partiel : calcul, contrôle, revue, approbation PASS) : valider/payer Décembre 2026 à partir du 01/12/2026 (ou donner une structure salariale aux 23 salariés réels bloquants) et tester la séparation saisie/validation (bulletins du salarié : isolation PASS) ; supprimer ou remettre en Calculée les traitements de test Décembre 2026 et Décembre 2025 ; lancer `scripts/verify-payroll.ps1` après toute modification de `compute_salary_slip`.
- [x] Bloc G : focus clavier validé par revue de code (à confirmer visuellement) (montants, retour arrière, 400 px, libellés : PASS).
- [x] Sécurité : inscription fermée (403) : PASS. À corriger D-40 : masquer le lien « Créer un compte » et le texte « premier compte administrateur » quand l'inscription est fermée.
- [ ] Mesurer les temps de chargement chiffrés (/salaries, /equipes/organigramme, /mon-equipe) avec 125 fiches.
- [ ] Soldes de congés avant/après validation (créer d'abord une dotation).

## C. Données de test
- [x] Services QA rattachés aux directions QA (organigramme → Directions → Modifier → « Dépend de »). 19 salariés restent sans lien hiérarchique.
- [ ] Documenter dans `scripts/qa-reset-scenario.ps1` le scénario `pme-100` et la procédure de sauvegarde/restauration (`backups/`).

## D. Recommandations
1. Garder le jeu `pme-100` comme base de non-régression fonctionnelle, avec une sauvegarde de référence.
2. Ajouter une vraie boîte de dialogue de confirmation (composant partagé) : un seul composant pour Appliquer, Rejeter, Supprimer.
3. Automatiser les parcours critiques (connexion par rôle, congés à deux niveaux, simulation) en tests Playwright pour éviter de refaire la recette à la main.
4. Prévoir un écran de rattachement en masse des unités à leur direction.
5. Ne jamais copier de données personnelles de salariés dans des fichiers suivis par Git (règle du projet).

## E. Nettoyage de la base de test
- [ ] Supprimer ou annuler les demandes « Sim - … », les prêts de test (QA0011, QA0012), l'absence du 14/09 de QA0011, le traitement « Décembre 2026 » ; ou restaurer la sauvegarde puis rejouer `pme-100`.

## F. Compléments du 05/11/2026
- [x] Structures salariales des 23 salariés réels (date de début reculée à l'entrée) ; Décembre 2025 recalculé et validé (F-9 et F-10 : voir section 17 des résultats).
- [ ] D-43 : enregistrer une approbation avant toute validation (ou retirer le raccourci Calculée → Validée).
- [ ] D-44 : proposer « Recalculer » / « Remettre en Calculée » pour un mois « Réouverte ».
- [ ] D-45 : cantonner le recalcul d'un mois passé à son effectif d'origine.
- [ ] D-47 : exporter les paiements avant d'annuler un mois « Payé ».
- [x] Paiements de Mars (28/03 présumé) rétablis et Mars, Avril, Mai clôturés (05/11).
- [x] Simulation 2025 (janvier à novembre, payés au 28 et clôturés) et complément Mars à Juillet 2026 (05/11) : voir section 19 des résultats.
- [x] D-49 corrigé le 05/11/2026 (migration `20261107110000_d49_periode_cloturee_paiements_variables.sql`, test `tests/sql/d49_periode_cloturee.sql` OK) ; [ ] D-50, D-51 : voir section 19 ; plan de tests restants dans TESTS_RESTANTS_ET_RECOMMANDATIONS.md.
- [ ] D-52 : appliquer la migration 20261107100000_mois_valides_payes_clotures.sql (tableau de bord annuel, cumuls, journal) puis vérifier G-10.
- [x] Blocs H à M (société unique) : section 20 des résultats, avancement et éléments à développer dans TESTS_RESTANTS_ET_RECOMMANDATIONS.md (sections 9 et 10).
- [ ] D-53 à D-61 : voir section 20 (priorité : D-49 complément, D-55, D-57, D-58, D-59).
