# Dossier de reprise — fiches RPR

Chaque fiche permet à un développeur (ou une IA) de reprendre un point sans relire la campagne. Priorité : P1 bloquant ou sécurité, P2 important, P3 confort.
Dépôt : `C:\IT-Mozaic\SOMA-RH-local`. Migrations : `docker cp` + `psql -f`, puis `notify pgrst, 'reload schema'`.

## RPR-01 — Calcul sans structure salariale silencieux (P1) · P1-06
- Constat : un salarié sans structure donne l'erreur API « Aucune structure salariale affectée », mais la paie passe en Calculée avec 0 bulletin et aucun message.
- Attendu : message visible listant les salariés non calculés et blocage de « Envoyer en revue » tant qu'il en reste.
- Pistes : fonction de calcul (compute) et `PayrollGovernancePage.tsx`.
- Test : créer un salarié sans structure, calculer, vérifier le message et le blocage.

## RPR-02 — Approbation impossible depuis l'écran pour un rôle seul (P1) · P5-04, P5-06
- Constat : `transition_payroll_entry` exige le rôle rh pour « Approuvée » (migration `20261107120000_d43…`, l. 33) ; l'écran n'affiche les boutons qu'à `can('paie')` (`PayrollGovernancePage.tsx`, l. 157). Un compte rh ne voit rien, un compte paie seul est refusé.
- Attendu : bouton « Approuver la paie » visible pour rh (et admin), masqué pour paie seul ; message clair en cas de refus.
- Test : `web/e2e/sim/10-croissance.sim.spec.ts` avec un compte rh seul à l'étape d'approbation.

## RPR-03 — Verrouillage de connexion par adresse source (P1 sécurité) · X-01, D-58
- Constat : environ 45 connexions en 20 min depuis un poste verrouillent tous les comptes pendant 30 min.
- Attendu : compteur par compte + adresse, ou par compte seul avec alerte ; limite par IP plus haute et séparée.
- Pistes : `api/server.mjs` (limite 30 connexions / 15 min, verrouillage).
- Test : N échecs sur le compte A ne bloquent pas le compte B.

## RPR-04 — Dérogation sans champ motif (P2) · P1-09, P1-10
- Constat : refus D-43 « motif de dérogation obligatoire » sur validation directe, mais le dialogue n'a pas de champ ; sur l'autre chemin le motif est pré-rempli avec le message d'erreur.
- Attendu : champ motif vide et obligatoire dans les deux chemins.

## RPR-05 — Période Réouverte sans Recalculer (P2) · P3-02
- Constat : message « pourra être recalculée ou supprimée », mais seuls Annuler et Supprimer existent.
- Attendu : bouton Recalculer sur statut Réouverte (admin, avec motif déjà saisi).

## RPR-06 — Création d'un salarié : fiabilité et découpage (P2) · P5-01, P5-02, P7-01
- Constat : structure en lecture seule pour le RH sans explication ; Enregistrer actif avant chargement de la structure (erreur brute `structure_id` not-null) ; message « Fiche enregistrée » fugace.
- Attendu : message explicatif pour le RH, bouton inactif tant que la structure n'est pas chargée, confirmation persistante, erreur traduite.

## RPR-07 — Date d'effet par défaut d'une structure (P2) · P1-07
- Constat : la date par défaut est le mois courant, donc ignorée par un calcul d'un mois passé.
- Attendu : date par défaut = date d'embauche, avertissement si postérieure à la période en cours.

## RPR-08 — Plafond de retenue sur prêt : base ≠ dépôt (P2) · R-08, R-09, D-30/D-53
- Constat : `set_loan_max_rate` refuse rh et paie en base ; le fichier `20261107130000_d30_d53_…` les autorise.
- Action : vérifier la version appliquée, aligner base et dépôt selon la décision (admin seul ou admin/rh/paie), cocher D-30/D-53 dans BATTERIE, TACHES, RESULTATS.

## RPR-09 — Prorata à l'entrée en cours de mois (P2) · P1-11, D-56 (décision en attente)
- Constat : S0299, entrée le 15/01, payée sur le mois entier.
- Action : décision métier, puis calcul au prorata des jours (calendaire ou ouvrable), test d'écart sur le bulletin.

