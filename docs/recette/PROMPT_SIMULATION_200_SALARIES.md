# Prompt Claude Code — Simulation grandeur nature de SOMA-RH (10 à 200 salariés), guide utilisateur et dossier de reprise (v2.3)

> À coller dans Claude Code lancé dans `C:\IT-Mozaic\SOMA-RH-local` (PowerShell, Docker Desktop démarré, navigateur disponible).
> Cette version v2.2 remplace le « Master Battle Test » d'origine : elle est alignée sur l'architecture réelle de SOMA-RH (voir §2) et sur les résultats des recettes du 04 et 05/11/2026 (`docs/recette/`).
> Elle prolonge `docs/PROMPT_CAMPAGNE_TESTS_SOMA_RH.md` (v4) sans le refaire : la campagne v4 vérifie le moteur ; ce prompt simule une **entreprise qui grandit**, rôle par rôle, et en tire deux produits : un **guide utilisateur** et un **dossier de reprise** que l'IA pourra utiliser pour redévelopper ce qui ne passe pas.

---

## 1. Rôle et objectif

Tu es le **responsable de recette** de SOMA-RH. Tu pilotes une entreprise sénégalaise fictive qui passe de **10 à 200 salariés** sur 10 mois de paie, en utilisant l'application **par le navigateur, comme le feraient ses vrais utilisateurs**, avec **chacun des cinq rôles** (`admin`, `rh`, `paie`, `manager`, `salarie`) et leurs combinaisons.

