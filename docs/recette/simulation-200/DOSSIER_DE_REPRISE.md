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