## RPR-10 — Référentiels manquants (P2) · P1-04, P1-15
- Constat : aucun écran de départements (table `departments` vide, pas de champ sur la fiche) ; tables `shift_types` et `work_posts` absentes (page /planning à vérifier).

## RPR-11 — Ergonomie, texte et données (P3) · P1-02, P1-03, P1-05, P1-13, P1-01
- Boutons d'action hors écran à 1280 px (Conventions) ; Entrée ne valide pas l'ajout d'un référentiel ; convention « Prestations de services » avec 1 catégorie à 0 F ; texte Paramètres > Accès parlant d'inscription depuis la connexion alors qu'elle est fermée ; conventions désactivées en base.

## RPR-12 — Contrôles bloquants peu lisibles (P2) · P5-08, P5-09
- Constat : le refus ne dit pas quel contrôle bloque ; l'envoi en revue passe malgré un blocage.
- Attendu : liste des contrôles dans le message de refus ; avertissement dès l'envoi en revue.

## RPR-13 — Déclaration d'embauche découverte tardivement (P3) · P1-08
- Constat : exigée à la première validation, non mentionnée à la création de la fiche. Attendu : indicateur « déclaration manquante » sur la fiche.

## RPR-14 — Paiements individuels et matricules (P3) · P1-12, P1-14
- Constat : Payée puis Clôturée sans aucun `salary_payments` ; matricules démarrant à S0291.
- Action : décision sur l'obligation d'enregistrer les paiements ; séquence de matricule à réinitialiser avec la base.

## RPR-15 — Performance à 175–200 salariés (P3) · P8-01, P9-01
- Constat : confirmation d'enregistrement des variables > 5 s sans indicateur ; chargement de /paie/variables > 30 s lors d'un run.
- Attendu : indicateur de progression, mesure du temps d'écriture ligne par ligne, écriture en lot.

## Résolu pendant la campagne
- D-64 garde de période (migration `20261109170000_d64_garde_periode_mois_precedent.sql`, rollback, test `tests/sql/d64_garde_periode.sql`) : appliqué, test OK.

---
## Complément du 10/11/2026 (palier 10)
- **RPR-09 confirmée** : sortie du 23/10/2026 (S0450) payée le mois entier ; aucun prorata dans `compute_salary_slip`. Décision D-56 à coder (entrée et sortie, base ouvrables par défaut).
- **RPR-01 à RPR-15** : aucun correctif commité à ce jour (`git log`). Suivi en `test.fixme` dans `web/e2e/sim/30-rpr.sim.spec.ts`.
- **Nouveau (ORANGE)** : approbation de congé par le manager introuvable dans `/mon-equipe` (bouton Approuver absent) ; la RH a approuvé directement.
- **Nouveau (ORANGE)** : statut de la fiche resté « Actif » après enregistrement d'une date de sortie par la fiche.
- **Nettoyage** : demande de congé d'un test antérieur (S0291, « eere r »).

