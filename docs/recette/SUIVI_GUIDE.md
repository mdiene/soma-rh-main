# Suivi — reconstruction du guide utilisateur (branche `docs/guide-utilisateur-complet`)

Mis à jour et commité à la fin de chaque étape. Les miniatures (120 px) renvoient aux captures réelles de `docs/guide-utilisateur/captures/`.

| Étape | Statut | Tests joués (pass/fail) | Pages écrites | Captures | Dernier commit |
|---|---|---|---|---|---|
| A. Environnement et base | fait | — | 0 | — | voir `git log` |
| B. Helper de capture | fait | 1 pass (`capture.mask.test.mjs`) ; `npm run check` 0 erreur | 0 | — | voir `git log` |
| C. Rejeu complet (blocs A à J) | en cours | 05-demarrer 1/1 ; 10-croissance (paliers 5-9) 5/5 pass | 0 | ![](../guide-utilisateur/captures/referentiels-emplois-liste.png){width=120} | voir `git log` |
| D. Matrices et dossier de reprise | à faire | | | | |
| E. Rédaction du guide | à faire | | | | |
| F. Vérifications | à faire | | | | |
| G. Clôture | à faire | | | | |

## Étape A — notes
- Branche `docs/guide-utilisateur-complet` créée depuis `fix/rpr-09-prorata` ; un premier commit isole l'onglet « Documentation utilisateur » (travail préexistant non commité).
- Sauvegarde : `backups/soma-rh-20261112-153339.dump` (base de 200 salariés, avant remise à zéro).
- Base remise à zéro (décision du propriétaire) : 0 salarié, 1 compte (mdiene) ; 20 comptes `sim-*` recréés.
- **Outillage corrigé** : `tests/fixtures/sim/reset-zero.sql` refusait de s'exécuter (tables `employee_loan_caps`, `phone_access_accounts`, `phone_access_requests`, `phone_access_tokens` absentes de sa liste). Ajoutées ; aucune modification de l'application.
- **Constat** : `scripts/check-migrations.sh` sort en erreur (préfixes dupliqués hors liste blanche : 20261204090000, 20261206090000, 20261207090000, 20261208090000). Antérieur à cette campagne, non corrigé ici.
- Application sur http://localhost:5173 : répond 200 ; conteneurs api, postgres, postgrest actifs.

## Étape C — journal
### Bloc A · Emplois (palier 11)
<img src="../guide-utilisateur/captures/referentiels-emplois-vide.png" width="120"> <img src="../guide-utilisateur/captures/referentiels-emplois-ajouter.png" width="120"> <img src="../guide-utilisateur/captures/referentiels-emplois-liste.png" width="120">

Sur base remise à zéro, le référentiel « Emplois » est vide : 23 emplois créés par Paramètres › Référentiels RH (`05-demarrer.sim.spec.ts`). VERT.

### Paliers 5 à 9 (100 → 200 salariés) — VERT (5/5)
<img src="../guide-utilisateur/captures-sim/palier-5-liste-salaries.png" width="120"> <img src="../guide-utilisateur/captures-sim/palier-7-calcul.png" width="120"> <img src="../guide-utilisateur/captures-sim/palier-9-gouvernance.png" width="120">

- Base : 200 salariés, 200 affectations de structure.
- **ORANGE à confirmer (intermittent)** : sur la page d'un salarié neuf, la section « Structure salariale » n'apparaît parfois pas dans les 8 s (3 occurrences sur ~200 embauches), ou la page reste blanche. Cause non établie (lenteur du serveur de développement ou chargement paresseux). Délai du test porté à 20 s ; aucune correction de l'application.
- Problèmes de test corrigés (sans effet sur l'application) : sélecteur « Enregistrer » ambigu avec « Enregistrer la fiche » ; emplois à recréer après remise à zéro.
