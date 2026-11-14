# SOMA-RH — Document maître : audit technique, benchmark et feuille de route révisée

**Date** : 14/11/2026 · **Méthode** : `docs/audit/METHODE_AUDIT_BENCHMARK_SOMA_RH.md` · **Destination** : source maîtresse du carnet NotebookLM / Gemini Notebook « logiciel HR ».
**Périmètre lu** : dépôt `C:\IT-Mozaic\soma-rh-main`, branche `feat/saisie-salarie-menu-apropos` (commit `148c3d4`), `db/baseline/schema_local.sql` + 151 migrations, `api/server.mjs`, `web/src`, `tests/`, `.github/workflows/ci.yml`, passations du 10 et du 12/11 ; carnet « logiciel HR » (questions `[AUDIT-SOMA-2026-11-14 Q1, Q2]`) ; web (sources datées en §9).
**Non fait dans cette passe** : exécution des tests (base locale non sollicitée), lecture ligne à ligne de `compute_salary_slip`, inspection du projet Supabase en ligne, test d'intrusion. Ces points sont listés en §8.

Légende des identifiants : `ARCH` architecture et code · `SEC` sécurité · `QA` tests et qualité · `OPS` exploitation · `GAP` fonctionnalité manquante · `ROAD` feuille de route · `DEC` décision attendue du propriétaire · `BENCH` constat de benchmark.

---

## 1. Synthèse exécutive et score de maturité

