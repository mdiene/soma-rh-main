# Journal des paliers — simulation 10 → 200 salariés

Base : SOMA-RH locale remise à zéro (compte mdiene conservé). Navigateur intégré, rôle admin (mdiene).
Convention de statut : VERT = conforme ; ROUGE = écart ; ORANGE = contournement ou point à arbitrer.

## Palier 1 — janvier 2026, 10 salariés (Commerce) — 09/11/2026

Parcours réalisé par l'interface : référentiels, 10 fiches, affectation de structure, calcul, revue, approbation, validation, paiement, clôture.
Résultat : 10 bulletins, brut 1 065 218 F, retenues 166 898 F, indemnités 260 000 F, net 1 158 320 F, charges patronales 258 829 F, masse salariale 1 584 047 F. Totaux cohérents (brut − retenues + indemnités = net). Période Clôturée.

| Réf | Constat | Statut |
|---|---|---|
| P1-01 | 3 conventions (BTP, Commerce, Industries hôtelières) désactivées en base (test du 29/10). Liste de la fiche salarié n'en montre que 8. Réactivées via Paramètres > Référentiels RH. | ORANGE |
| P1-02 | Référentiel Conventions : boutons d'action hors écran à 1280 px (défilement horizontal). | ROUGE (ergonomie) |
| P1-03 | Formulaire d'ajout d'un référentiel : la touche Entrée ne valide pas. | ROUGE (mineur) |
| P1-04 | Aucun écran de gestion des départements (table `departments` vide, pas de champ sur la fiche). | ORANGE |
| P1-05 | Convention « Prestations de services » : 1 seule catégorie à 0 F, inutilisable. | ROUGE (données) |
| P1-06 | Création d'un salarié n'affecte aucune structure salariale. Le calcul répond « Aucune structure salariale affectée » côté API mais le traitement passe en Calculée avec 0 bulletin, sans message visible. | ROUGE |
| P1-07 | Affectation de structure : date par défaut = mois courant (novembre 2026), donc ignorée par un calcul de janvier si on ne la change pas. | ROUGE (piège) |
| P1-08 | Validation de la paie exige la déclaration d'embauche (référence + date). Garde-fou légitime mais découvert seulement à la validation ; le formulaire de création n'en parle pas. | ORANGE |
| P1-09 | Validation directe Calculée → Validée : la règle D-43 refuse (« motif de dérogation obligatoire ») mais le dialogue n'a pas de champ motif. Le chemin Revue → Approbation propose bien la dérogation avec motif. | ROUGE (UI) |
| P1-10 | Dialogue de dérogation : le champ motif est pré-rempli avec le message d'erreur (« … ne peut pas la approuver »), faute d'accord. | ROUGE (mineur) |
| P1-11 | Salariée entrée le 15/01 (S0299) payée à plein tarif, sans prorata (D-56, décision en attente). | ORANGE |
| P1-12 | Période passée à Payée puis Clôturée sans qu'aucun paiement individuel (`salary_payments`) ne soit enregistré. | ORANGE (à confirmer) |
| P1-13 | Texte de Paramètres > Accès : « Les comptes se créent depuis l'écran de connexion » alors que l'inscription est fermée (D-016). | ROUGE (texte) |
| P1-14 | Matricules démarrent à S0291 (numérotation non remise à zéro). | ORANGE |
| P1-15 | Tables `shift_types` et `work_posts` absentes (à vérifier sur /planning). | À VÉRIFIER |
| P1-16 | Contrôles avant validation : 10 alertes « aucune variable du mois » (attendu, aucun salarié n'a d'absence ni d'heures supplémentaires). | VERT |
| P1-17 | Workflow Calculée → En revue → Approuvée → Validée → Payée → Clôturée avec bulletins en Validé. | VERT |

## Tests de droits par rôle (comptes sim-*, API avec jeton de chaque compte) — 09/11/2026

Liaisons faites par l'interface : sim-sal-1/2/3 → S0295/S0296/S0297 ; sim-mgr-1 → S0293, équipe S0295 et S0296.

| Réf | Test | Résultat |
|---|---|---|
| R-01 | Connexion des 20 comptes sim-* | VERT (20/20) |
| R-02 | sal-1 / sal-2 : voient 1 fiche et 1 bulletin (les leurs) ; sal-4 non lié : 0 | VERT |
| R-03 | mgr-1 : 3 fiches (soi + 2 équipiers), 1 bulletin (le sien) ; mgr-2 non lié : 0 | VERT |
| R-04 | sal-1 modifie sa fiche ou celle d'un autre : 200 mais 0 ligne modifiée (refus silencieux) | VERT |
| R-05 | rh modifie une fiche : accepté | VERT |
| R-06 | sal-1 et mgr-1 lancent le calcul de paie : « rôle paie ou rh requis » | VERT |
| R-07 | paie relance le calcul d'une période clôturée : « paie clôturée immuable » | VERT |
| R-08 | Plafond de retenue : rh et paie refusés (« rôle admin requis … demande de modification de constantes ») alors que le besoin est admin, RH ou paie | ROUGE |
| R-09 | La fonction en base ne correspond pas au fichier de migration du dépôt (le fichier autorise admin, rh, paie) | ROUGE (à expliquer) |

## Palier 2 — février 2026, 25 salariés (Commerce, BTP, Hôtelières, Sécurité privée) — 09/11/2026

15 salariés créés par l'interface (fiche, déclaration d'embauche, structure : chaîne complète en un passage). Variables saisies à l'écran : HS 15 % 8 h (S0294), absence 16 h (S0296), paniers 10 (S0300), prime 50 000 F (S0292), retenue 20 000 F (S0297). Calcul des 25 bulletins puis workflow complet jusqu'à Clôturée (dérogation motivée admin aux étapes d'approbation).

| Réf | Contrôle | Résultat |
|---|---|---|
| P2-01 | HS 15 % : 8 h × taux horaire 667,6 × 1,15 = +6 142 F au brut de S0294 | VERT |
| P2-02 | Absence 16 h : brut 75 361 → 68 404 F (prorata 16/173,33) pour S0296 | VERT |
| P2-03 | Prime 50 000 F : brut 132 498 → 182 498 F (S0292) | VERT |
| P2-04 | Retenue 20 000 F : net 97 348 → 77 348 F sans changement du brut (S0297) | VERT |
| P2-05 | Paniers 10 : net +11 116 F sans changement du brut (S0300), indemnité non imposable | VERT |
| P2-06 | Salarié sans variable (S0291) : bulletin identique à janvier | VERT |
| P2-07 | Workflow février Calculée → … → Clôturée sans refus | VERT |

## Palier 3 — mars 2026, 50 salariés (+5 conventions : transport hydrocarbures, pétrole et gaz, mécanique, alimentaire, chimie) — 09/11/2026

Incident de séquencement (mon script) : mars a d'abord été calculé et clôturé avec 25 salariés avant la saisie des 25 embauches du 1er mars. Cela a permis de tester la réouverture.

| Réf | Constat | Statut |
|---|---|---|
| P3-01 | Réouverture d'une période clôturée : motif obligatoire (5 caractères), statut Réouverte, journalisée | VERT |
| P3-02 | Période Réouverte : le message annonce « pourra être recalculée ou supprimée » mais la page n'offre ni bouton Recalculer ni Calculer ; seuls Annuler et Supprimer sont proposés. Contrôles : 25 erreurs pour les 25 nouveaux salariés sans bulletin. | ROUGE |
| P3-03 | « Annuler le traitement » marque les bulletins Annulé et autorise un nouveau traitement du mois | VERT |
| P3-04 | Nouveau traitement de mars : 50 bulletins calculés, 0 erreur, workflow complet jusqu'à Clôturée | VERT |
| P3-05 | 25 salariés créés par l'interface sur 5 conventions supplémentaires, structures affectées, déclarations d'embauche saisies | VERT |

## Palier 4 — avril 2026, 75 salariés (11 conventions) — 09/11/2026

25 embauches du 1er avril créées par l'interface sur les 11 conventions (chaîne fiche + déclaration d'embauche + structure). Calcul : 75 bulletins, 0 erreur, 75 alertes « aucune variable » (attendu). Workflow complet jusqu'à Clôturée sans refus.