Trois produits à livrer (détail au §9) :
1. **Guide utilisateur** (pages MDX publiées avec Mintlify depuis `docs/`) : chaque cas d'usage qui passe au vert devient une page pas-à-pas avec captures.
2. **Matrice VERT / ORANGE / ROUGE / BLOQUÉ** : l'état réel de chaque cas d'usage, preuve à l'appui.
3. **Dossier de reprise** : une fiche exploitable par une IA pour chaque point qui ne passe pas ou qui exige un travail de fond (écart, cause probable, fichiers à toucher, correctif proposé, test d'acceptation).

Principe cardinal : **ne jamais maquiller un résultat**. Un cas d'usage est vert seulement si tu l'as exécuté de bout en bout et vérifié le résultat. Une fonction absente est « BLOQUÉ – à développer », pas « OK ».

---

## 2. Écarts entre le prompt d'origine et SOMA-RH réel (à appliquer)

| Prompt d'origine | Réalité du produit | Conséquence pour la simulation |
|---|---|---|
| Front « React/TypeScript/Next.js » | React 18 + Vite + TS + Tailwind + TanStack ; données via PostgREST, API Node `api/server.mjs` | Recommandations de reprise sur ce socle, jamais Next.js |
| Instance neuve « à créer » | Base locale avec 23 salariés, données QA et simulations 2025–2026 | **Remise à zéro de la même base** (§4), sur autorisation écrite du propriétaire ; référentiel du produit et compte `mdiene` conservés |
| Documentation « style Frappe HR / Sage HR » | Documentation Mintlify dans `docs/` (`docs/docs.json`) ; analyses Frappe/Sage déjà dans `docs/comparatif/` | Écrire pour Mintlify, en s'inspirant de la clarté de Frappe sans le recopier |
| HS à 25 %, 50 %, 100 % | Les taux sont **datés** dans `overtime_rates` (115/140/160/200 % du classeur) ; décret 70-184 non lu | Ne pas imposer 25/50/100 ; comparer au registre légal et signaler l'écart |
| « IPRES Cadre (RCC 40 %) », « IPRES RG (60 %) » | RG : 14 % dont 8,4 % employeur et 5,6 % salarié (plafond 432 000 F) ; complémentaire cadres : 2,4 % / 3,6 % (plafond 1 296 000 F) ; statut ◐ (arrêtés non fournis) | Vérifier les taux **du paramétrage**, afficher leur statut légal |
| VRS | Supprimé par la CFCE (3 % employeur) | VRS hors périmètre : noter « sans objet » |
| Fichier « SEPA » | Pas de SEPA au Sénégal | Tester l'ordre de virement et le suivi de paiement (`paie/:id/paiements`, `payment_orders`) |
| Articles du Code du travail « cités de mémoire » | Seuls les textes **présents dans le projet** font foi (`docs/sources-legales/`, Code du travail 2026, CSS 2026, CGI 2025, CCNI) avec leur statut ✔ ◐ ✖ | Aucune citation sans texte lu ; sinon « source à fournir » |
| « Sans demander de confirmation » | Garde-fous du §4 (sauvegarde, périmètre, identifiants) | Autonomie totale **dans** ce périmètre |
| Équivalences gardiennage 56/72 h, HORECA 50/45 h | Valeurs d'un texte nigérien ; décisions dans `docs/sources-legales/DECISIONS_GARDIENNAGE_EQUIVALENCE.md` | Lire la décision ; ne tester que ce qui est décidé |

---

## 3. Lectures obligatoires avant d'agir (dans cet ordre)

1. `CLAUDE.md` (règles, contrôles qualité, limite de connexions).
2. `docs/recette/README.md`, `RESULTATS_SIMULATION_100_2026-11-04.md` (sections 17 à 20), `TACHES_ET_RECOMMANDATIONS_RECETTE.md`, `BATTERIE_TESTS_RECETTE.md`, `TESTS_RESTANTS_ET_RECOMMANDATIONS.md` : défauts connus D-01 à D-63, avec état de correction. **Ne pas les redécouvrir** : les rejouer et marquer « connu » ou « corrigé ».
3. `docs/regles-de-paie/registre-legal.mdx`, `docs/ARBITRAGES_PAIE.md`, `docs/sources-legales/DECISIONS_*.md`.
4. `docs/modules/` (modules métiers verticaux : gardiennage, intérim, HORECA, transport, nettoyage/BTP ; statuts des paramètres).
5. `docs/PLAN_CONTROLE_QUALITE_SOMA_RH.md` (invariants I1–I20) et `docs/qa/`.
6. Pour le code : `graphify query "<question>"` avant de parcourir les fichiers.

Puis vérifie, sans supposer : migrations appliquées (`scripts/check-migrations.sh`), en particulier `20261107110000` (D-49), `20261107120000` (D-43) et `20261107130000` (D-30/D-53, plafond de prêt) ; baseline `scripts/verify-payroll.ps1`.

---

## 4. Instance de simulation et garde-fous

### 4.1 Phase 0 — repartir de zéro sur la même base (décision du propriétaire, 09/11/2026)
Autorisation du propriétaire : « tu peux supprimer les 23 salariés de base », rester sur la même base, supprimer les salariés et utilisateurs restants, **conserver l'utilisateur `mdiene`** (administrateur), pas de seconde pile Docker (mémoire limitée). Le travail se fait « comme un nouvel utilisateur ».

1. **Sauvegarde** : `scripts\sim-reset-zero.ps1` appelle `scripts\local-backup.ps1` avant toute suppression. Contrôle que le `.dump` est lisible et note la commande de restauration (`scripts\local-restore.ps1`).
2. **Remise à zéro** : `scripts\sim-reset-zero.ps1` (confirmation `RESET-ZERO`) exécute `tests/fixtures/sim/reset-zero.sql` en une transaction : vide salariés, paie, congés, présences, documents, organisation, audit et comptes **sauf `mdiene@gmail.com`** ; conserve le **référentiel du produit** (taux et plafonds, barèmes IR/TRIMF, rubriques, conventions, grilles, structures salariales, types de congé, paramètres, modules, société). Un garde-fou interrompt tout si une table conservée dépend d'une table vidée. Après la remise à zéro : `verify-payroll.ps1` n'a plus de sens (plus de bulletins) ; la référence sera refaite à la fin de la campagne (`-Save`, évolution voulue).
3. **Comptes** : `scripts\sim-create-users.ps1` (voir §5). Le compte `mdiene` reste le compte de configuration ; ne change jamais son mot de passe, ne l'écris nulle part.
4. Reconstruction à vide des migrations (test **H-01**) : **non faite** sur cette base (elle exigerait une base neuve). La noter « NON TESTÉ – raison : mémoire », avec le suspect connu (`20261104180000_maj_compute_salary_slip.sql` semble incomplet).
5. Aucune donnée réelle n'existe plus après l'étape 2 : toute donnée créée ensuite est **fictive** (matricules `SIM…`).

### 4.2 Garde-fous
- Données **fictives uniquement**. Matricules `SIM0001` à `SIM0200`. Noms sénégalais plausibles, RIB et téléphones fictifs. Rien de personnel dans Git (`scripts/scan-pii.sh` avant tout commit).
- **Identifiants** : crée toi-même les comptes de test avec des mots de passe jetables générés, écrits seulement dans `tests/.env.qa-sim` (hors Git). Ne les affiche jamais, ni dans la conversation, ni dans les rapports, ni dans les captures (masque le champ).
- **Anti-verrouillage** : l'API verrouille 30 minutes une adresse après des échecs répétés (D-58) et limite `POST /auth/v1/token` à 30 par 15 minutes. Connecte-toi **une fois par compte**, réutilise la session (jeton dans `localStorage`, clé `sb-localhost-auth-token`, ou `refresh_token`). Jamais de boucle de connexions. Tests de limite : un seul, en fin de campagne, sur l'instance de simulation.
- **Migrations** : toute correction passe par `db/migrations/…` + retour arrière + `notify pgrst, 'reload schema'`. Sous PowerShell, n'envoie jamais de SQL accentué par un tube (les accents sont altérés) : `docker cp fichier.sql <conteneur>:/tmp/m.sql` puis `psql -f`. **Tu ne corriges pas en cours de simulation** : tu consignes (§9) ; les corrections viennent après, sur validation.
- **Navigateur** : l'exécution se fait dans le navigateur intégré, session ouverte avec `mdiene` puis, pour chaque rôle, avec le compte `sim-*` correspondant (une seule connexion par compte).
- **Moteur de paie** : `verify-payroll.ps1` est un garde-fou de non-régression, pas une preuve de conformité légale. Compare les montants aux textes (registre légal) et à l'oracle `tests/oracle/`.
- Aucune valeur légale inventée. Un paramètre ✖ reste vide ; le produit doit alors émettre une alerte `compliance_findings`.
- Pas de commit ni de push sans demande.

---

## 5. Comptes et rôles à créer

Crée les comptes avec `scripts\sim-create-users.ps1`. L'inscription publique est **fermée** (D-016) et l'application n'a **aucune fonction de création de compte par l'administrateur** : c'est un **manque produit** à consigner en BLOQUÉ (UC « inviter / créer un utilisateur »), avec une fiche de reprise (écran admin + fonction `admin_create_user` + envoi d'invitation). Le script crée donc les comptes en base (hachage bcrypt par le conteneur API) et écrit les identifiants jetables dans `tests/.env.qa-sim` (hors Git) ; option `-MotDePasseCommun` pour un mot de passe jetable unique saisi au clavier. Rattache les comptes `salarie` et `manager` à un dossier salarié une fois ces salariés créés dans l'application (`Paramètres` → utilisateurs, ou `admin_link_employee`).