SOMA-RH a un **cœur de paie sénégalais solide et vérifié** (moteur PL/pgSQL déterministe, oracle indépendant, empreinte de non-régression, workflow de paie en 7 états avec approbation séparée, journal d'audit chaîné et immuable, RLS sur 100 % des tables). Les faiblesses sont ailleurs : **sorties légales au format officiel** (NDAMLI, DGID), **paiement** (lot, mobile money), **sécurité d'exploitation** (MFA absent, données bancaires en clair, sauvegardes manuelles) et **architecture mono-société** (rôles globaux, `company_id` non filtré).

| Domaine | Note /10 | Justification (preuves en §2) |
|---|---|---|
| Code et architecture | 7 | Schéma reconstruit par baseline + migrations, retour arrière pour toutes les migrations récentes, tests SQL (67), unitaires (9 fichiers), e2e (24 specs). Mais 9 horodatages de migration en double, CI sans tests SQL ni non-régression de paie |
| Sécurité | 6 | RLS sur 79/79 tables, 227 politiques, 85 mentions `security definer`, aucune sans `search_path` figé, aucun droit d'exécution accordé à `anon` dans la baseline, verrouillage par compte + adresse (RPR-03). Mais pas de MFA (option `TOTP_ENABLED` déclarée et jamais utilisée), RIB en clair, limite de débit en mémoire, en ligne l'authentification Supabase n'a pas le verrouillage maison |
| Multi-société | 2 | `companies` existe, `company_id` sur 9 tables sur 79, **aucune** politique RLS ne filtre par société, rôles globaux (`user_roles(user_id, role)`) |
| Paie | 8 | Moteur vérifié, prêts avec plafond paramétrable (RPR-08), prorata (RPR-09), solde de tout compte, certificat de travail, IFC intérim, verticales (gardiennage, intérim, HORECA, transport, nettoyage). Mais exports officiels non conformes à un format publié, paiement par lot bloqué, pas de calcul net → brut |
| Expérience utilisateur | 7 | Guide de 29 pages, aide pour tous les rôles, assistant de création de salarié, connexion par téléphone, tests d'accessibilité. Branches non fusionnées (assistant lots 1-2, menu) |
| Exploitation (DevOps, PRA) | 4 | Scripts `local-backup.ps1`, `supabase-backup.ps1`, `local-restore.ps1`, `replay-migrations.sh` ; aucune sauvegarde planifiée hors Supabase, aucun test de restauration périodique, pas de supervision |

---

## 1bis. Matrice des six piliers

| Pilier | Opérationnel (preuve) | Partiel | Manquant |
|---|---|---|---|
| 1. Espace personnel | Mon espace, mes bulletins, demandes, congés (`MySpacePage`, `MySlipsPage`, `RequestsPage`, `LeavesPage`) ; connexion par téléphone validée par l'admin (`20261213090000_connexion_telephone`) | Documents du salarié (`EmployeeDocumentsPage`) sans dépôt automatique ni durée de conservation | Signature électronique, coffre-fort scellé |
| 2. Management | Équipes, affectations, organigramme, circuit d'approbation des congés et délégations (`ManagerPage`, `OrganigrammePage`, `leave_approval_steps`, `approval_delegations`) | Évaluations, formation, recrutement : tables `evaluations`, `trainings`, `candidatures` (Dev09), écrans à vérifier | Entretiens annuels outillés, objectifs |
| 3. Administration du personnel | Fiche, assistant de création, pièces requises, contrats, sorties et indemnités, solde de tout compte, certificat de travail (`Dev06_solde_tout_compte`, `certificat_travail_art140`) | Visites médicales (catalogue de documents seulement) | **Discipline et sanctions** (aucune table) ; registre unique du personnel au format officiel |
| 4. Paie et rémunération | Moteur, variables, régularisations, prêts, saisies sur salaire (`garnishment_scale`), heures sup et équivalences (m5), journal comptable équilibré (`validate_journal_balance`), suivi des versements de cotisations | Exports IPRES/CSS et DGID : texte par salarié lu sur le bulletin calculé (`export_ipres_css`, migration `20261116090000`, `etat_dgid`), sans format NDAMLI ; ordres de virement (`payment_export`) sans règlement par lot | Format NDAMLI, format DGID, mobile money, net → brut, acompte de quinzaine dédié (à vérifier) |
| 5. Pilotage | Tableau de bord, pilotage, centre de conformité, anomalies de paie, rapport de clôture, simulation de réorganisation | Indicateurs de masse salariale et bilan social (à vérifier sur `ReportsPage`) | BI externe (Metabase prévu, non installé) |
| 6. Configuration et système | Paramètres légaux datés (`payroll_settings`, `tax_slabs`, `trimf_brackets`), 11 conventions et 254 catégories, rôles, journal d'audit chaîné, moteur de modules métiers (m0, m3) | Matricule paramétrable (RPR-14) | Multi-société, administration de plateforme, API publique et webhooks |

---

## 2. Matrice de diagnostic technique

| ID | Composant / fichier | Constat (preuve) | Risque | Remédiation exacte | Agent |
|---|---|---|---|---|---|
| ARCH-01 | `db/migrations/` | 9 horodatages en double : `20261104150000`, `20261104160000`, `20261104180000`, `20261107120000`, `20261204090000`, `20261206090000`, `20261207090000`, `20261208090000`, `20261217090000` (commande `ls db/migrations \| cut -c1-14 \| sort \| uniq -d`). L'ordre d'application entre deux fichiers de même préfixe dépend du nom | Haut | Ne pas renommer les fichiers déjà appliqués ; ajouter à `check-migrations.sh` une liste blanche figée des doublons historiques et **échouer** sur tout nouveau doublon ; vérifier l'ordre réel dans `replay-migrations.sh` pour `20261217090000` (assistant + saisie CNI, deux branches) | soma-base |
| ARCH-02 | `.github/workflows/ci.yml` | CI : scan PII, lint, build, tests unitaires, contrôle et rejeu des migrations. **Ni `tests/sql/`, ni `verify-payroll`** (`grep -c tests/sql scripts/replay-migrations.sh` = 0) | Haut | Dans le job `rebuild`, après le rejeu : exécuter chaque `tests/sql/*.sql` avec `ON_ERROR_STOP=1` sur un scénario de données chargé, puis le contrôle d'empreinte de paie sur un jeu fixe versionné (sans données personnelles) | soma-tests |
| ARCH-03 | Branches | `main` ne contient pas `feat/saisie-salarie-menu-apropos`, `feat/assistant-creation-lot2` ; la passation du 12/11 interdit de fusionner le lot 2 avant la migration en ligne | Moyen | Ordre : appliquer `20261217090000_assistant_creation_salarie` et `20261218090000` sur Supabase, puis fusionner, puis déployer (DEC-04) | soma-controle |
| ARCH-04 | `scripts/verify-payroll.ps1` | Référence enregistrée (26 bulletins) antérieure à la base simulée actuelle : la non-régression ne protège plus rien | Haut | Décision DEC-03 : figer une nouvelle référence sur un jeu de données de test versionné (fictif) et l'utiliser en CI | soma-base |
| ARCH-05 | `api/server.mjs` l.17-23 | Limite de débit et jetons de rafraîchissement aussi gardés **en mémoire** (`Map`) : remis à zéro au redémarrage, faux sur plusieurs instances | Moyen | Garder la table `refresh_tokens` comme seule source ; déplacer le compteur de débit en base (table non journalisée) ou Redis si plusieurs instances | soma-codage |
| SEC-01 | Authentification | Pas de double authentification : `totpEnabled` déclaré (`api/server.mjs` l.114) et jamais lu ailleurs ; rien côté Supabase | Critique (données de paie) | En ligne : Supabase Auth MFA (TOTP), exiger `aal2` pour admin et paie dans `has_role` ou dans une fonction `require_aal2()` appelée par les RPC sensibles. En local : implémenter TOTP dans la passerelle derrière l'option existante | soma-base + soma-codage |
| SEC-02 | Table `employees`, colonne `bank_account text` | Coordonnées bancaires en clair (idem numéro de pièce d'identité, à confirmer colonne par colonne) | Haut | Chiffrement applicatif par Supabase Vault / `pgcrypto` (`pgp_sym_encrypt`, clé hors base), vue de masquage (4 derniers caractères) pour les rôles non paie ; journal d'accès comme `employee_document_access_log` | soma-base |
| SEC-03 | Politiques `FOR SELECT USING (true)` | 26 tables de référence lisibles par tout utilisateur connecté, dont `salary_structures`, `salary_structure_components`, `companies`, `payroll_settings` | Moyen (mono-société) ; Critique en multi-société | Vérifier si `salary_structures` porte des montants individuels ; si oui, restreindre à rh/paie. En multi-société, toutes ces lectures deviennent filtrées par tenant (§3) | soma-securite → soma-base |
| SEC-04 | En ligne (Supabase) | Le verrouillage par compte + adresse et la limite de débit maison n'existent qu'en local ; en ligne, Supabase Auth seul. Passation : mot de passe de base exposé, URL du site à déclarer, protection contre les mots de passe compromis à activer | Haut | Vérifier et cocher : mot de passe réinitialisé, URL déclarée, « leaked password protection », limites Auth, conseillers Supabase (sécurité, performance) | soma-securite |
| SEC-05 | `audit_log` | Point fort : chaîne de hachage (`audit_log_chain`) et immuabilité (`audit_log_immutable`). Lecture admin + rh | Bas | Ajouter une vérification périodique de la chaîne et une copie hors base (export signé) | soma-base |
| SEC-06 | Fonctions `security definer` | 85 mentions, toutes avec `search_path` figé, aucune accordée à `anon` dans la baseline. Trois régressions passées (D-013, D-014, D-021) | Moyen | Test SQL automatique en CI : aucune fonction `public` exécutable par `anon` ; chaque `security definer` commence par un contrôle de rôle | soma-tests |
| OPS-01 | Sauvegardes | Scripts manuels ; aucune planification ni copie chiffrée hors site documentée ; aucune restauration testée périodiquement | Haut | Sauvegarde quotidienne chiffrée (`pg_dump` + `age`/`gpg`) vers un second stockage, conservation 30 jours / 12 mois ; restauration testée chaque mois dans une base jetable, résultat journalisé | soma-base + propriétaire |
| OPS-02 | Supervision | Pas de page d'état ni d'alerte d'erreur côté front ou passerelle | Moyen | Journal d'erreurs (Sentry ou équivalent auto-hébergé) et alerte sur échec de clôture de paie | soma-codage |
| QA-01 | `scripts/test-sql.ps1` | 14 échecs au 12/11, surtout données de scénario absentes (passation) | Moyen | Scénario de données de test chargeable avant les tests SQL ; séparer tests de structure et tests de scénario | soma-tests |

---

## 3. Architecture cible : multi-société, sécurité, sauvegardes

### 3.1 Multi-société (conditionnée à DEC-01)

**Conflit à trancher.** Le méga-prompt classe le multi-société en urgence ; le projet a acté « une seule entreprise » et verrouillé le multi-tenant en phase 5 jusqu'à la décision de vendre (`GAP_ANALYSIS_NEXTGEN` §4, phase 5B, conflit X1). Ce document instruit la cible, il ne la déclenche pas.

Modèle recommandé (reprend `GAP_ANALYSIS` 5B et le carnet, sans OPA) :

```
tenants(id, nom, statut)                         -- un client ou un cabinet de paie
companies(id, tenant_id, ninea, rccm, convention, …)      -- entité juridique (existe : ajouter tenant_id)
establishments(id, company_id, nom, adresse)      -- site, agence
memberships(user_id, tenant_id, company_id NULL = toutes, role, valid_from, valid_to)
```

- `has_company_role(p_company uuid, p_roles text[])` remplace `has_role` dans les politiques des tables métier.
- Politique **restrictive** sur chaque table métier : `as restrictive for all using (company_id = any(app.my_company_ids()))`, en plus des politiques de rôle.
- `company_id NOT NULL` sur toutes les tables métier (aujourd'hui 9 sur 79), inclus dans les index et contraintes d'unicité (matricule unique **par société**).
- Référentiels légaux (barèmes IR, IPRES, CSS) : globaux en lecture ; paramètres d'entreprise (structures, primes, conventions appliquées) par société.
- Toutes les RPC qui reçoivent un identifiant contrôlent l'appartenance de la ligne au périmètre de l'appelant (protection IDOR).
- Salarié muté entre filiales : nouveau contrat dans la société cible, lien `person_id` commun pour l'historique ; consolidation groupe par vues filtrées.
- **Test d'étanchéité obligatoire avant tout client** : deux tenants, deux jetons, aucune ligne de A visible ni modifiable par B, vues et RPC comprises.
- Écarté : OPA / Rego, schéma par client, Aurora, Kafka, Kubernetes (proposés par le carnet, déjà reportés par `GAP_ANALYSIS` §1 ; disproportionnés pour la taille actuelle). Schéma séparé seulement si un gros compte l'exige.

### 3.2 Chiffrement, masquage, authentification

| Élément | Cible |
|---|---|
| RIB, numéro de pièce d'identité | Chiffrés en colonne (Vault/`pgcrypto`), clé hors base, déchiffrement par fonction réservée à paie/admin, accès journalisé |
| Affichage | Masquage partiel pour manager et rh hors paie |
| MFA | Obligatoire pour admin et paie (Supabase `aal2`, TOTP passerelle) ; facultatif pour les autres |
| Conservation | Bulletins et registres : durée **à confirmer** (le carnet cite 10 ans, CGI art. 637, et 11 ans pour les retenues à la source, art. 163, d'après un CGI annoté 2023 : non vérifié). Hébergement des données fiscales au Sénégal (art. 640 cité par le carnet) : **à confirmer avec un juriste**, impact direct sur le choix Supabase eu-west-1 (DEC-05) |
| Données personnelles | Déclaration à la CDP, registre des traitements, contrat de sous-traitance avec l'hébergeur (à faire, `GAP_ANALYSIS` 5E) |

### 3.3 Sauvegardes et reprise

| Objectif | Aujourd'hui | Cible réaliste |
|---|---|---|
| Perte de données maximale (RPO) | Dernière sauvegarde manuelle | 24 h tout de suite (sauvegarde quotidienne) ; 1 h ou moins avec la restauration à un instant donné de Supabase si le plan la propose (à vérifier) |
| Durée d'interruption (RTO) | Non mesurée | 4 h, mesurée par un test de restauration mensuel |
| Règle 3-2-1 | Non | 3 copies, 2 supports, 1 hors site, chiffrées |
| Coupures locales (électricité, réseau) | Version locale Docker | Garder le mode local comme poste de secours : restauration de la dernière sauvegarde en ligne sur la machine locale, procédure écrite |

Le carnet propose un RPO < 1 min et un RTO < 30 min (réplication Aurora, Kubernetes) : écarté, coût sans rapport avec le besoin ; les textes sénégalais cités n'imposent pas de chiffre (le carnet le dit lui-même).

---

## 4. Tableau comparatif mondial

Sources : carnet « logiciel HR » (Q1, 14/11/2026), `docs/comparatif/fiches-concurrents/`, `ANALYSE_SAGE_PAIE_RH_VS_SOMA_RH.md`, web (§7). « ✓ » = attesté par une source ; « ? » = non couvert par les sources ; pour SOMA-RH, preuve dans le dépôt.

| Brique | SOMA-RH | Open source (Frappe HR, Odoo, Horilla) | Propriétaires (Sage, Silae, PayFit, Workday) | Locaux (SunuPayRH, Popay) | Écart |
|---|---|---|---|---|---|
| Moteur de règles paramétrable | ✓ tables datées + PL/pgSQL ; rubriques non éditables par l'utilisateur | ✓ formules (Frappe), composantes (Horilla) | ✓ rubriques et constantes (Sage) ; Silae 800+ conventions (France) | ✓ moteur propriétaire (Popay) | Moyen : éditeur de rubriques sans code (GAP-021) |
| Exports NDAMLI (IPRES/CSS) | Fichier simplifié | Senedoo (Odoo) d'après le carnet | ? | ✓ Popay, SunuPayRH | **Fort** (GAP-001) |
| Exports DGID (IR, TRIMF, CFCE) | État simplifié | Senedoo | ? | ✓ | **Fort** (GAP-002) |
| Écritures comptables SYSCOHADA | ✓ journal équilibré | ✓ Odoo | ✓ Sage (OD de paie) | ? | Faible : formats d'import cibles (GAP-016) |
| Simulateur net → brut, coût employeur | Brut → net seulement | Senedoo | ? | ✓ SunuPayRH | Fort (GAP-003) |
| Prêts, acomptes | Prêts ✓, plafond paramétrable | ✓ Frappe, Horilla | ✓ Sage | ✓ | Faible : acompte de quinzaine (GAP-006) |
| Paiement par lot, mobile money | Ordres de virement ; lot bloqué ; Wave/OM non | ? | Sage : libellés mobile money | AfricaPaieRH, Weplanify (carnet) | Fort (GAP-004, GAP-005) |
| Coffre-fort salarié | Documents du salarié | Horilla | ✓ Workday ; Silae (dépôt auto des bulletins) | ✓ Popay Docs | Moyen (GAP-010) |
| Signature électronique | Non | Horilla (lettres d'offre) | Workday | Popay (émargement registre) | Moyen (GAP-011) |
| Multi-société | Non | ✓ | ✓ ; Silae multi-dossiers pour cabinets | ✓ Popay | Fort si vente (GAP-014) |
| API et webhooks | Non | ✓ | ✓ Workday | ✓ Popay | Moyen (GAP-012) |
| Recrutement (ATS) | Tables seulement | ✓ Horilla, Frappe | ✓ Workday, SAP | ✓ Popay | Faible (GAP-017) |
| OCR (CNI, RIB) | Non | Parsing de CV seulement (Horilla) | ? | ? | Faible ; absent des sources (GAP-018) |
| Discipline / sanctions | Non | ? | ? | ? (dossier du personnel en 5 sous-dossiers selon APPM) | Moyen (GAP-013) |
| Contrôles avant transmission | Contrôles avant revue (RPR-01, RPR-12), centre de conformité | ? | ✓ Silae (contrôles de cohérence dès le calcul) | ? | Faible : rapport de contrôle pré-déclaration (GAP-019) |

**BENCH-01** : Silae et PayFit sont **absents du carnet** ; les éléments retenus viennent de `payfit-lucca-silae.mdx` et du web. Leurs obligations françaises (DSN, conventions) ne s'appliquent pas au Sénégal ; ce qui est transposable : contrôles avant transmission, multi-dossiers pour cabinets, dépôt automatique des bulletins dans le coffre.
**BENCH-02** : les chiffres légaux cités par le carnet (abattement 30 % plafonné, barème IR, plafonds IPRES 432 000 / 1 296 000, CSS 63 000, CFCE 3 %) correspondent aux valeurs déjà en base d'après `AUDIT_SAAS_BENCHMARK.md` ; ils restent soumis à la règle du projet (source officielle datée).
**BENCH-03** : NDAMLI est le système commun IPRES-CSS de déclaration et de paiement des cotisations (presse 2025-2026). Le format de fichier attendu n'est dans aucune source consultée : il faut l'obtenir auprès de l'IPRES/CSS ou d'un utilisateur du portail (DEC-02).

---

## 5. Backlog des éléments manquants (différentiel)

| ID | Fonctionnalité | Inspiration | Impact Sénégal / UEMOA | Dépendances techniques | Priorité |
|---|---|---|---|---|---|
| GAP-001 | Export des cotisations au format NDAMLI (IPRES + CSS), mensuel ou trimestriel | Popay, SunuPayRH | Obligation légale, pénalités de retard | Spécification officielle du format (DEC-02) ; `export_ipres_css` à faire évoluer | P2 |
| GAP-002 | États DGID (IR, TRIMF, CFCE) au format officiel | Popay, Senedoo | Obligation fiscale | Format officiel ; `etat_dgid` | P2 |
| GAP-003 | Simulateur net → brut et coût employeur avant embauche | SunuPayRH, Senedoo, Weplanify | Salaires souvent négociés en net | Inversion de `simulate_net_for_draft` par recherche numérique, sans changer le moteur | P2 |
| GAP-004 | Règlement par lot (virement, chèque, espèces) | Proposition interne `PROPOSITION_PAIEMENTS_INDIVIDUELS.md` | Clôture de paie complète | Décision 4 du propriétaire (en attente) ; `salary_payments`, `payment_export` | P2 |
| GAP-005 | Fichier de paiement mobile money (Wave, Orange Money) | AfricaPaieRH, Weplanify | Inclusion financière, journaliers | GAP-004 ; formats des opérateurs | P3 |
| GAP-006 | Acompte de quinzaine automatique | Sage, SunuPayRH | Pratique courante | `additional_salaries` ou objet dédié ; vérifier l'existant | P2 |
| GAP-007 | Double authentification admin et paie | Carnet (rapports Deep Research), `GAP_ANALYSIS` 5E | Protection des données de paie | SEC-01 | **P1** |
| GAP-008 | Chiffrement et masquage des RIB et pièces d'identité | Carnet | Loi sur les données personnelles | SEC-02 | **P1** |
| GAP-009 | Sauvegarde automatisée chiffrée + restauration testée | Workday (sauvegardes hors site), Horilla | Continuité de la paie | OPS-01 | **P1** |
| GAP-010 | Coffre-fort : dépôt automatique des bulletins validés, scellement, durée de conservation | Popay Docs, Silae | Preuve en cas de contrôle | Durée légale à confirmer ; stockage objet | P3 |
| GAP-011 | Signature électronique (émargement du registre, contrats, avenants) | Popay, Horilla | Valeur probante | Niveau de signature à décider (DEC-06) | P3 |
| GAP-012 | API publique documentée et webhooks | Workday, Horilla, Odoo | Pointeuses, comptabilité, banques | PostgREST existe ; contrat d'API stable, clés par client | P4 |
| GAP-013 | Dossier disciplinaire (avertissements, sanctions, procédure) | APPM (5 sous-dossiers) | Code du travail | Nouvelle table + RLS stricte rh | P2 |
| GAP-014 | Multi-société / cabinet de paie | Sage, Silae, Odoo, Popay | Groupes, fiduciaires | §3.1 ; DEC-01 | P4 (P1 si vente décidée) |
| GAP-015 | Registre unique du personnel / DISA au format officiel | Sage, KayFay (`AUDIT_SAAS_BENCHMARK`) | Obligation | Format officiel | P2 |
| GAP-016 | Exports vers Sage, Odoo, Excel SYSCOHADA | Sage (OD de paie), Odoo | Comptables | `export_payroll_journal` | P3 |
| GAP-017 | Recrutement : écrans sur les tables existantes | Horilla, Frappe | Moyen | `candidatures`, `job_postulations` | P4 |
| GAP-018 | OCR des pièces (CNI, RIB) à la création | Aucun éditeur dans les sources | Faible | Service externe, consentement | P4 |
| GAP-019 | Rapport de contrôle avant déclaration | Silae | Moins de rejets | GAP-001/002 | P3 |
| GAP-020 | Module école privée (verticale annoncée, aucune migration trouvée) | — | Selon la cible commerciale | Moteur de modules m0/m3 | À décider |
| GAP-021 | Éditeur de rubriques de paie sans code | Sage | Paramétrage par client | `salary_components` ; tests par client | P4 |

---

## 6. Feuille de route révisée (4 phases)

Chaque lot a un agent responsable (configuration `.claude/agents/`, guide `docs/agents/README.md`) et une condition de passage contrôlée par `soma-controle`.

### Phase 1 — Urgence : sécurité, sauvegardes, stabilisation (≈ 3 semaines)
| ID | Lot | Agent | Condition de passage |
|---|---|---|---|
| ROAD-01 | Contrôles sécurité en ligne (SEC-04) | soma-securite | Les 5 points cochés et prouvés |
| ROAD-02 | MFA admin et paie (GAP-007) | soma-base, soma-codage | Connexion admin impossible sans second facteur en ligne et en local |
| ROAD-03 | Chiffrement/masquage RIB et pièce d'identité (GAP-008) | soma-base | Test SQL : un rôle rh non paie ne lit jamais le RIB complet |
| ROAD-04 | Sauvegarde quotidienne chiffrée + restauration mensuelle (GAP-009) | soma-base | Une restauration complète réussie et chronométrée |
| ROAD-05 | CI : tests SQL + empreinte de paie (ARCH-02, ARCH-04, SEC-06) | soma-tests | CI rouge si un test SQL ou l'empreinte échoue |
| ROAD-06 | Doublons de migration (ARCH-01) | soma-base | `check-migrations.sh` échoue sur tout nouveau doublon |
| ROAD-07 | Fusion et mise en ligne des branches en attente (ARCH-03) | soma-controle | Migrations appliquées sur Supabase avant fusion ; site vérifié |
| ROAD-08 | Multi-société : **conception et test d'étanchéité écrit**, pas d'implémentation | soma-securite | Document validé ; implémentation selon DEC-01 |

### Phase 2 — Complétude du cœur RH et paie (≈ 6 semaines)
ROAD-09 exports NDAMLI et DGID (GAP-001, 002, 015, après DEC-02) · ROAD-10 règlement par lot (GAP-004, après décision 4) · ROAD-11 net → brut (GAP-003) · ROAD-12 acompte de quinzaine (GAP-006) · ROAD-13 dossier disciplinaire (GAP-013) · ROAD-14 rejouer les parcours non joués (passation du 12/11 : vacations, nuit, versements, virements, ayants droit, avenants, mutations) — agents soma-base, soma-codage, soma-tests, soma-design.

### Phase 3 — Différenciation et verticales (≈ 6 semaines)
ROAD-15 coffre-fort avec dépôt automatique (GAP-010) · ROAD-16 signature électronique (GAP-011, après DEC-06) · ROAD-17 mobile money (GAP-005) · ROAD-18 contrôle avant déclaration (GAP-019) · ROAD-19 exports comptables (GAP-016) · ROAD-20 verticales : consolider intérim, gardiennage, HORECA, transport, nettoyage ; décider l'école privée (GAP-020).

### Phase 4 — Échelle et écosystème (après décision de vendre)
ROAD-21 multi-société implémenté + test d'étanchéité vert (GAP-014) · ROAD-22 API publique et webhooks (GAP-012) · ROAD-23 BI (Metabase) · ROAD-24 éditeur de rubriques (GAP-021) · ROAD-25 recrutement, OCR (GAP-017, 018). Conditions de passage de `GAP_ANALYSIS` phase 5 (5A à 5H) reprises telles quelles.

---

## 7. Décisions attendues du propriétaire

| ID | Décision | Pourquoi maintenant |
|---|---|---|
| DEC-01 | Lever ou maintenir « une seule entreprise » (multi-société en phase 1 ou 4) | Le méga-prompt et la décision écrite se contredisent |
| DEC-02 | Qui fournit les formats officiels NDAMLI et DGID (comptable, IPRES/CSS, client) | Bloque GAP-001, 002, 015 |
| DEC-03 | Autoriser une nouvelle référence de `verify-payroll` sur un jeu fictif versionné | La non-régression ne protège plus rien |
| DEC-04 | Ordre de fusion et de mise en ligne des branches en attente | Le lot 2 de l'assistant casse en ligne sans sa migration |
| DEC-05 | Hébergement des données (Supabase eu-west-1 ou Sénégal) après avis juridique | Article 640 du CGI cité par le carnet, non vérifié |
| DEC-06 | Niveau de signature électronique visé | Conditionne GAP-011 |

## 8. Ce qui reste à inspecter (prochaine passe)
1. `compute_salary_slip` ligne à ligne et la migration `20261104180000_maj_compute_salary_slip.sql` (risque de troncature signalé le 10/11).
2. Le projet Supabase en ligne : conseillers sécurité et performance, configuration Auth, plan de sauvegarde (lecture seule).
3. Les écrans `ReportsPage`, `ModulesPage` (évaluations, formation, recrutement) pour confirmer « partiel ».
4. Exécution réelle : `test-sql.ps1`, `verify-payroll.ps1`, Playwright, sur un scénario chargé.
5. Carnet : question Q3 sur les formats NDAMLI et DGID.

## 9. Sources
- Carnet Gemini Notebook « logiciel HR » (78 sources), questions du 14/11/2026 ; sources citées : rapports Deep Research « Architecture et Stratégie Produit d'un SIRH SaaS Enterprise Nouvelle Génération », « Étude d'Architecture Logicielle et de Conformité Réglementaire … pour SOMA-RH au Sénégal », « Spécifications Techniques SIRH … UEMOA / OHADA » ; Popay, SunuPayRH, Sage Paie & RH (vidéos), Horilla, Weplanify, KeeMatch, APPM, CGI annoté 2023 (Kof Experts).
- Web, consulté le 14/11/2026 : NDAMLI, guichet commun IPRES-CSS (allAfrica, 21/05/2026 ; osiris.sn, 11/07/2025) ; Silae (hackceleration.com, lafabriquedunet.fr 31/03/2026, bulletinspaie.com).
- Dépôt : documents cités dans chaque ligne.