| Réf | Constat | Statut |
|---|---|---|
| P4-01 | 75 bulletins calculés sans erreur sur 11 conventions | VERT |
| P4-02 | Workflow avril Calculée → Clôturée | VERT |
| P4-03 | Outillage : les temporisations de la page du navigateur intégré sont gelées quand aucun script n'est en cours ; l'automatisation avance lentement (environ 7 à 10 s par salarié). À rejouer proprement par Playwright (specs `web/e2e/sim/`) pour les paliers suivants. | NOTE |

## Incident de connexion Playwright — 09/11/2026 16:13

| Réf | Constat | Statut |
|---|---|---|
| X-01 | Après environ 45 connexions en 20 minutes depuis la même adresse (20 comptes testés à l'API, 2 × 9 connexions Playwright), l'API répond « Compte verrouillé suite à trop d'échecs, réessayez dans N secondes » à **tous** les comptes, y compris ceux dont le mot de passe est correct. Le verrouillage est porté par l'adresse source (D-58), pas par le compte : un seul poste peut bloquer toute l'entreprise 30 minutes. | ROUGE (sécurité / disponibilité, lié à D-58) |
| X-02 | Correctif outillage : `sim.setup.ts` réutilise les sessions enregistrées encore valables au moins 10 minutes au lieu de se reconnecter à chaque exécution. | OUTILLAGE |

## Palier 5 (Playwright) — constats du 09/11/2026 16:20

| Réf | Constat | Statut |
|---|---|---|
| P5-01 | Section « Structure salariale » en lecture seule pour le compte RH, sans message : l'affectation relève de la paie ou de l'admin. Création d'un salarié = deux métiers. | ORANGE |
| P5-02 | Affectation de structure enregistrée avant la fin du chargement : erreur brute « null value in column structure_id of relation salary_structure_assignments violates not-null constraint » affichée à l'utilisateur ; le bouton Enregistrer devrait rester inactif tant que la structure n'est pas chargée. | ROUGE |

## Palier 5 (Playwright) — workflow à comptes distincts, 09/11/2026 16:30

| Réf | Constat | Statut |
|---|---|---|
| P5-03 | Envoi en revue par sim-paie : accepté, statut En revue | VERT |
| P5-04 | Le compte RH (sim-rh2) ne voit pas le bouton « Approuver la paie » sur la page Gouvernance, alors que la fonction `transition_payroll_entry` autorise le rôle rh à approuver (D-43). Les boutons d'étape ne s'affichent que pour `can('paie')` (PayrollGovernancePage.tsx, ligne 157). Écran et base ne sont pas alignés : le RH ne peut pas exercer son rôle d'approbateur. | ROUGE |
| P5-05 | Pour poursuivre, l'approbation est confiée à un second compte paie (sim-paie2). | CONTOURNEMENT |

## Palier 5 (Playwright) — approbation, 09/11/2026 16:34

| Réf | Constat | Statut |
|---|---|---|
| P5-06 | Approbation par un second compte paie (sim-paie2) : sans effet, la paie reste En revue. La fonction exige le rôle rh pour « Approuvée » (db/migrations/20261107120000_d43…, ligne 33) alors que l'écran n'affiche le bouton qu'aux comptes paie ou admin. Aucun profil à un seul rôle ne peut donc approuver depuis l'application : il faut soit le cumul rh + paie, soit la dérogation admin. | ROUGE (blocage de la séparation des tâches) |
| P5-07 | Contournement de test : approbation par sim-rhpaie (rôles rh + paie), distinct du compte qui a envoyé en revue. | CONTOURNEMENT |

## Palier 5 — blocage à l'approbation, 09/11/2026 16:45

| Réf | Constat | Statut |
|---|---|---|
| P5-08 | Approbation par sim-rhpaie : refusée avec « Validation impossible : 1 contrôle(s) bloquant(s) doit/doivent être résolu(s) ». Cause : le salarié S0375 n'avait pas de structure salariale (erreur de mon test : un enregistrement de structure perdu). Le message du refus ne dit pas quel contrôle bloque ; il faut ouvrir « Contrôler » pour le savoir. | ORANGE |
| P5-09 | « Envoyer en revue » est accepté alors qu'un contrôle bloquant existe ; seul l'approbation le refuse. | ORANGE |
| P5-10 | Reprise : structure de S0375 affectée, retour En revue → Calculée par l'admin (« Remettre en Calculée », motif), recalcul : 100 bulletins, 0 erreur. Les boutons Recalculer et Remettre en Calculée fonctionnent sur une paie non clôturée. | VERT |

## Palier 5 — garde de période, 09/11/2026 16:50

| Réf | Constat | Statut |
|---|---|---|
| D-64 | `payroll_entry_period_guard` : pour valider le mois M, un compte non administrateur exige que le mois M-1 soit exactement « Validée ». Dès que M-1 passe Payée ou Clôturée (cas normal), la validation de M est refusée (« le mois précédent (04/2026) n'est pas validé »). Toute entreprise sans compte admin à chaque clôture est bloquée dès le deuxième mois. Correctif : migration `20261109170000_d64_garde_periode_mois_precedent.sql` (+ rollback + test `tests/sql/d64_garde_periode.sql`), à appliquer. | ROUGE (blocage) |

## Paliers 5 et 6 (Playwright), 09/11/2026 17:00

Après correction D-64 appliquée : palier 5 (mai, 100 salariés) et palier 6 (juin, 125 salariés, 125 bulletins) rejoués intégralement avec comptes distincts : paie envoie en revue, rhpaie approuve, paie valide et paye, admin clôture. Les deux paliers passent à Clôturée.

| Réf | Constat | Statut |
|---|---|---|
| P6-01 | Palier 6 : 25 embauches (compte RH) + structures (compte paie) + variables + calcul 125 bulletins + workflow à comptes distincts jusqu'à Clôturée | VERT |
| P7-01 | Palier 7 : à la dernière embauche, le message « Fiche enregistrée » n'apparaît pas dans les 5 secondes alors que la déclaration d'embauche est bien enregistrée en base ; la structure de ce salarié (S0436) n'a pas été affectée (test interrompu). | ORANGE |

## Palier 7 et début du palier 8 — 09/11/2026 17:10

Palier 7 (juillet, 150 salariés) : VERT, de bout en bout (reprise automatique des structures manquantes, embauches, variables, calcul, workflow à comptes distincts, clôture).

| Réf | Constat | Statut |
|---|---|---|
| P8-01 | Variables du mois à 175 salariés : après « Enregistrer », le bouton reste désactivé (« Enregistrer (3) ») et la confirmation « enregistrées » met plus de 5 secondes à paraître. Aucun indicateur de progression. À mesurer (lenteur d'écriture ligne par ligne ?). | ORANGE (performance) |

## Paliers 8 et 9 — 09/11/2026 17:30

Paliers 8 (août, 175) et 9 (septembre, 200 salariés) : VERT de bout en bout. Croissance 10 → 200 salariés terminée, périodes 2026-01 à 2026-09 clôturées. Run Playwright complet : 14 passés (5,1 min).

| Réf | Constat | Statut |
|---|---|---|
| P9-01 | Premier chargement de /paie/variables à 200 salariés > 30 s lors d'un run (puis normal au run suivant). À surveiller : lenteur ou serveur de dev saturé. | ORANGE (performance) |

## Palier 10 — octobre 2026, 200 salariés (10/11/2026, v3)

Base conservée (aucune remise à zéro). Sauvegarde préalable : `backups/soma-rh-20261110-191512.dump` (restauration : `scripts/local-restore.ps1`). Spec : `web/e2e/sim/11-octobre.sim.spec.ts`.

| Réf | Constat | Statut |
|---|---|---|
| P10-01 | Sortie par la fiche (S0450, démission le 23/10) : date et motif enregistrés ; message « Fiche enregistrée » non vérifié ; statut resté « Actif ». | VERT / ORANGE |
| P10-02 | Congé : dotation 24 j (RH), demande salarié (état Ouverte), approbation RH (état Approuvée). L'approbation par le manager n'a pas pu être rejouée : bouton Approuver absent de /mon-equipe pour cette demande. | VERT / ORANGE |
| P10-03 | Prêt de 300 000 F sur 6 échéances refusé (50 000 F > plafond 45 709 F = 33,0 % du brut 138 513 F) avec message clair ; accepté sur 12 échéances ; retenue de 25 000 F au bulletin d'octobre (net 142 473 → 117 473). | VERT |
| P10-04 | Heures supplémentaires : S0294, 10 h à 15 % = 7 677,44 F, identique au recalcul manuel (115 718 ÷ 173,33 × 1,15 × 10). Prime de 50 000 F (S0298) au bulletin. | VERT |
| P10-05 | Calcul de 200 bulletins : 18 s ; workflow à comptes distincts jusqu'à Clôturée. | VERT |
| P10-06 | **Prorata à la sortie** : S0450 sort le 23/10, bulletin d'octobre au mois entier (salaire de base 70 709 F, identique à septembre). `compute_salary_slip` ne contient aucun prorata (D-56 non implémentée). | ROUGE (RPR-09) |
| P10-07 | Un congé annuel de test (S0291, 19 j du 14/11 au 02/12, motif « eere r ») était en attente avant ce palier : reste d'un test antérieur, à supprimer. | ORANGE |

Non joué dans ce palier : CDD et intérim, réouverture motivée, ordres de virement et déclarations (IPRES/CSS, DGID), paiements par lot. Voir le rapport final.

### Palier 10 — suites (11/11/2026)

| Réf | Constat | Statut |
|---|---|---|
| P10-01 (suite) | Le statut « Actif » après la date de sortie est conforme à la conception : il passe à « Left » par le processus de sortie (solde de tout compte), pas par la fiche. | VERT (consigné) |
| P10-02 (suite) | Bouton « Approuver » absent de `/mon-equipe` : S0291 n'avait aucun manager affecté, l'étape manager est « Ignorée », la demande attend à l'étape RH. Pas un défaut. | VERT (expliqué) |
| P10-06 (suite) | Prorata D-56 appliqué (migration `20261214090000`) ; octobre 2026 rouvert, recalculé, reclôturé : S0450 retenue de prorata 18 331,96 F, net 63 403,18 F. | VERT |
| P10-07 (suite) | Congé de test de S0291 (« eere r ») supprimé. | VERT |
| P11-01 | Paie de novembre 2026 créée pour les parcours RPR (199 bulletins : S0450 est sorti), puis supprimée après retour à « Calculée » avec motif (règle de `delete_payroll_entry`). Spec `31-rpr-mutating.sim.spec.ts` : RPR-01/12, 02, 04, 06, 10, 14, 15/15 au vert en 54 s. Un échec isolé à la création de la paie, non reproduit. | VERT / ORANGE |
| P11-02 | Connexion par téléphone, contrôle d'état : API 7/7, verrou 4/4, unitaires 45/45, SQL `connexion_telephone` OK, e2e `telephone.spec.ts` 7/7 (le salarié ne voit pas l'écran d'autorisation : un échec au 1er passage, dû au chargement lent juste après le redémarrage de la passerelle, vert au 2e). | VERT |
| P11-03 | Amélioration : adresse du client derrière un proxy (`TRUST_PROXY=1`, entrée de droite de `X-Forwarded-For` ; en-tête ignoré sinon). Sans cela, derrière un proxy toutes les connexions partageraient la limite par adresse (120 / 15 min). Test unitaire ajouté. | VERT |
| P11-04 | Les tests API partagent la limite par adresse de la passerelle : lancés ensemble ou après une campagne e2e, ils reçoivent 429. Redémarrer la passerelle avant chaque suite, une suite à la fois. | ORANGE (méthode) |
| P11-05 | `scripts/check-migrations.sh` : préfixes en double 20261204090000, 20261206090000, 20261207090000, 20261208090000 (antérieurs au chantier). | ORANGE |

Reste à jouer (palier 10, partie 2) : CDD et intérim, ordres de virement, états IPRES/CSS et DGID, journal comptable, rapport de clôture, paiements par lot, accès interdits par rôle, temps à 200 salariés.

### Connexion par téléphone — e2e de bout en bout (11/11/2026)
Spec `web/e2e/sim/32-telephone.sim.spec.ts` (salarié synthétique « Tel E2E », supprimé), 6 parcours au vert en 50 s : demande ; l'écran d'autorisation est réservé à l'administrateur (rh ne le voit pas) ; autorisation ; ouverture, mot de passe, connexion ; le compte téléphone ne voit ni `/paie`, ni `/salaries`, ni `/parametres` ; réutilisation refusée ; 5 mauvaises dates puis bonne date refusée ; réinitialisation ; révocation (connexion refusée) ; refus. Pas encore couvert : autorisation expirée (délai de 48 h, test SQL seulement).

### Revue du 11/11/2026 (sécurité, base de données, échecs silencieux) — corrections appliquées
Migration `20261215090000_revue_corrections.sql` (+ retour arrière, test `revue_corrections.sql`), passerelle `api/server.mjs`, fonction Edge, écrans.

| Réf | Constat | Correction | Statut |
|---|---|---|---|
| REV-01 | Validation dérogatoire (Calculée → Validée) sans contrôle des bulletins manquants | même contrôle que l'envoi en revue | VERT |
| REV-02 | `run_payroll_batch` : échec de calcul sans trace ni sqlstate, ancien bulletin brouillon conservé (périmé) | `sqlstate`, journal d'audit `calcul_bulletin_echec`, bulletin brouillon périmé écarté (le contrôle de complétude le signale) | VERT |
| REV-03 | `next_employee_number()` rappelable par tout compte connecté (consommation de la séquence) | retirée aux rôles connectés (le déclencheur est `security definer`) ; `preview_employee_number` réservée rh/paie | VERT |
| REV-04 | Devinette de la date de naissance : ~480 essais possibles en 48 h | autorisation révoquée après 10 secondes informations fausses | VERT |
| REV-05 | Corps de requête sans plafond sur les routes non authentifiées | 64 Ko, réponse 413 | VERT |
| REV-06 | Délai bcrypt différent si le compte n'existe pas (énumération par la durée) | hachage factice toujours comparé | VERT |
| REV-07 | JSON invalide traité comme `{}` ; types non texte → 500 | 400 « Corps de requête invalide » | VERT |
| REV-08 | Journal des connexions : échec = 500 sur une connexion réussie ; suppression de fichier : erreurs avalées | journal protégé et tracé ; `unlink` trace tout sauf ENOENT | VERT |
| REV-09 | Fonction Edge : erreurs `rpc` ignorées (demande perdue en silence), panne d'authentification comptée comme mot de passe faux, adresse falsifiable (entrée de gauche) | 500/503 explicites sans verrou, entrée de droite | VERT (non exécuté : Deno absent, non déployé) |
| REV-10 | Écran : réponse non JSON prise pour un succès ; réglages non chargés = case « date de naissance » affichée cochée | « Réponse inattendue », cases désactivées tant que les réglages manquent | VERT |
| REV-11 | Retour arrière de la migration téléphone bloqué par l'index `employees_phone_normalized_idx` | `drop index` ajouté | VERT |

**Non corrigé, à décider** : (a) verrou d'ouverture par numéro seul : 5 mauvaises dates bloquent l'activation de n'importe quel numéro autorisé pendant 30 min (déni de service ciblé ; le lier à l'adresse affaiblirait la défense) ; (b) verrou de connexion en mémoire, jamais purgé, perdu au redémarrage (étape 10 du prompt : table en base) ; (c) `TRUST_PROXY=1` suppose exactement un proxy et une API non joignable directement ; (d) **organigramme** : un salarié qui a un compte téléphone ne peut pas être nommé manager (le verrou de rôle lève une erreur et annule l'opération, y compris une réorganisation par lot qui le contient) ; (e) un jeton émis (8 h) survit à la désactivation du compte si `has_role` s'appuie sur une claim du jeton (à vérifier) ; (f) `phone_access_settings` : changements non journalisés ; (g) jeu de données : `decide_leave_droits` échoue désormais faute de congé en attente (j'ai supprimé le congé de test demandé par le prompt) : 12 échecs SQL de données manquantes au lieu de 11.

Contrôles : SQL 60 tests, 12 échecs (tous de données manquantes), `revue_corrections` OK ; unitaires 45/45 ; API 7/7 et 4/4 ; e2e sim 31 et 32 21/21 ; menu et a11y 19/19 (un échec isolé sur `/modules`, vert au rejeu seul) ; build et scan de données personnelles OK.

### Suites de la revue (11/11/2026, décisions du propriétaire)
- **Organigramme** : le message du verrou de rôle dit désormais quoi faire (« Ce salarié se connecte par téléphone : il ne peut pas recevoir le rôle « manager »… Créez-lui un compte e-mail (Paramètres > Accès) puis recommencez »). Le verrou lui-même est conservé.
- **Verrou de connexion en base** (étape 10, accord du propriétaire) : migration `20261215100000` (table `login_attempts`, clé hachée, fonctions `login_lock_*` réservées à `service_role`, retour arrière, test `verrou_connexion_base`). Passerelle : repli en mémoire si la base répond mal. Vérifié : 5 échecs, redémarrage de la passerelle, la tentative suivante est encore refusée (429).
- **Guide** : `docs/LOCAL_SETUP.md`, section « Passerelle derrière un proxy (`TRUST_PROXY`) ».
- Blocage d'un numéro par 5 mauvaises dates : laissé tel quel (accord).
- Incident de méthode : mes appels `curl` de contrôle ont consommé la limite de demandes par numéro (3 par 24 h) et fait échouer `connexion_telephone` ; traces supprimées. Éviter des numéros réels de test hors des specs.

### Étape 9 — mise en ligne (12/11/2026)
| Réf | Constat | Statut |
|---|---|---|
| MEL-01 | Migrations `20261214090000` à `20261215100000` appliquées sur le projet distant (4 par l'outil, 6 par `scripts/supabase-appliquer.ps1` chez le propriétaire : l'outil `apply_migration` est refusé en session non interactive). Contrôle : plafond de prêt 0,333333, `RET_PRORATA` présente, `login_attempts` et `employee_loan_caps` créées, `next_employee_number` non appelable par un compte connecté, fonctions `login_lock_*` non appelables par `anon`/`authenticated`. 27 salariés, 0 paie : aucune donnée touchée. | VERT |
| MEL-02 | Alertes de sécurité Supabase : 4 (INFO RLS sans politique ; WARN extension dans `public` ; WARN fonctions `security definer` appelables par un compte connecté, 133 sur 160, aucune par `anon` ; WARN protection contre les mots de passe compromis désactivée). Le détail par objet n'est pas fourni par l'outil. | ORANGE |
| MEL-03 | Fonction Edge `phone-auth` déployée (version 1, `verify_jwt` désactivé). **Défaut trouvé et corrigé avant déploiement** : la pré-vérification CORS répondait `204` avec un corps, ce que Deno refuse ; sans correction, le téléphone en ligne n'aurait jamais fonctionné depuis le navigateur. Vérifié en ligne : OPTIONS 204 avec en-têtes CORS, corps invalide 400, GET 405. | VERT |
| MEL-04 | Reste à faire par le propriétaire : secret `PHONE_AUTH_PEPPER`, réinitialisation du mot de passe de la base, URL de redirection, protection contre les mots de passe compromis, `scripts/vercel-deploy.ps1`. Tant que le secret n'est pas posé, les routes `login` et `set-password` échouent ; ne pas annoncer la fonctionnalité aux salariés. Test réel de bout en bout contre Supabase : à faire après le secret. | À FAIRE |

### Test réel de bout en bout contre Supabase (12/11/2026, accord du propriétaire)
Fiche synthétique « Tel E2E » (numéro fictif), fonction Edge `phone-auth` en ligne, secret `PHONE_AUTH_PEPPER` posé par le propriétaire.

| Réf | Constat | Statut |
|---|---|---|
| MEL-05 | Demande : numéro connu et inconnu, réponse identique (200). | VERT |
| MEL-06 | Ouverture : mauvaise date refusée (message neutre), bonne date : jeton. Mot de passe trivial refusé (422), valide accepté, jeton réutilisé refusé (400). Création du compte par l'API admin avec le mot de passe dérivé de 64 caractères : fonctionne. | VERT |
| MEL-07 | Connexion : mauvais mot de passe 400, bon mot de passe : jetons de session. | VERT |
| MEL-08 | Isolation avec le jeton du compte téléphone : ne voit que sa fiche, 0 paie, 0 bulletin, rôle `salarie` seul ; RPC d'autorisation refusée (« Réservé aux administrateurs ») ; `next_employee_number` et `login_lock_fail` : 403. | VERT |
| MEL-09 | Révocation : compte banni, rôles retirés, fiche déliée ; l'ancien jeton, encore valide, ne lit plus ni la fiche ni les rôles (coupure immédiate). | VERT |
| MEL-10 | **Défaut trouvé** : `banned_until = 'infinity'` fait échouer le service d'authentification de Supabase (« unsupported Scan … banned_until ») : toute connexion du compte révoqué renvoyait 503 « Service indisponible » au lieu de 400, et la réactivation risquait d'échouer. Corrigé : migration `20261215110000_phone_ban_date_finie.sql` (date lointaine finie, 100 ans) ; hypothèse vérifiée en ligne sur le compte de test (400 normal après correction manuelle de la date). Migration à appliquer en ligne. | ROUGE → corrigé (à appliquer) |
| MEL-11 | Réinitialisation après révocation : nouvelle demande (objet `reset`), autorisation, ouverture, nouveau mot de passe : l'ancien est refusé (400), le nouveau fonctionne. | VERT |
| MEL-12 | L'autorisation par l'administrateur a été simulée en SQL (l'écran admin n'est pas joignable sans session admin en ligne) ; le parcours d'écran est couvert en local. | ORANGE |
| MEL-13 | **Nettoyage en ligne refusé** par le système de permissions (suppressions) : la fiche TEL-E1, le compte `221700005100@tel.soma-rh.invalid`, ses demandes et tentatives restent en ligne. À supprimer par le propriétaire (SQL fourni). | À FAIRE |

### Clôture de l'étape 9 (12/11/2026)
Actions du propriétaire confirmées : migration `20261215110000` appliquée en ligne, données de test supprimées, mot de passe de la base changé, URL de redirection saisie, `scripts/vercel-deploy.ps1` terminé sans erreur.
Vérifié en lecture seule : en ligne, 27 salariés, 0 fiche de test, 0 compte téléphone, 0 demande, 0 tentative, 0 compte banni avec `infinity`, fonction `phone_access_disable` à jour (bannissement à 100 ans), 0 paie ; `https://soma-rh.vercel.app` répond 200 et son bundle contient l'URL de la fonction `phone-auth` et le projet Supabase, aucune clé `service_role`.
| Réf | Constat | Statut |
|---|---|---|
| MEL-14 | Mise en ligne : base, fonction Edge et site Vercel cohérents ; test réel de bout en bout validé (MEL-05 à MEL-11). | VERT |
| MEL-15 | Protection contre les mots de passe compromis : non confirmée par le propriétaire (alerte Supabase `auth_leaked_password_protection`). | À CONFIRMER |
| MEL-16 | Parcours téléphone joué depuis le site en ligne, dans un navigateur : non fait (seul l'appel direct à la fonction a été testé). Revue des 133 fonctions `security definer` appelables par un compte connecté : non faite une à une. | À FAIRE |

### Revue du lot conformité et cotisations (12/11/2026) — corrections
Revues base de données et sécurité du commit `e68ddcf` (migration `20261216090000`, page `/paie/cotisations`, fiche du constat). Aucun constat critique. Corrigé par la migration `20261216100000_cotisations_corrections_revue.sql` (+ retour arrière, test `cotisations_corrections`) et de petites retouches d'interface.

| Réf | Constat | Correction | Statut |
|---|---|---|---|
| COT-01 | Concurrence : deux caisses validées en même temps laissaient le mois « non versé » | verrou par mois (`pg_advisory_xact_lock`) | VERT |
| COT-02 | Un versement saisi à la main dans `contribution_payments` était supprimé (ligne IPM) ou écrasé | seules les lignes créées par le suivi sont modifiées ou retirées ; caisses hors échéancier sans effet | VERT |
| COT-03 | Changement de mois d'une ligne : ancien mois périmé | resynchronisation de l'ancien et du nouveau mois | VERT |
| COT-04 | La vue `v_contribution_follow` laissait un salarié lire ses propres cotisations (part patronale comprise) | filtre rh/paie pour les rôles d'API ; propriétaire et administration voient tout (sinon la synchronisation lisait une vue vide, défaut trouvé par le test) | VERT |
| COT-05 | Bornes de longueur manquantes, `?mois=` non validé, date de paiement future, liens non encodés, liste de contrat sans valeur vide | contraintes (référence 100, note 500), `max`, `maxLength`, `encodeURIComponent`, option vide | VERT |
| COT-06 | Retour arrière laissait les versements de synchronisation | suppression des lignes « Suivi des versements par caisse » | VERT |
| COT-07 | Nom de caisse libre : une faute de frappe crée une ligne orpheline | non corrigé : liste fermée non ajoutée (valeurs à confirmer avec le propriétaire) | ORANGE |
Contrôles : SQL 63 tests, mêmes 12 échecs de données manquantes, `cotisations_corrections` et `cotisations_versements` OK ; types et build OK ; menu et accessibilité 19/19 (un premier passage a échoué parce que le serveur de développement s'était arrêté ; relancé, 19/19).

### Mise en ligne des migrations cotisations (12/11/2026)
Migrations `20261216090000` et `20261216100000` appliquées en ligne par le propriétaire. Vérifié en lecture seule : table et vue présentes, vue filtrée par rôle, verrou par mois dans la synchronisation, 2 contraintes de longueur, vue non lisible par `anon` ; 27 salariés, 0 versement, 0 ligne de suivi (aucune donnée touchée). Toutes les migrations de la branche sont désormais appliquées en ligne.

## Palier 11 — rejeu complet sur base remise à zéro et guide utilisateur (12/11/2026)
Base remise à zéro (sauvegarde `backups/soma-rh-20261112-153339.dump`), 20 comptes `sim-*` recréés, puis tout rejoué avec captures. Résultats : `resultats-playwright.jsonl` (lignes du 12/11), `MATRICE_UC.md`, `matrice.csv`.

| Bloc | Parcours | Résultat |
|---|---|---|
| A | Emplois (23), écran de connexion, liaison comptes/fiches | VERT |
| B | Embauche CDI/CDD/COD/STAGE/PRESTATION, RIB, sortie et certificat de travail | VERT (APPRENTISSAGE non rejoué) |
| D | Congé : dotation, demande, étape manager (`sim-mgr-1`) puis RH | VERT — ORANGE du palier 10 clos |
| E | Paliers 5 à 9 (100 → 200 salariés), octobre, prêt (plafond refusé puis accordé), réouverture et recalcul (1 ligne RET_PRORATA), simulateur | VERT |
| F | Livre de paie, résumé des cotisations, charges patronales, écritures comptables, suivi des cotisations (lecture) | VERT |
| G | Conformité (e2e 7/7, sans captures dédiées) | VERT |
| I, J | 41 écrans par rôle ; pages autorisées et refusées ; isolation du salarié | VERT |
| A (phone) | Accès par téléphone : demande, autorisation, usage unique, 5 dates fausses, réinitialisation, refus | VERT 6/6 |

Non joué : heures supplémentaires et vacations, planning (saisie), absences exceptionnelles/maladie/maternité, saisie des versements, ordres de virement, paiements par lot (BLOQUÉ : fonction absente), ayants droit/avenant/mutation, simulation de réorganisation, 7 fiches RPR en `fixme`.

Aucun ROUGE, aucune régression par rapport au palier 10. Intermittence ORANGE : section « Structure salariale » parfois absente (RPR-16). Défaut corrigé avec accord du propriétaire : images du guide en 403 sur le serveur de développement (RPR-17).
Contrôles : unitaires 54/54, `npm run check` 0 erreur, build OK, menu 12/12, accessibilité 10/10, onglet Documentation 2/2. SQL : 63 tests, 14 échecs dont la majorité de données de scénario absentes (la dernière campagne en comptait 12 sur l'ancienne base) : à rejouer sur un scénario QA. `verify-payroll.ps1` : écart attendu (référence de 26 bulletins, base à 175/200), référence non réenregistrée.

### Saisie des salariés, menu, À propos (13/11/2026) — branche `feat/saisie-salarie-menu-apropos`
Migration `20261217090000_saisie_salarie_cni_noms_brouillons.sql` (+ retour arrière, tests `saisie_salarie` et `moteur_reference_2026`), assistant et fiche salarié, menu latéral, rubrique « À propos », documentation.

| Réf | Demande | Réalisation | Statut |
|---|---|---|---|
| SAI-01 | N° CNI ou passeport obligatoire et unique | Assistant : obligatoire (écran et fonction `create_employee_from_wizard`), doublon refusé avec le matricule concerné ; index unique partout (espaces et casse ignorés) ; saisie complète : obligatoire à la création ; fiches anciennes sans numéro : alerte rouge non bloquante (les 210 salariés de simulation n'en ont aucun, l'imposer à toute modification les bloquerait). Décision à confirmer. | VERT / ORANGE |
| SAI-02 | Majuscule à la première lettre du prénom et du nom, le reste en minuscule | Fonction `person_name` + déclencheur (création et modification du champ), aperçu à la sortie du champ ; appliqué aussi au nom de jeune fille, à la mère et au père. Une modification d'un autre champ ne retouche pas les anciens noms. | VERT |
| SAI-03 | Nom de jeune fille pour les femmes ; nom et prénom de la mère | Colonnes `maiden_name`, `mother_first_name`, `mother_last_name` ; le nom complet historique `mother_name` est composé à l'enregistrement. | VERT |
| SAI-04 | TRIMF et IR : calcul automatique, mémo des formules, saisie manuelle avec alerte rouge | Interprétés comme les **parts** TRIMF et IR (règle jusque-là « à fournir » dans le code) : règle du document de référence 2026, calcul automatique tant que non modifiées, mémo visible sous les champs, alerte rouge et bouton « Appliquer le calcul automatique » si écart ; mêmes règles sur la fiche. **Règle à confirmer auprès du texte de loi** (ambiguïté du document : « marié(e) = 1,5 » puis « conjoint sans revenu = +0,5 » interprété comme 2 parts avec un conjoint à charge). | VERT / ORANGE |
| SAI-05 | Accord du moteur avec le document de référence | Test SQL `moteur_reference_2026` : les 3 cas de validation du PDF (IR 59 500 / 272 438 / 282 361, TRIMF 1 000 / 6 000 / 6 000) concordent exactement avec `compute_income_tax` et `compute_trimf`. Aucun code du PDF n'a été repris (le moteur existant suffit). | VERT |
| SAI-06 | Mettre la saisie en attente et la reprendre | Table `employee_drafts` (RLS : l'auteur, et l'administrateur), bouton « Mettre en attente », page « Saisies en cours » (avancement, points à déterminer, reprise au clic, suppression), compteur sur la page Salariés. | VERT |
| MEN-01 | Menu déployé au survol ou au clic, refermé au clic ou à la sortie de la souris, bouton pour l'épingler | Par défaut non épinglé (rail d'icônes, volet au survol) ; épingle en bas du rail et dans le volet ; « Désépingler » dans le volet déployé ; Échap et clic extérieur ferment. | VERT |
| MEN-02 | Menu « À propos » | Dernier espace : Aide et guide utilisateur (déplacée), À propos (version, build, support), Tarification et services, Conditions d'utilisation, Politique de confidentialité, Sauvegardes et versions. Contenus juridiques et commerciaux : **versions de travail à valider** ; aucun tarif ni coordonnée inventés (support configurable par variables d'environnement). | VERT / ORANGE |
| MEN-03 | Numérotation des versions | Version 1.0.0 introduite avec cette livraison ; l'historique antérieur est listé par date, sans numéros rétroactifs. | VERT |

Tests : unitaires 70/70 ; SQL (nouveaux et adaptés) OK ; menu et accessibilité (dont les nouvelles pages et le survol) ; guide 7/7 ; simulation : `33-saisie-salarie` 3/3, `60-assistant` 4/4, `61-assistant-lot2` 5/5 ; build et types OK.
Constats : (1) les specs `41-embauches` et `52-divers` (héritées) créaient des salariés sans n° de pièce : adaptées ; (2) la base locale avait été refaite par ailleurs (salariés à partir de mai 2026) : `connexion_telephone`, `l5_batch` et `rpr09_prorata` échouent désormais pour des raisons de données (vérifié : mêmes échecs sans ma migration) ; (3) `localhost` ne répond plus vers Docker Desktop en IPv6 : le proxy de développement vise `127.0.0.1`.