| Compte | Rôle(s) | Sert à |
|---|---|---|
| `mdiene` (existant) | admin | Configuration initiale uniquement ; jamais utilisé pour les tests de droits |
| `sim-admin`, `sim-admin2` | admin | Configuration, rôles, dérogations motivées, réouverture, audit |
| `sim-rh`, `sim-rh2` | rh | Dossiers, contrats, congés, préparation (rh1) et approbation (rh2) de la paie |
| `sim-paie`, `sim-paie2` | paie | Variables, calcul, paiements, clôture, taux de paie |
| `sim-rhpaie` | rh + paie | Cumul de rôles et séparation des tâches |
| `sim-mgr-1` … `sim-mgr-5` | manager | Équipes par métier (administration, mines/BTP, gardiennage, HORECA, logistique) |
| `sim-sal-1` … `sim-sal-8` | salarie | Un par profil : cadre, ouvrier, gardien de nuit, serveur, chauffeur, CDD, intérimaire, stagiaire |

Pour **chaque** compte : parcours attendu (menu visible, routes accessibles) **et** parcours interdit (accès direct aux URL et aux tables refusé : écran, API, RLS). Réutilise `tests/api/isolation.test.mjs`, `routes.test.mjs`, `workflow.test.mjs` et `web/e2e/menu.spec.ts` comme socle ; complète-les avec les comptes `sim-*`.

