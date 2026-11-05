# Audit SOMA-RH : expérience utilisateur, code, conformité Sénégal (5 novembre 2026)

Périmètre : dépôt `SOMA-RH-local` tel qu'il est le 2026-11-05. Les constats « base » ont été vérifiés dans la base locale, les constats « code » dans le dépôt. La colonne « Marché » s'appuie sur les analyses déjà présentes dans `docs/comparatif/` et `docs/ANALYSE_SAGE_PAIE_RH_VS_SOMA_RH.md` ; **KayFay, SunuPayRH, Popay, Workday et OrangeHRM n'ont pas été re-vérifiés dans cet audit** (aucune source datée consultée) : à traiter dans la phase 13 de la campagne QA.

## Écarts entre la demande et le projet

| La demande suppose | Le projet est | Conséquence |
|---|---|---|
| Next.js, Supabase | React + Vite, PostgreSQL local dans Docker (règle du projet : rester en local) | Aucune migration de pile ; les correctifs suivent les conventions du dépôt |
| Tables à créer : `legal_payroll_rates`, `company_settings`, `salary_grids` | Elles existent sous d'autres noms : `payroll_settings` (versionnée par `effective_from`), `companies`, `employee_grades` (par convention collective et date d'effet) | **Aucune table en double créée** ; `companies` est complétée |
| Moteur en « pure functions » séparé de la base | Moteur en PL/pgSQL (`compute_salary_slip`, déterministe, `STABLE`), vérifié par un oracle indépendant et une empreinte de non-régression | Pas de réécriture : le moteur est testé et sa séparation avec l'interface est déjà nette |
| Heures supplémentaires : +15 %, +40 %, +60 %, +100 % | Ces paliers existent **et** une décision du propriétaire du 2026-11-04 (D-012) ajoute 150 % à partir de la 49e heure | Non modifié : conflit à arbitrer par le propriétaire |

## Matrice d'évaluation

