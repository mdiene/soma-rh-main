# Méthode — Audit technique, benchmark et mise à jour de la feuille de route (SOMA-RH)

Version du 14/11/2026. Remplace l'usage direct du « méga-prompt » reçu le même jour : ce document en garde l'objectif et le plan de livrable, mais l'adapte au dépôt réel et à l'historique du projet. Résultat de la première exécution : `docs/audit/DOCUMENT_MAITRE_SOMA_RH_2026-11-14.md`.

## 1. Ce qui change par rapport au méga-prompt

| Le méga-prompt suppose | Le projet est | Conséquence pour la méthode |
|---|---|---|
| Schémas Prisma, middlewares, routes API classiques | PostgreSQL + PL/pgSQL (`compute_salary_slip`), RLS, PostgREST ; passerelle `api/server.mjs` en local ; Supabase Auth + Vercel en ligne | L'audit lit `db/baseline/schema_local.sql` + les migrations postérieures à la coupure, les politiques RLS et les fonctions `security definer` |
| Dépôt `mdiene/soma-rh` | Dépôt actif `mdiene/soma-rh-main`, `C:\IT-Mozaic\soma-rh-main` | Tous les chemins partent de ce dossier |
| Rien n'a été fait | Benchmarks et écarts déjà produits : `docs/comparatif/`, `ANALYSE_SAGE_PAIE_RH_VS_SOMA_RH.md`, `GAP_ANALYSIS_NEXTGEN_SOMA_RH.md`, `AUDIT_SAAS_BENCHMARK.md`, `AUDIT_COMMERCIALISATION_SOMA_RH.md` | On produit un **différentiel** : ce qui a changé depuis, ce qui manque encore, avec renvoi aux documents existants. On ne réécrit pas |
| Multi-société en « urgence critique » (phase 1) | Décision écrite : « une seule entreprise » ; multi-tenant verrouillé en phase 5 jusqu'à décision explicite de vendre (`GAP_ANALYSIS` §4, conflit X1) | Le multi-société est **instruit** (architecture cible, coût, test d'étanchéité) mais reste conditionné à une décision du propriétaire. Signalé comme conflit, pas tranché |
| Chiffres légaux à prendre dans les sources | Règle du projet : aucun taux ni plafond codé sans source officielle datée et décision du propriétaire (`REGISTRE_RISQUES` K2) | Tout chiffre issu du carnet ou du web est marqué **« à confirmer »** |
| Gemini sur le web pour les phases 2 et 3 | Le carnet Gemini Notebook « logiciel HR » (78 sources) contient déjà trois rapports Deep Research, dont un sur SOMA-RH | Le carnet est interrogé en premier, le web complète ce qu'il ne couvre pas (ex. Silae, PayFit absents du carnet) |

## 2. Étapes

| # | Étape | Agent | Entrées | Sortie |
|---|---|---|---|---|
| 0 | Cadrage : relire la passation la plus récente, les décisions du propriétaire, les documents d'audit existants | `soma-controle` | `docs/passation/`, `REGISTRE_RISQUES_DECISIONS`, `GAP_ANALYSIS`, `docs/comparatif/` | Liste de ce qui est déjà couvert |
| 1 | Audit du code et de la base (lecture seule, preuves chiffrées) | `soma-securite` + `soma-base` | `db/baseline`, `db/migrations`, `api/server.mjs`, `web/src`, `tests/`, `.github/workflows` | Section 2 du document maître (`ARCH-`, `SEC-`, `QA-`) |
| 2 | Matrice des 6 piliers (opérationnel / partiel / manquant) | `soma-controle` | pages `web/src/pages`, tables, fonctions, recette | Section 1bis |
| 3 | Interrogation du carnet « logiciel HR » | `soma-recherche` | questions préfixées `[AUDIT-SOMA-<date> Qn]`, lecture seule | Réponses citées par titre de source |
| 4 | Compléments web (sources datées) | `soma-recherche` | sites éditeurs, organismes, presse | Section 4 |
| 5 | Synthèse : scores, architecture cible, backlog `GAP-xxx`, feuille de route en 4 phases | `soma-controle` | étapes 1 à 4 | `DOCUMENT_MAITRE_SOMA_RH_<date>.md` |
| 6 | Contrôle croisé : chaque fait relié à un fichier, une commande ou une source | `soma-controle` | document maître | Avis GO / à corriger |
| 7 | Import dans le carnet NotebookLM (ajout d'une source, rien d'autre) | propriétaire | document maître | Source « Document maître SOMA-RH <date> » |

## 3. Questions types pour le carnet (étape 3)

- **Q1 Fonctionnalités** : liste des fonctionnalités et automatismes de Sage Paie & RH, Silae, PayFit, Frappe HR, Odoo, Horilla, SunuPayRH, Popay, Workday/SAP qu'un SaaS de paie sénégalais doit avoir, en tableau `fonctionnalité | éditeurs | source exacte | importance Sénégal`, en disant ce qui est absent des sources.
- **Q2 Architecture** : modèle multi-société / groupe / cabinet, chiffrement, MFA, conservation légale, sauvegardes (RPO/RTO), en partant de l'état réel (`user_roles` global, `company_id` sans RLS).
- **Q3 (prochaine passe)** : formats officiels des déclarations NDAMLI et DGID, avec la source exacte de chaque format.

## 4. Règles de rédaction du document maître

- Identifiants stables : `ARCH-xx`, `SEC-xx`, `QA-xx`, `GAP-xxx`, `ROAD-xx`, `BENCH-xx`, `DEC-xx` (décision attendue).
- Chaque constat : preuve (fichier, ligne, commande ou source), gravité, remédiation exacte, agent responsable.
- Séparer « source » et « analyse ». Les recommandations du carnet qui contredisent une décision du projet (ex. Kafka, OPA, Kubernetes, déjà reportés au §1 de `GAP_ANALYSIS`) sont citées et **écartées avec la raison**.
- Aucune donnée personnelle, aucun secret.

## 5. Relancer la méthode

```powershell
.\scripts\agents.ps1 lancer controle audit-<date> -Consigne "Applique docs/audit/METHODE_AUDIT_BENCHMARK_SOMA_RH.md en partant du dernier document maître ; produis le différentiel."
```