Séparation des tâches à éprouver avec **deux comptes distincts** : préparateur ≠ approbateur ; validation directe « Calculée → Validée » réservée à l'admin avec motif (D-43) ; dérogation tracée dans l'audit.

---

## 6. Population fictive et croissance

### 6.1 Répartition cible à 200 salariés (adapter ±10 %)
| Secteur | Effectif | Particularités à couvrir |
|---|---|---|
| Administration et direction | 35 | Cadres, 40 h, primes de responsabilité, IPRES complémentaire cadres |
| Mines, BTP, industrie | 60 | Ouvriers, heures supplémentaires, primes de salissure/risque/transport, postes continus |
| Gardiennage et sécurité | 40 | Vacations 12 h, nuit (22 h–5 h), équivalence selon la décision du projet |
| HORECA | 25 | Horaires à coupure, avantages en nature, service |
| Logistique et chauffeurs | 30 | Temps de conduite/attente, indemnités de déplacement (CCNI art. 61) |
| Services : intérim et prestataires | 10 | Intérimaires, consultants (BRS 5 % au cœur), stagiaires |

Contrats : CDI, CDD, intérim, stage, prestataire. Grilles : du SMIG/SMAG aux cadres supérieurs. Situations familiales : 0 à 5 parts et plus ; enfants à charge. Prévois des cas limites volontaires : salaire au plafond IPRES, 63 000 F CSS, tranche IR à 40 %/43 %, TRIMF à chaque tranche, entrée et sortie en cours de mois, absence longue, prêt, régularisation.

### 6.2 Calendrier (10 mois de paie, jamais de mois futur : la date du jour est le plafond)
| Mois | Effectif | Événements à jouer |
|---|---|---|
| Janv. 2026 | 10 | Configuration initiale, premiers contrats, première paie bout en bout |
| Févr. | 25 | Premiers congés, premières HS, un manager |
| Mars | 40 | Gardiennage (nuit), prêts, acomptes |
| Avr. | 60 | HORECA, avantages en nature, absence maladie |
| Mai | 80 | Chauffeurs, déplacements, première sortie (démission) |
| Juin | 100 | CDD/intérim, renouvellements, solde de tout compte |
| Juill. | 130 | Mines/BTP, postes continus, licenciement, maternité |
| Août | 160 | Congés massifs, réorganisation d'équipes (module Équipes/organigramme) |
| Sept. | 180 | Déclarations (IPRES, CSS, DGID), journal comptable, clôture annuelle partielle |
| Oct. | 200 | Pic de charge, retraite, décès, réouverture motivée d'un mois, audit |

À chaque palier : création des salariés, variables du mois, calcul, contrôles, séparation des tâches, validation, paiement, clôture, états. Mesure à chaque palier : durée du calcul de la paie, du livre de paie, de la liste des salariés, du tableau de bord, de l'impression des bulletins (`tests/perf/`).

---

## 7. Plan de test par module (identifiants UC-xx)

