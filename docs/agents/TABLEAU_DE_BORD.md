# Tableau de bord des agents

Tenu par `soma-controle` (et `soma-doc`). Une ligne par lot. Dernière mise à jour : 2026-11-14.

| Lot | Agent | Session | Branche | État | Dernier avis | Fiche |
|---|---|---|---|---|---|---|
| audit-1114 | soma-controle | (session du 14/11, claude.ai) | — | Livré | Document maître et méthode produits | `docs/audit/DOCUMENT_MAITRE_SOMA_RH_2026-11-14.md` |
| agents-audit (versionnement) | soma-controle | soma-controle-agents-audit | `chore/agents-audit` | Commité (a2bde6d), non poussé | — | — |
| ROAD-06 doublons de migration | soma-base | `soma-base-road06` | `chore/road-06-doublons-migrations` | Ordre émis, **1er de la file soma-base** | — | `relais/2026-11-14_ROAD-06_ordre.md` |
| ROAD-01 sécurité en ligne (SEC-04) | soma-securite | `soma-securite-road01` | `chore/road-01-securite-en-ligne` | Ordre émis (lecture seule, parallélisable) | — | `relais/2026-11-14_ROAD-01_ordre.md` |
| ROAD-02 MFA admin et paie | soma-base, puis soma-codage | `soma-base-road02`, `soma-codage-road02` | `feat/road-02-mfa` | Ordre émis, après ROAD-06 | — | `relais/2026-11-14_ROAD-02_ordre.md` |
| ROAD-03 chiffrement RIB et identité | soma-base | `soma-base-road03` | `feat/road-03-chiffrement-rib` | Ordre émis, après ROAD-02 | — | `relais/2026-11-14_ROAD-03_ordre.md` |
| ROAD-04 sauvegarde chiffrée + restauration | soma-base | `soma-base-road04` | `feat/road-04-sauvegarde` | Ordre émis, après ROAD-03 | — | `relais/2026-11-14_ROAD-04_ordre.md` |
| ROAD-05 CI tests SQL + empreinte | soma-tests | `soma-tests-road05` | `chore/road-05-ci-sql-paie` | Ordre émis, après ROAD-06 ; empreinte **bloquée par DEC-03** | — | `relais/2026-11-14_ROAD-05_ordre.md` |
| ROAD-07 fusion et mise en ligne | soma-controle | `soma-controle-road07` | `main` (fusion) | Ordre émis, **bloqué par DEC-04** | — | `relais/2026-11-14_ROAD-07_ordre.md` |
| ROAD-08 multi-société : conception | soma-securite | `soma-securite-road08` | `docs/road-08-multi-societe` | Ordre émis (conception seule, DEC-01 non tranchée) | — | `relais/2026-11-14_ROAD-08_ordre.md` |

## File `soma-base` (une seule base partagée, jamais deux migrations en même temps)
ROAD-06 → ROAD-02 (partie SQL) → ROAD-03 → ROAD-04.

## Décisions attendues du propriétaire (document maître §7)
| ID | Décision | Bloque |
|---|---|---|
| DEC-01 | Multi-société en phase 1 ou 4 | Implémentation ROAD-21 (ROAD-08 reste en conception) |
| DEC-02 | Source des formats NDAMLI et DGID | ROAD-09 (phase 2) |
| DEC-03 | Nouvelle référence `verify-payroll` sur jeu fictif versionné | Volet empreinte de ROAD-05 |
| DEC-04 | Ordre de fusion et de mise en ligne des branches | ROAD-07 |
| DEC-05 | Hébergement des données (après avis juridique) | Choix d'hébergement, phase 1-2 |
| DEC-06 | Niveau de signature électronique | ROAD-16 (phase 3) |
