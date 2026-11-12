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