Chaque ligne = au moins un cas d'usage (UC) avec un parcours **nominal**, un parcours **erreur** et, quand c'est pertinent, un parcours **interdit** selon le rôle. Les écrans sont ceux de `web/src/App.tsx`.

| Bloc | Écrans / routes | À couvrir |
|---|---|---|
| A. Configuration | `/parametres`, `/modules`, `/conformite`, `/centre-conformite` | Société, départements, postes, conventions, grilles, rubriques, taux et plafonds datés, barème IR, plafond de retenue de prêt, activation des modules métiers et saisie des paramètres manquants |
| B. Salariés | `/salaries`, `/salaries/:id`, `/dossiers-salaries` | Embauche (tous contrats), ayants droit, RIB, pièces, affectation de structure salariale, avenants, promotions, mutations, suspension ; sortie (`sortie_salarie`), solde de tout compte, certificat de travail |
| C. Temps | `/presences`, `/planning`, `/mon-equipe` | Pointages, vacations, nuit, rotations, HS, validation par le manager |
| D. Congés et absences | `/conges`, `/demandes`, `/mon-espace` | Acquisition, demande, validation, solde, absences exceptionnelles, maladie, maternité |
| E. Paie | `/paie`, `/paie/variables`, `/paie/ajustements`, `/paie/:id`, `/paie/gouvernance`, `/paie/simulateur` | Variables, calcul individuel et massif, contrôles bloquants, workflow Brouillon → Calculée → En revue → Approuvée → Validée → Payée → Clôturée, réouverture, retour en Calculée, prêts et régularisations, net jamais négatif, périodes clôturées immuables |
| F. Paiements et états | `/paie/:id/paiements`, `/paie/:id/imprimer`, `/paie/:id/livre`, `/paie/:id/rapport`, `/etats` | Ordres de virement, bulletins imprimés, livre de paie, rapport de clôture, IPRES/CSS (`export_ipres_css`), DGID (`etat_dgid`), journal comptable |
| G. Libre-service | `/mon-espace`, `/mes-bulletins`, `/bulletins/:id` | Salarié : bulletins validés seulement, demandes, documents |
| H. Équipes | `/equipes`, `/equipes/organigramme`, `/equipes/simulation` | Affectations managers, organigramme, simulation de réorganisation |
| I. Pilotage | `/`, `/pilotage`, `/journal` | Tableau de bord (masse salariale validée par mois sur tous les mois), audit chaîné (`audit_verify`) |
| J. Modules métiers | `/modules` | Pour chaque module : désactivé = aucun effet (empreinte `verify-payroll` identique) ; activé = champs, rubriques et alertes attendus ; paramètre ✖ manquant = alerte |
| K. Sécurité | Voir §5 | Accès par rôle, jetons falsifiés, isolation RLS, limite de connexions, documents |
| L. Résilience | Scripts `local-*` | Sauvegarde, restauration, remise à zéro, rejeu des migrations |

**Règles légales** : pour chaque calcul vérifié (IR, TRIMF, CFCE, IPRES, CSS, IPM, BRS, HS, nuit, congés, préavis, indemnités), consigne le texte et l'article **du projet**, son statut (✔ ◐ ✖), la valeur attendue (recalculée à la main ou par l'oracle) et la valeur obtenue, **au franc près**. Un écart sur un texte ✔ est un défaut ; un écart sur un texte ✖ est une « question légale ouverte ».

**Fonctions absentes** (par exemple import massif, pointeuse, module non encore développé) : essaie d'abord de les trouver dans l'application ; si elles n'existent pas, statut BLOQUÉ, avec la référence du document de spécification qui les prévoit.

---

## 8. Méthode d'exécution

**Boucle par palier**, sans attendre de validation entre deux étapes : préparer les données → jouer les UC par rôle dans le navigateur → vérifier en base (lecture seule) → consigner → mesurer → palier suivant. Arrête-toi seulement pour une décision irréversible touchant des données hors simulation.

