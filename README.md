# SOMA-RH — Gestion du personnel et de la paie

Application web de gestion RH et de paie de la **Société Minière Africaine (SOMA)**, construite à partir du
classeur Excel « GESTION DE LA PAIE DES CONGES » et sur le modèle fonctionnel de
[Frappe HR](https://github.com/frappe/hrms).

* **Frontend** : React 18 + Vite + TypeScript + Tailwind CSS + TanStack Query / Table + Lucide (`web/`)
* **Backend cible** : PostgreSQL 17 + PostgREST + authentification JWT (`db/`, `postgres/`, `docker-compose.yml`)
* **Moteur de paie** : fonctions PL/pgSQL qui reproduisent les formules Excel au centime près
  (25 bulletins d'août 2026 identiques, voir [docs/ANALYSE_EXCEL.md](docs/ANALYSE_EXCEL.md))

## Deux versions, un seul code

| | Locale | En ligne |
|---|---|---|
| Base de données | PostgreSQL 17 dans Docker | Supabase (projet `mzhdwdpesbggxtjxxgab`) |
| Authentification | conteneur `api` (compatible `/auth/v1`), inscription fermée | Supabase Auth |
| API de données | PostgREST (Docker) derrière la passerelle `api` | PostgREST de Supabase |
| Documents salariés | fichiers sur disque via `/api/v1/documents` | Supabase Storage (bucket privé `employee-documents`) |
| Miniatures de documents | image générée par la passerelle (`sharp`) | image elle-même (JPEG/PNG) ou type de fichier |
| Dossier PDF complet d'un salarié | oui | **non** (bouton masqué) |
| Lien privé d'un document | oui | **non** (bouton masqué) |
| Envoi d'e-mails | non (la file `email_outbox` n'est pas traitée) | non |
| Propriétaire des objets SQL | rôle `soma` | rôle `postgres` |
| Front | `npm run dev` (http://localhost:5173) | Vercel |
| Configuration du front | `web/.env.local` (modèle `web/.env.local.example`) | variables Vercel (modèle `web/.env.production.example`) |

Le front ne les distingue que par `VITE_API_URL`, `VITE_API_PUBLIC_KEY` et `VITE_DOCUMENTS_MODE` (`gateway` ou `supabase`).

## Lancer en local

```powershell
Copy-Item .env.docker.example .env        # puis renseigner POSTGRES_PASSWORD, JWT_SECRET, PGADMIN_* (jamais commité)
docker compose up -d postgres postgrest api
Copy-Item web\.env.local.example web\.env.local
cd web; npm ci; npm run dev
```

* Application : http://localhost:5173 ; passerelle/API : http://localhost:8000 ; PostgREST : http://localhost:3001 ; PostgreSQL : `localhost:5432` ; pgAdmin : http://localhost:5051 (`docker compose up -d pgadmin`).
* Nouvelle migration : la créer dans `db/migrations/`, l'appliquer (`docker exec -i soma-rh-local-postgres-1 psql -U soma -d soma_rh -v ON_ERROR_STOP=1 < fichier.sql`), recharger PostgREST (`notify pgrst, 'reload schema'`) et régénérer `web/src/lib/database.types.ts`.
* Contrôles : `cd web; npm run check; npm run build`, `scripts	est-sql.ps1`, `scriptserify-payroll.ps1` (nécessite `POSTGRES_PASSWORD` dans l'environnement ou `.env`).
* Création d'un compte local : inscription fermée par défaut ; voir `scripts\sim-create-users.ps1` / `qa-create-users.ps1`, puis **Paramètres › Accès › Me déclarer administrateur**.

## Mettre en ligne (Supabase + Vercel)

Les migrations ne se rejouent plus en entier (voir `db/baseline/README.md`) : une base neuve se construit avec la baseline puis les migrations postérieures à la coupure. `scripts/supabase-load.sh` le fait et remplace le rôle `soma` par `postgres`.

1. **Sauvegarde** de l'existant (facultatif mais recommandé) : `.\scripts\supabase-backup.ps1 -DbHost aws-1-eu-west-1.pooler.supabase.com -DbUser postgres.mzhdwdpesbggxtjxxgab`.
2. **Base** : `.\scripts\supabase-migrer.ps1 -Etape reset -Sauvegarde backups\<dossier>` — **destructif** (supprime puis recrée le schéma `public`, confirmation à taper). Le pooler IPv4 est utilisé ; le mot de passe de la base est saisi à l'écran, jamais écrit. `-Etape donnees` recharge ensuite les données d'une sauvegarde.
   Si le schéma est déjà à jour et qu'il ne manque qu'une migration, l'appliquer seule avec `psql` sur le pooler (en remplaçant `FOR ROLE soma` par `FOR ROLE postgres`).
3. **Stockage** : la migration `20261212090000_documents_supabase_storage.sql` crée le bucket privé `employee-documents` et ses politiques ; rien d'autre à faire dans Supabase.
4. **Vercel** : importer le dépôt (racine `./`, `vercel.json` fixe le build). Dans *Settings › Environment Variables* : `VITE_API_URL` = URL du projet (`https://mzhdwdpesbggxtjxxgab.supabase.co`), `VITE_API_PUBLIC_KEY` = clé publique *anon*, `VITE_DOCUMENTS_MODE` = `supabase`. Ne jamais mettre la clé `service_role` ici. `.vercelignore` exclut le dossier `api/` (passerelle Docker, pas une fonction Vercel).
5. **Supabase Auth** : *Authentication › URL Configuration* → adresse du site Vercel ; désactiver les inscriptions publiques (*Sign In / Providers › Allow new users to sign up*).
6. **Premier administrateur** : créer l'utilisateur dans *Authentication › Users › Add user* (e-mail + mot de passe, « Auto Confirm »), se connecter à l'application, puis **Paramètres › Accès › Me déclarer administrateur** (possible tant qu'aucun administrateur n'existe). Créer ensuite les autres comptes de la même façon et leur attribuer les rôles.

Chaque `git push` sur la branche de production redéploie le front. Les données personnelles (sauvegardes, `db/seed/`, `.env*`) sont exclues de Git.

## Modules

| Écran | Rôle | Feuille Excel d'origine |
|---|---|---|
| Tableau de bord | vue mensuelle (masse salariale, IPRES, CSS, CFCE, TRIMF, provisions, alertes) et vue annuelle ; « Synthèse annuelle » des traitements validés | TDB |
| Salariés | fiche complète, matricule attribué automatiquement (S0027…) et verrouillé, classification conventionnelle, structure salariale, solveur « net à simuler » | FICHE DE PERSONNEL |
| Congés | demandes, validation, attribution et soldes | — |
| Présences | grille journalière (un salarié par ligne, enregistrement groupé sans doublon) : heures travaillées, absence, maladie, HS par taux ; report dans les variables de paie | — |
| Mes bulletins | bulletins validés filtrés par salarié, matricule et période, regroupés par salarié ; impression et export | BULLETIN |
| Variables du mois | saisie en grille des heures, primes et retenues | élements de salaires (colonnes de saisie) |
| Traitements de paie | calcul par lot, contrôle, validation, impression de tous les bulletins | BULLETIN + macros VBA |
| Bulletin | maquette fidèle, cumuls période/année, montant en lettres, impression / PDF | BULLETIN |
| Simulateur net / brut | simulation sans enregistrement, recherche du sursalaire pour un net cible | macro Valeur_Cible |
| États et déclarations | livre de paie en 7 blocs avec cumuls annuels validés (TRIMF, IPRES RG/RC, provisions congé et précarité), cotisations, charges patronales, écritures comptables ; en-têtes figés, sous-totaux, contrôles de cohérence, export CSV, impression paysage | livre de paie, états, compta |
| Paramètres | rôles, taux et plafonds, barèmes IR/TRIMF, rubriques, grilles conventionnelles, société ; référentiels RH (emploi, type de contrat, convention, catégorie, mode de paiement) avec activation et journal | PARAMETRES |

## Base de données

Migrations dans `db/migrations/` (appliquées sur la base locale) :

| Fichier | Contenu |
|---|---|
| `…170000_core_hr.sql` | sociétés, départements, emplois, conventions, grilles, salariés, congés, présences |
| `…170100_payroll_schema.sql` | paramètres, barèmes IR/TRIMF, rubriques, structures, affectations, variables, traitements, bulletins |
| `…170200_security_rls.sql` | rôles `admin / rh / paie / salarie`, RLS sur toutes les tables |
| `…170300_payroll_engine.sql` | `compute_salary_slip`, `calculate_salary_slip`, `run_payroll_entry`, `solve_sursalaire_for_net`, IR, TRIMF, indemnités |
| `…170400_reference_data.sql` | taux, barèmes, 39 rubriques, 11 conventions et 254 catégories issus de PARAMETRES |
| `…170500_reports.sql` | vues livre de paie, cotisations, journal comptable, cumuls, soldes de congés ; `hr_dashboard` |
| `…170600_service_context.sql` | traitements serveur (clé service / console SQL) |
| `…170700_admin_users.sql` | gestion des comptes par l'administrateur |
| `…180000_delete_payroll_entry.sql` | suppression d'une paie mensuelle (validée : administrateur uniquement) |
| `…29090000_lot1_provisions_cumuls.sql` | provision précarité du mois ; cumuls annuels validés dans `v_payroll_register` et `v_salary_slip_ytd` |
| `…29120000_lot2_dashboard_annuel.sql` | `hr_dashboard` enrichi ; `hr_dashboard_year` (traitements validés, 12 mois) |
| `…29140000_lot3_presences.sql` | heures de maladie, contrôle 24 h par jour, traçabilité, report dans la paie |
| `…29160000_lot6_matricule.sql` | séquence et déclencheurs du matricule, `preview_employee_number`, `admin_change_employee_number`, `audit_log` |
| `…29180000_lot7_referentiels.sql` | `contract_types`, `payment_modes`, activation / journal des référentiels ; le moteur lit la nature du contrat dans le référentiel |
| `…30100000_durcissement_triggers.sql` | fonctions de déclencheur retirées de l'API |
| `…30110000_presences_dans_paie.sql` | `run_payroll_entry` reprend d'abord les présences (absences, maladie, heures sup.) dans les variables du mois |

**Impressions** : bon de congé (fenêtre de la demande), fiche salarié complète, livre de paie mensuel au modèle Sage (`/paie/:id/livre`, 7 salariés par page A4 + colonne Total).

Après chaque modification du moteur, le contrôle de non-régression recalcule les 25 bulletins d'août 2026
avec les valeurs du classeur (voir [l'analyse](docs/ANALYSE_EXCEL.md#3-validation-du-moteur-soma-rh)).

`db/seed/` contient la reprise des 26 salariés et des variables d'août 2026 (données personnelles :
exclu de Git par `.gitignore`).

### Correspondance avec Frappe HR

| Frappe HR (DocType) | SOMA-RH (table) |
|---|---|
| Company, Department, Designation | `companies`, `departments`, `designations` |
| Employee Grade | `employee_grades` (+ `collective_agreements`) |
| Employee | `employees` |
| Leave Type, Leave Allocation, Leave Application | `leave_types`, `leave_allocations`, `leave_applications` |
| Attendance | `attendance` |
| Salary Component | `salary_components` |
| Salary Structure, Salary Structure Assignment | `salary_structures`, `salary_structure_components`, `salary_structure_assignments` |
| Income Tax Slab | `tax_slabs`, `tax_slab_brackets`, `ir_family_reductions`, `trimf_brackets` |
| Additional Salary | `additional_salaries` (+ `payroll_inputs` pour les heures) |
| Payroll Entry | `payroll_entries` |
| Salary Slip (+ Salary Detail) | `salary_slips`, `salary_slip_details` |

## Outils pour Claude Code

* `.claude/skills/` : skills installés pour ce projet — `supabase-postgres-best-practices`,
  `graphify`, `frontend-design`, `ui-ux-pro-max`, `ui-styling`, `design-system`, `web-design-guidelines`,
  `vercel-react-best-practices`, `vercel-composition-patterns`, `deploy-to-vercel`, `vercel-cli-with-tokens`,
  `webapp-testing`, `xlsx`.
* `.claude/settings.json` : active le plugin officiel `vercel@claude-plugins-official` (Claude Code propose de
  l'installer à l'ouverture du projet ; sinon `/plugin install vercel@claude-plugins-official`).
* Graphify a besoin de son outil en ligne de commande sous Windows : `scripts\setup-skills.ps1`, puis
  `/graphify .` dans Claude Code pour générer la carte du code (`graphify-out/`).

## Documentation

* [Analyse du classeur Excel](docs/ANALYSE_EXCEL.md) : feuilles, formules, barèmes, macros, validation, anomalies.
* [Arbitrages des règles de paie](docs/ARBITRAGES_PAIE.md) : transport, IPM prestataires, indemnité de licenciement, arrondis (D10).
* [Feuille de route](docs/FEUILLE_DE_ROUTE_SOMA_RH.md) : état réel, benchmark (Frappe HR, OrangeHRM, Odoo, Sage), angles morts, architecture cible, lots 0 à 8, décisions à valider.