### RPR-09 corrigée (10/11/2026, branche `fix/rpr-09-prorata`)
- Migration `20261214090000_rpr09_prorata_entree_sortie` (+ retour `db/rollback/…_down.sql`, testé) : paramètre `payroll_settings.proration_basis` (`ouvrables` par défaut = lundi au samedi, jours fériés non déduits ; `calendaires`) et ligne de bulletin `RET_PRORATA`. Entrée et sortie incluses ; transport, kilométrique et prime d'ancienneté suivent le ratio.
- Test : `tests/sql/rpr09_prorata.sql` (entrée le 15/01 : 12/27 retenus ; calendaire : 14/31 ; sortie le 23/10 : 7/27 ; sortie le 31/10 : aucun prorata ; base invalide refusée). Recalcul de septembre : 200 bulletins, 0 écart avec les bulletins clôturés. Suite SQL : mêmes 11 échecs de données qu'avant (vérifié migration retirée).
- Les bulletins déjà calculés ne sont pas recalculés. Octobre 2026 (clôturé) reste au mois entier pour S0450 : à rouvrir et recalculer (réouverture motivée, admin) si le propriétaire le souhaite.
- Changer la base de prorata passe par une nouvelle version datée des paramètres (garde-fou existant : un paramétrage déjà utilisé n'est pas modifiable).
- Décisions ouvertes : jours fériés (non déduits en base ouvrables) ; prorata appliqué aussi au transport (choix retenu) ; interface de saisie du paramètre non faite.

---
## État au 10/11/2026 (branche `fix/rpr-09-prorata`)
| Fiche | Statut | Détail |
|---|---|---|
| RPR-09 | corrigée | voir plus haut ; octobre 2026 rouvert, recalculé, reclôturé (S0450 : retenue de prorata 18 331,96 F, net 63 403,18 F) |
| RPR-05 | corrigée | bouton Recalculer sur une paie « Réouverte » ; `run_payroll_batch` remet les bulletins validés en brouillon avant recalcul (migration `20261214100000`). Cause racine : sans cela chaque bulletin refusait le recalcul et l'écran annonçait quand même « N bulletin(s) calculé(s) » |
| RPR-01 | corrigée (base) | `transition_payroll_entry` refuse « En revue » et liste les salariés sans bulletin (migration `20261214110000`, test `rpr01_revue_incomplete`). Reste : avertissement persistant sur la page d'une paie incomplète |
| RPR-02 | corrigée (base) | approbation par admin et rôle paie, plus par rh (migration `20261214120000`, test `rpr02_approbation_roles`). L'écran était déjà conforme. Specs : `paie2` approuve. Reste : parcours Playwright sur un mois ouvert (tous les mois simulés sont clôturés) |
| RPR-03 | corrigée (partiel) | verrou progressif par couple compte + adresse (`api/server.mjs`), limite par adresse 120/15 min, test `tests/api/login.lock.test.mjs`. Reste : alerte à l'administrateur ; verrou en mémoire (perdu au redémarrage de la passerelle) |
| RPR-04 à RPR-08, RPR-10 à RPR-15 | à faire | |

Constats nouveaux : (1) `run_payroll_batch` avale les erreurs de calcul ; (2) la ligne `RET_PRORATA` devait exister dans `salary_components` (clé étrangère) ; (3) la passerelle de test sur le port 8001 doit pointer `POSTGREST_URL=http://localhost:3001` quand elle tourne hors Docker.

### Mise à jour du 11/11/2026 : RPR-04, 06, 07, 08
| Fiche | Statut | Détail |
|---|---|---|
| RPR-04 | corrigée | page d'une paie : motif de dérogation toujours demandé, champ vide, bouton désactivé tant qu'il est vide (`PayrollEntryPage.tsx`). Le dialogue de la page Gouvernance était déjà conforme. Pas de test Playwright (aucun mois ouvert à valider) |
| RPR-05 | corrigée | voir plus haut |
| RPR-06 | corrigée (partiel) | structure salariale : message de lecture seule pour rh, enregistrement bloqué avant chargement, erreur lisible à la place de `structure_id`, confirmation avec `role="status"`. Le message « Fiche enregistrée » reste un état d'écran (disparaît au prochain enregistrement) |
| RPR-07 | corrigée | date d'effet par défaut = date d'entrée ; avertissement si elle est postérieure à aujourd'hui |
| RPR-08 | corrigée | migration `20261214130000` (+ retour) : plafond global 1/3 (app_parameters et valeur de référence du catalogue), modifiable par admin/rh/paie ; surcharge par salarié (`employee_loan_caps`, motif obligatoire) ; journal `audit_events` (ancienne et nouvelle valeur) ; `create_loan` lit la surcharge. Écrans : Paramètres (rôles rh et paie autorisés) et champ « Plafond de retenue sur prêt » sur la fiche. Tests : `rpr08_plafond_pret`, `l2b_validation_admin` et `d30` alignés sur la décision |

Points ouverts : le circuit « demande de modification de constante » (`request_parameter_change`) existe toujours pour `loan_max_rate` dans le catalogue ; la décision demande de ne plus l'utiliser pour ce plafond, à retirer du catalogue si vous le confirmez. Types web régénérés (`database.types.ts`), `p_rate` de `set_employee_loan_cap` accepte `null` côté base mais le type généré l'ignore (cast commenté).

### Mise à jour du 11/11/2026 (soir) : RPR-01 à 15 traitées
| Fiche | Statut | Détail |
|---|---|---|
| RPR-01 | corrigée | refus d'envoi en revue (liste des salariés sans bulletin) + bandeau permanent sur la page d'une paie (`payroll_missing_employees`, migration `20261214140000`) |
| RPR-02 | corrigée | approbation admin et rôle paie ; test SQL. Parcours Playwright à écrire sur un mois ouvert |
| RPR-03 | corrigée | verrou par compte + adresse, limite par adresse 120/15 min, **alerte administrateur** (`security_alerts`, journal `verrouillage_connexion`, tableau de bord). Reste : verrou en mémoire (perdu au redémarrage de la passerelle) |
| RPR-04 à 09 | corrigées | voir mises à jour précédentes |
| RPR-10 | corrigée | Paramètres > Référentiels RH : gestion des départements ; champ Département sur la fiche ; `/planning` ne dépend plus de `shift_types` ni `work_posts` |
| RPR-11 | corrigée (partiel) | Entrée valide les référentiels ; plus de débordement à 1280 px ; texte d'accès exact ; lien « Créer un compte » masqué sauf `VITE_SIGNUP_ENABLED=true` (D-40) ; catégorie à 0 F affichée « minimum non renseigné ». **Données à compléter (source datée requise)** : catégorie PRESTATION (Prestations de services) et 3 catégories 1ère, 2ème, 3ème de Transports Routiers Hydrocarbures à 0 F. Les conventions sont toutes actives en base |
| RPR-12 | corrigée | refus avec code, nombre et exemple par contrôle bloquant ; fenêtre d'avertissement avant « Envoyer en revue » |
| RPR-13 | corrigée | bandeau « déclaration d'embauche non référencée » sur la fiche |
| RPR-14 | corrigée | numérotation paramétrable (préfixe, chiffres, prochain numéro), Paramètres > Société, défaut S + 4 chiffres inchangé |
| RPR-15 | corrigée | mesures : écriture de 200 lignes 130 ms en base, 40 lignes 1,3 s au navigateur, page variables 0,6 à 1,8 s ; les lenteurs de la campagne venaient du serveur de développement. Ajouts : message de progression, une seule lecture des rôles par navigation (3 à 4 requêtes avant). Incident de mesure : un serveur Vite oublié sur le port 5174 consommait le processeur (arrêté) |

Contrôles du 11/11 : tests unitaires 44/44 ; API 11/11 ; SQL 11 échecs de données manquantes (inchangés) ; e2e menu et accessibilité 19/19 ; simulation 20-roles 17/17.
Décision du propriétaire du 11/11 : `loan_max_rate` reste dans le circuit de demande de constante (non retiré du catalogue).

Prompt de reprise pour poursuivre le chantier : `docs/recette/PROMPT_REPRISE_2026-11-11.md`.

### Mise à jour du 11/11/2026 (reprise) : parcours Playwright et étape manager
- `web/e2e/sim/31-rpr-mutating.sim.spec.ts` : RPR-01/12 (bandeau + avertissement + refus avec la liste), RPR-04 (motif obligatoire), RPR-02 (rh refusé, même personne refusée, paie2 approuve), RPR-06, RPR-10, RPR-14. 15/15 au vert (53 s). La paie de novembre 2026 est créée (199 bulletins : S0450 est sorti le 23/10) puis supprimée (retour à « Calculée » avec motif, règle de `delete_payroll_entry`). Un échec isolé de création de la paie, non reproduit, a été observé au 3e passage. `30-rpr` garde `fixme` pour RPR-03, 05, 07, 08, 11, 13, 15 (couvertes par SQL, API et unitaires).
- Bouton « Approuver » introuvable dans `/mon-equipe` : **pas un défaut**. Le salarié de test (S0291) n'avait aucun manager affecté ; l'étape manager est « Ignorée » et la demande attend à l'étape RH. `LeaveApprovals` ne s'affiche que s'il existe une demande à décider pour ce manager. Le congé de test (« eere r ») est supprimé.
- Statut « Actif » après une date de sortie (S0450, sortie 23/10) : **conforme à la conception**. Le statut passe à « Left » par le processus de sortie (solde de tout compte), pas par l'enregistrement de la date sur la fiche.
- `scripts/check-migrations.sh` signale des préfixes en double (20261204090000, 20261206090000, 20261207090000, 20261208090000) : antérieurs au chantier, à traiter ou à ajouter à la liste d'exceptions.

Prompt pour rejouer la simulation sur une base remise à zéro, en parallèle : `docs/recette/PROMPT_PARALLELE_PALIER_10_PARTIE_2.md`.