**Navigateur** (Claude in Chrome, navigateur intégré ou Playwright) :
- Parcours **fonctionnels** (au moins 15 salariés par secteur, tous les workflows, tous les rôles) : **par l'interface**, avec captures.
- **Volume** (le reste des 200 dossiers) : par l'interface si un import existe ; sinon par les appels REST/RPC authentifiés d'un compte `sim-*`. Dis-le dans le rapport : « injection API » n'est pas « parcours UI ».
- Dialogues `confirm`/`prompt` : remplace-les pour ne pas bloquer le navigateur ; champs React : utilise le setter natif de l'élément puis déclenche `input`/`change` ; appels JavaScript courts (moins de 45 s) ; reconstruis les en-têtes d'API après chaque rechargement de page.
- Chaque UC garde : captures avant/après, texte exact des messages d'erreur, identifiant de l'enregistrement, requête ou fonction vérifiée.

**Statuts**
- **VERT** : exécuté, résultat conforme, preuve conservée.
- **ORANGE** : fonctionne avec une réserve (UX, message, perf au-delà du seuil, écart à arbitrer).
- **ROUGE** : écart avéré (calcul, droit, sécurité, intégrité, plantage).
- **BLOQUÉ** : fonction absente ou impossible à atteindre (cause indiquée).
- **NON TESTÉ** : jamais en silence ; raison obligatoire.

**Gravité** : Critique (paie ou calcul légal faux, fuite de données, perte de données), Majeur (fonction dégradée, contournement coûteux), Mineur (UX, libellé, accessibilité).

---

## 8 bis. Playwright : exploration à la main, rejeu automatisé

- **Exploration** : dans le navigateur intégré (ou Claude in Chrome), pour découvrir les écrans, jouer les parcours et trancher VERT/ROUGE.
- **Rejeu** : chaque UC passé au vert est transcrit en test Playwright dans `web/e2e/sim/` (`<bloc>-<uc>.spec.ts`), qui sert à la fois de **test de non-régression** et de **générateur des captures du guide** (`docs/captures-sim/<uc>-<étape>.png`, même résolution, mots de passe masqués). Réutilise `web/e2e/auth.setup.ts` : **une connexion par rôle**, session réutilisée (`storageState`), jamais de connexion dans le test. Données et comptes lus dans `tests/.env.qa-sim`.
- Les tests de rejeu **créent des données `SIM…`** : ils sont rejouables seulement après `sim-reset-zero.ps1`, ou écrits pour être idempotents (recherche avant création). Ceux qui ne modifient rien (menus, accès interdits, accessibilité WCAG, lecture des états) restent rejouables en tout temps.
- Mémoire limitée : un fichier à la fois (`npx playwright test e2e/sim/<fichier>`), pas de parallélisme (`--workers=1`).
- Les ROUGE deviennent des tests **qui échouent** (`test.fixme` avec référence `RPR-xxx`) : ils servent de critère d'acceptation au dossier de reprise.

## 9. Livrables (tout dans `docs/`)

```
docs/guide-utilisateur/          ← pages MDX Mintlify (VERT uniquement)
  index.mdx, premiers-pas.mdx, roles-et-droits.mdx
  salaries/…, temps-et-presences/…, conges/…, paie/…, paiements-et-etats/…,
  libre-service/…, equipes/…, pilotage/…, modules-metiers/…, depannage.mdx
docs/captures-sim/               ← captures (données fictives, mots de passe masqués)
docs/recette/simulation-200/
  MATRICE_UC.md  +  matrice.csv  ← tous les UC, un statut, une preuve
  PROFILS_FICTIFS.csv            ← SIM0001…SIM0200 (secteur, contrat, grille, parts, dates)
  JOURNAL_PALIERS.md             ← un compte rendu par mois simulé, avec mesures de performance
  RAPPORT_VERT_ROUGE.md          ← synthèse : ce qui marche, ce qui ne marche pas, priorités
  DOSSIER_DE_REPRISE.md          ← fiches de reprise (ci-dessous)
  QUESTIONS_LEGALES_OUVERTES.md  ← textes à fournir, paramètres ✖
docs/recette/PROMPT_SIMULATION_200_SALARIES.md ← ce fichier, mis à jour (v2.2) en fin de campagne
```
Mets à jour `docs/docs.json` (navigation Mintlify) et `docs/recette/README.md`.

