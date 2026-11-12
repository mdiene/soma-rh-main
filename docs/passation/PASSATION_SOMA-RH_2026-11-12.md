# Passation — reconstruction du guide utilisateur (12/11/2026)

Branche `docs/guide-utilisateur-complet` (issue de `fix/rpr-09-prorata`), **non poussée**, un commit par étape. Aucun mot de passe ni jeton dans ce document.

## Ce qui a été fait
- Base locale remise à zéro (sauvegarde `backups/soma-rh-20261112-153339.dump`), comptes `sim-*` recréés, tous les parcours existants rejoués avec succès, nouveaux parcours écrits (emplois, comptes et équipes, 41 écrans par rôle, embauches par contrat, états, connexion).
- Guide de 24 pages dans `docs/guide-utilisateur/`, captures dans `captures/` (64, masquage des champs sensibles) ; navigation `docs/docs.json` ; onglet « Documentation utilisateur » vérifié par test e2e.
- Matrice des cas d'usage, questions légales ouvertes, fiches RPR-16 et RPR-17 dans `docs/recette/simulation-200/`.

## À savoir pour reprendre
- L'état de la base est celui d'une paie 2026-05 à 2026-10 clôturée sur 200 salariés fictifs (matricules S0724 à S0923, plus 4 salariés d'essai SimCDD, SimSTAGE, SimPRESTATION, SimCOD).
- `verify-payroll.ps1` signale un écart : sa référence (26 bulletins) date de l'ancienne base ; elle n'a **pas** été réenregistrée (`-Save` interdit pendant la campagne).
- `scripts/test-sql.ps1` : 14 échecs, surtout des données de scénario QA absentes ; à rejouer sur un scénario chargé.
- `scripts/qa-create-users.ps1` échoue (inscription fermée) ; `tests/.env.qa` (hors Git) a été régénéré depuis `tests/.env.qa-sim`, ancienne version en `tests/.env.qa.bak-avant-guide`.
- `scripts/check-migrations.sh` signale toujours des préfixes en double (antérieur).
- Le site en ligne et Vercel n'ont pas été touchés. Le build lit `docs/` : vérifier que `docs/` est dans le périmètre de `scripts/vercel-deploy.ps1` avant de compter sur le guide en ligne.

## Décisions attendues du propriétaire
1. Pousser et fusionner la branche ?
2. Donner l'accès au guide à tous les rôles (entrée « Aide » dans `nav.ts`, qui touche `menu.spec.ts` et `a11y.spec.ts`) ? Aujourd'hui salariés et managers n'ont pas les Paramètres.
3. Rejouer les parcours non joués (heures supplémentaires, absences exceptionnelles, versements de cotisations, ordres de virement…) dans une seconde campagne ?
4. Trancher les questions de `QUESTIONS_LEGALES_OUVERTES.md`.

## Mise à jour du soir (12/11/2026) — publication, Aide et campagne 2
- **Fusionné et poussé** : `docs/guide-utilisateur-complet` puis `test/guide-campagne-2` dans `main` (commits f1e4127 et 843cbba). `main` = `origin/main`.
- **Guide ouvert à tous les rôles** : entrée « Aide et guide utilisateur » (`/aide`, `web/src/pages/HelpPage.tsx`, `nav.ts`, route dans `App.tsx`) pour salarié, manager, rh, paie (admin passe partout). Tests : `menu.spec.ts`, `a11y.spec.ts`, `guide.spec.ts` (aide en salarié et manager).
- **Déployé en production** : https://soma-rh.vercel.app (`scripts/vercel-deploy.ps1`, deux déploiements, état READY). `.vercelignore` autorise désormais `docs/docs.json` et `docs/guide-utilisateur/` (le build les lit) ; le reste de `docs/` reste exclu. Penser à déclarer l'adresse dans Supabase (Authentication > URL Configuration).
- **Campagne 2** (cas non testés) : verts = congés maladie, maternité, permission exceptionnelle, absence non payée ; présences avec heures supplémentaires, report en variables, planning ; variables du mois ; demande de profil traitée par la RH ; embauche en apprentissage ; ajout à la simulation de réorganisation. Guide passé à **28 pages**.
- **RPR-18** (ORANGE, décision produit) : après approbation sans dotation, les soldes de ces congés deviennent négatifs. Question Q6 ajoutée dans `QUESTIONS_LEGALES_OUVERTES.md`.

## Reste à jouer (troisième passe, libellés d'écran à relever d'abord)
Vacations et heures de nuit (saisie) · saisie des versements de cotisations · ordres de virement et rapport de clôture · paiements par lot (BLOQUÉ, fonction absente) · ayants droit, documents, avenant, mutation · application effective d'une réorganisation · saisie des régularisations et des éléments récurrents · 7 fiches RPR `fixme` (03, 05, 07, 08, 11, 13, 15).

## Nouveau chantier (à instruire)
Assistant de création d'un salarié (wizard) : proposition dans `docs/propositions/PROPOSITION_ASSISTANT_CREATION_SALARIE.md`, sélection interactive des composants dans l'artefact lié à la conversation. Aucune ligne de code de l'application n'a encore été écrite pour ce chantier.

## Assistant de création d'un salarié — réalisé (branche `feat/assistant-creation-salarie`, non fusionnée, non déployée)
- Migration locale appliquée : `db/migrations/20261217090000_assistant_creation_salarie.sql` (+ retour arrière) : table `employee_document_receipts`, fonctions `create_employee_from_wizard` (atomique) et `simulate_net_for_draft` ; test SQL `tests/sql/assistant_creation_salarie.sql` vert.
- Interface : `web/src/components/EmployeeWizard.tsx`, règles `web/src/lib/employeeWizard.ts` (9 tests unitaires), choix du type de saisie sur `/salaries/nouveau`, `Modal` avec option `persistent`.
- Tests : `web/e2e/sim/60-assistant.sim.spec.ts` (4/4), accessibilité de la fenêtre, menu 12/12, guide 7/7 ; page du guide « Créer un salarié avec l'assistant » (29 pages).
- **Pour mettre en ligne** : appliquer la migration sur Supabase (`scripts/supabase-appliquer.ps1`), puis fusionner et déployer. Sans la migration, seule la saisie complète fonctionne en ligne.
