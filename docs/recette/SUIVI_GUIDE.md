# Suivi — reconstruction du guide utilisateur (branche `docs/guide-utilisateur-complet`)

Mis à jour et commité à la fin de chaque étape. Les miniatures (120 px) renvoient aux captures réelles de `docs/guide-utilisateur/captures/`.

| Étape | Statut | Tests joués (pass/fail) | Pages écrites | Captures | Dernier commit |
|---|---|---|---|---|---|
| A. Environnement et base | fait | — | 0 | — | voir `git log` |
| B. Helper de capture | à faire | | | | |
| C. Rejeu complet (blocs A à J) | à faire | | | | |
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