### 9.0 Base documentaire utilisateurs (à créer, pas seulement des pages isolées)
- `docs/guide-utilisateur/index.mdx` : présentation du produit, vocabulaire, parcours d'apprentissage « par où commencer » selon le rôle (je suis administrateur, RH, paie, manager, salarié).
- Un **parcours par rôle** (`parcours-admin.mdx`, `parcours-rh.mdx`, `parcours-paie.mdx`, `parcours-manager.mdx`, `parcours-salarie.mdx`) : l'ordre dans lequel un nouvel utilisateur découvre les écrans, avec liens vers les pages des cas d'usage.
- Un **calendrier de paie** pas-à-pas (du mois ouvert à la clôture) avec le workflow et les rôles à chaque statut.
- `glossaire.mdx` (brut, net imposable, parts, TRIMF, CFCE, IPRES RG/RC, CSS PF/AT, IPM, BRS, HS, équivalence, STC… avec la source légale du projet et son statut) et `faq.mdx` (questions réelles rencontrées pendant la simulation, avec le message d'erreur exact).
- `modeles/` : fichiers d'exemple fictifs (import, pointage) si l'application en accepte.
- `_index_uc.csv` : pour chaque UC, la page du guide, le test Playwright, le statut. Aucun UC vert sans page ; aucune page sans UC.
- `docs/docs.json` : navigation Mintlify mise à jour (groupes : Démarrer, Parcours par rôle, Modules, Paie et déclarations, Dépannage, Glossaire et FAQ). Vérifie que le site se construit (`mint dev` ou la commande du projet) et que les liens internes sont valides.

### 9.1 Page du guide utilisateur (gabarit, une par UC vert)
Titre en verbe d'action · Rôle concerné · Prérequis · Étapes numérotées (chemin de menu exact, libellés des boutons tels qu'à l'écran) avec capture · Résultat attendu · Erreurs fréquentes et message exact · Règle de gestion et source légale avec statut · Cas particuliers · Voir aussi. Langage simple, exemples chiffrés fictifs. Aucune page pour un UC non vert : il va dans le rapport et le dossier de reprise.

### 9.2 Fiche de reprise (gabarit, une par ROUGE, ORANGE notable ou BLOQUÉ)
```
ID : RPR-001   Lien : UC-E-12, défaut connu D-xx (ou « nouveau »)
Gravité / Statut : Majeur / ROUGE      Module : Paie      Rôle(s) : paie, rh
Écran / API / fonction : /paie/:id — transition_payroll_entry
Reproduction : données SIM… ; étapes numérotées ; compte utilisé
Attendu : … (source : texte + article, statut ✔ ◐ ✖, ou règle produit)
Obtenu : … (message exact, valeur au franc près, capture)
Cause probable : fichier(s) / fonction(s) / migration, vérifiés avec graphify
Correctif proposé : migration (+ retour arrière) | composant React | RLS | paramètre
Test d'acceptation : fichier à créer ou compléter (tests/sql, tests/api, e2e) + résultat attendu
Dépendances / risques : verify-payroll, autres UC touchés, décision à prendre
Effort : S / M / L     Priorité : P1 / P2 / P3
```
Le dossier est trié par priorité puis par dépendance, avec un **ordre de développement conseillé** et la liste des **décisions du propriétaire** nécessaires.

---

## 10. Fin de campagne

1. Rejoue `verify-payroll.ps1`, `scripts/test-sql.ps1`, `tests/api/*.test.mjs`, `web/e2e` (un fichier à la fois) et consigne les résultats.
2. Fais `scripts\verify-payroll.ps1 -Save` sur le dernier mois simulé (nouvelle référence) ; décide avec le propriétaire de conserver la base simulée ou de restaurer la sauvegarde du §4.1.
3. Rapport final court en français : ce qui est vert, ce qui est rouge, ce qui est bloqué, les cinq points à traiter d'abord, les décisions attendues, les chemins des livrables.
4. **Auto-amélioration** : à partir de ce que l'architecture et l'exécution ont montré, réécris ce prompt en v2.2 (corrige ce qui a gêné, ajoute les raccourcis découverts) et enregistre-le sous le même nom.

## 11. Enseignements de la campagne du 09/11/2026 (v2.3)

À appliquer lors de la prochaine campagne ; détails dans `simulation-200/RAPPORT_VERT_ROUGE.md` et `simulation-200/DOSSIER_DE_REPRISE.md`.

1. **Méthode** : explorer à la main (navigateur) les paliers 1 à 4, rejouer ensuite par Playwright (`web/playwright.sim.config.ts`, specs `web/e2e/sim/`). Durée du rejeu complet des paliers 5 à 9 : environ 5 minutes.
2. **Connexions** : réutiliser les sessions enregistrées (`sim.setup.ts`). Plus de 45 connexions en 20 minutes verrouillent tous les comptes pendant 30 minutes (D-58).
3. **Création d'un salarié = trois étapes et deux métiers** : fiche (RH), déclaration d'embauche (référence + date, exigée à la première validation), structure salariale (paie ou admin seulement).
4. **Workflow à comptes distincts** : l'approbation exige le rôle rh ; prévoir un compte rh+paie (`sim-rhpaie`) tant que RPR-02 n'est pas corrigé. L'admin ne clôture qu'avec motif ; D-64 corrigé (garde de période).
5. **Idempotence** : un rejeu ne doit pas ressaisir ce qui existe (embauches, variables déjà enregistrées, bouton Enregistrer désactivé). Les assertions ne doivent pas dépendre d'un message fugace.
6. **Délais** : navigation jusqu'à 120 s et attente de confirmation jusqu'à 60 s à partir de 175 salariés.
7. **Ne jamais mettre à jour la référence de `verify-payroll.ps1`** avec les chiffres de la base simulée ; la relancer seulement après restauration de la sauvegarde d'origine.
8. **Points ouverts avant la prochaine campagne** : RPR-01 à RPR-15, décisions D-56 (prorata), approbateur, plafond de prêt, paiements individuels.
9. **Palier 10 à prévoir** : sorties, CDD, prêts, congés, heures supplémentaires (explorer les écrans avant d'écrire les sélecteurs).

---

## Nouveautés v2.3 (12/11/2026)
- **Guide complet** : 24 pages dans `docs/guide-utilisateur/` (Markdown simple, sans JSX), lues par le site Mintlify et par l'onglet « Documentation utilisateur » (Paramètres). Contrôle : `tests/unit/guide.test.mjs` ; onglet : `web/e2e/guide.spec.ts`.
- **Helper de capture** : `web/e2e/sim/helpers/capture.ts` (masque mots de passe et jetons, 1280×800, nom à tiret et unique) ; captures dans `docs/guide-utilisateur/captures/`.
- **Parcours ajoutés** : `05-demarrer` (emplois), `06-comptes` (liaisons, équipes), `40-ecrans` (41 écrans par rôle), `41-embauches`, `42-etats`, `43-connexion`.
- **Base remise à zéro** : les emplois, les liaisons compte-fiche et les équipes sont à recréer (parcours 05 et 06) ; les matricules repartent de S0724 (décalage de +433 dans `11-octobre` et `12-reouverture`).
- **Comptes QA** : `scripts/qa-create-users.ps1` ne fonctionne plus (inscription fermée) ; `tests/.env.qa` se régénère à partir de `tests/.env.qa-sim`.
- Suivi de la campagne : `docs/recette/SUIVI_GUIDE.md`.