| Module | État actuel | Marché | Conformité Sénégal | Action | Fichiers |
|---|---|---|---|---|---|
| Moteur de paie | Déterministe, 939 salariés comparés à un oracle indépendant, empreinte de non-régression | Sage : moteur fermé ; Frappe HR : formules Python par structure | Conforme sauf D-006 (IPRES cadres sur toute la rémunération au lieu de la tranche), D-008 (stagiaires, apprentis) | Décision du propriétaire sur D-006 et D-008 | `db/migrations/*payroll_engine*`, `tests/oracle/` |
| SMIG | `smig_hourly` versionné (370,526) ; valeur à confirmer (D-003) ; SMAG absent | Sage : tables légales mises à jour par l'éditeur | À confirmer | **Fait** : alerte « salaire sous le SMIG paramétré » (fonction + saisie) ; SMAG et confirmation de la valeur restent à faire | `db/migrations/20261105150000_*`, `web/src/lib/payrollGuards.ts` |
| Heures supplémentaires | Paliers 15/40/60/100 % conservés + 150 % dès la 49e heure (D-012) | Frappe/Odoo : règles configurables | Conflit entre la décision D-012 et le barème demandé | Arbitrage du propriétaire, pas de changement | `20261104180000_maj_compute_salary_slip.sql` |
| Primes obligatoires | Transport en paramètre, prime d'ancienneté avec seuil `seniority_min_years` ; barème progressif de 1 % à 25 % **non vérifié** dans cet audit | Sage : prime d'ancienneté paramétrée par convention | À vérifier avec l'oracle | À vérifier (phase 4) | `payroll_settings` |
| Cotisations et plafonds | En base : IPRES RG 432 000, IPRES cadres 1 296 000, CSS 63 000, CFCE 3 %, tous datés | Identique | Valeurs conformes à la demande ; taux d'accident du travail unique (D-004) | **Fait** : contrôle de saisie (taux en fraction, plafonds positifs, cadres > régime général, baisse signalée) | `payrollGuards.ts`, `SettingsPage.tsx` |
| IR et TRIMF | Barème et TRIMF en tables datées ; base arrondie corrigée (D-007) ; quotient familial 1,5 par enfant (D-012) | Équivalent | Conforme d'après les tests | Aucune | `tax_slabs`, `ir_family_reductions`, `trimf_brackets` |
| Alertes juridiques | Avant : un compteur « contrats sous 60 jours » | Sage/Odoo : tableaux d'échéances | Fin de CDD, pièces : couverts maintenant. **Période d'essai et préavis : aucun champ en base** | **Fait** : `legal_alerts` (CDD échu ou à échéance, sous le SMIG, pièce expirée) affichée sur le tableau de bord. Essai et préavis à faire (nouvelle colonne de fin d'essai, règle de préavis) | `legal_alerts`, `LegalAlerts.tsx`, `DashboardPage.tsx` |
| Exports réglementaires | Livre de paie, journal comptable, IPRES/CSS et états DGID en mode fichier simplifié (Dev03, Dev04) | Sage/KayFay : DISA et fichiers d'organismes | **DISA et NDAMLI : format officiel non disponible dans le dépôt** ; registre unique du personnel absent | Non fait : exige les spécifications officielles | `export_ipres_css`, `etat_dgid` |
| Versionnage et immutabilité | Bulletins validés protégés (déclencheurs de clôture, instantané signé par empreinte) ; paramètres datés **mais l'écran écrasait la version en cours** | Frappe : documents soumis non modifiables | Conforme sur les bulletins ; écart sur les paramètres | **Fait** : « nouvelle version datée » (date postérieure), correction à date égale, refus d'une date antérieure | `SettingsPage.tsx`, `payrollGuards.ts` |
| Identité de la société | NINEA, RCCM seulement | Sage : fiche société complète | N° IPRES, N° CSS et convention appliquée manquaient | **Fait** : colonnes et formulaire | `companies`, `SettingsPage.tsx` |
| Grilles salariales | `employee_grades` : 254 catégories, 11 conventions, date d'effet | Équivalent | Conforme | Aucune table ajoutée (équivaut à `salary_grids`) | `employee_grades`, `collective_agreements` |
| Assistant de premier démarrage | Aucun parcours guidé : huit onglets de paramètres | Odoo/Frappe : assistant en étapes | — | Non fait : fonctionnalité à part entière (voir « Reste à faire ») | — |
| Sécurité et droits | RLS sur toutes les tables, séparation des tâches, campagne QA phases 0 à 7 (D-001 à D-021) | Équivalent | Conforme | Voir `docs/qa/` | `docs/qa/defects.mdx` |

## Ce qui a été fait dans cette passe

1. **Migration `20261105150000_societe_numeros_alertes_legales`** : numéros IPRES et CSS, convention collective de la société ; fonction `legal_alerts` (réservée aux rôles rh et paie, seuils lus dans `payroll_settings` à la date demandée). Test `tests/sql/alertes_legales.sql`.
2. **Garde-fous de saisie** (`web/src/lib/payrollGuards.ts`, 8 tests) : taux en fraction, plafonds positifs et cohérents, baisse signalée, salaire sous le SMIG, mode d'enregistrement d'un changement de taux.
3. **Écran « Taux et plafonds »** : date d'application, avertissements en clair, enregistrement bloqué sur erreur, création d'une version datée au lieu de l'écrasement.
4. **Fiche salarié** : avertissement si le salaire de base est sous le SMIG (hors prestataires).
5. **Tableau de bord** : section « Alertes réglementaires ».
6. **D-021** : une fonction d'une autre migration (`prevent_closed_period_data_mutation`) était exécutable par le rôle anonyme ; corrigé par `20261107120000_revoke_execute_anon_d49`. C'est la troisième fois (D-013, D-014, D-021) : toute migration qui crée une fonction doit finir par les deux lignes `revoke` / `grant`.

## Reste à faire (non fait, avec la raison)

| Sujet | Raison |
|---|---|
| Assistant de premier démarrage (société, grilles, organigramme, taux) | Nouvelle fonctionnalité de plusieurs écrans ; à cadrer (ordre des étapes, reprise, données minimales) |
| Période d'essai et préavis | Aucun champ en base : il faut d'abord définir les règles (durées par catégorie, renouvellement) avec une source datée |
| DISA, NDAMLI, registre unique du personnel | Formats officiels non disponibles dans le dépôt |
| SMAG, confirmation du SMIG (D-003), taux d'accident du travail par risque (D-004), IPRES cadres (D-006), stagiaires (D-008), heures supplémentaires (D-012) | Chiffres légaux : règle du projet, aucune modification sans source datée et décision du propriétaire |
| Benchmark KayFay, SunuPayRH, Popay, Workday, OrangeHRM | Sources à consulter (phase 13) |
| Citations d'articles du Code du travail (L.47, L.55…) | Non vérifiées : elles ne sont reprises dans aucun message de l'application tant qu'une source n'est pas consultée |
