# SOMA-RH — Batterie de tests de recette (réutilisable)

Version 1 — 05/11/2026. Issue de la recette « simulation 100 salariés » du 04/11/2026
([résultats](RESULTATS_SIMULATION_100_2026-11-04.md), [tâches et recommandations](TACHES_ET_RECOMMANDATIONS_RECETTE.md)).

Objectif : rejouer la recette à l'identique après correctifs, et vérifier que chaque défaut D-xx est corrigé (section 9).
Chaque test a un identifiant stable, une action, un résultat attendu (**comportement cible**, donc après correction pour les
défauts connus) et la référence du défaut qu'il surveille. Résultat à noter : PASS / FAIL / NON TESTÉ, avec la date et la version.

## 0. Préparation

1. Sauvegarde : `backups/soma-rh-AAAAMMJJ-HHMMSS.dump` avant toute campagne (`scripts/` de sauvegarde). Noter le nom du fichier.
2. Services : `docker compose up -d postgres postgrest api`, puis `cd web && npm run dev` (http://localhost:5173, API :8000).
3. Jeu de données : `scripts/qa-reset-scenario.ps1 -Scenario pme-100` (100 salariés QA, 8 services, comptes qa-admin, qa-rh, qa-paie,
   qa-manager QA0013, qa-salarie QA0011, qa-salarie2 QA0012). Identifiants dans `tests/.env.qa` (jamais commité, jamais recopié ici).
4. Hiérarchie : poser les liens managers dans /equipes (98 liens), rattacher les 8 services QA aux 8 directions QA
   (Organigramme › Directions › menu de l'unité › Modifier › « Dépend de »).
5. Les 26 salariés réels (S00xx) cohabitent dans la base : ne rien y modifier sans nécessité (D-17, D-22).
6. Période de test paie : un mois passé inexistant (ex. Décembre 2025) et un mois futur (ex. Décembre 2026). Ne jamais toucher aux mois réels validés.
7. Navigateur intégré : `confirm()`/`prompt()` natifs non pris en charge (D-07, D-13) ; sinon les surcharger. Appels JS < 45 s.
8. Après toute migration : recharger PostgREST ; après toute modification de `compute_salary_slip` : `scripts/verify-payroll.ps1`.

## 1. Tests automatisés existants à relancer d'abord
| Famille | Commande / fichier | Attendu |
|---|---|---|
| API | `tests/api/isolation.test.mjs`, `routes.test.mjs`, `workflow.test.mjs` | tout vert |
| SQL | `tests/sql/*.sql` (payroll_separation, payroll_revert, l6_conges, organigramme, equipe_presence, l8_reglement…) | aucune assertion en échec |
| Paie | `scripts/verify-payroll.ps1` | non-régression : empreinte (brut, net, nombre de bulletins) identique à la référence `backups/payroll-baseline-AAAA-MM.json` |
Ajouter à terme un test SQL/API pour chaque ligne de la section 9.

## 2. Bloc A — Accès par rôle
| ID | Rôle | Action | Attendu |
|---|---|---|---|
| A-01 | salarié | Menu | Mon espace, Organigramme, Congés, Mes bulletins uniquement |
| A-02 | salarié | URL directes /equipes, /equipes/simulation, /mon-equipe, /salaries, /demandes, /parametres, /paie | Redirection vers /mon-espace, aucune donnée |
| A-03 | manager | Menu et /mon-equipe | « Mon équipe » accessible ; aucun accès /salaries, /paie |
| A-04 | rh | 9 adresses directes | /equipes, /simulation, /organigramme, /salaries, /demandes, /parametres accessibles ; /mon-equipe → tableau de bord |
| A-05 | paie | 9 adresses directes | /equipes, /equipes/simulation, /mon-equipe, /demandes refusées ; décider si Salariés/Organigramme/Paramètres sont voulus |
| A-06 | paie | Paramètres › Référentiels RH, Journal | Rien d'inapproprié exposé |
| A-07 | tous | Menu juste après connexion | Pas d'entrées ni de « aucun rôle attribué » transitoires (D-10) |
| A-08 | admin | Paramètres › Accès | Liste des comptes et attribution des rôles |

## 3. Bloc B — Manager (« Mon équipe »)
| ID | Action | Attendu |
|---|---|---|
| B-01 | Ouvrir la page | Calendrier du mois, soldes, présence 30 jours |
| B-02 | Saisir (compte rh, Présences) 3 absences ≥ la date d'affectation puis 20 h sup. | Valeur en orange à ≥ 3 absences et ≥ 20 h sup. |
| B-03 | Ligne sans « Présent » cochée (heures sup., maladie) | Ne compte pas une absence non justifiée (D-35) |
| B-04 | Historique avant la date d'affectation au manager | Comportement documenté ou historique conservé (D-34) |
| B-05 | Périmètre | Seuls les salariés affectés (QA0011 oui, QA0012 non) |
| B-06 | Montants, prêts, bulletins | Aucun montant visible |
| B-07 | Demande de congé d'un membre | Approuver au niveau 1 ; rejeter avec motif (champ intégré à la page, pas de `prompt()` — D-13) |
| B-08 | Type de congé | Libellé français (« Congé annuel payé ») et non le code CONGE_ANNUEL (D-14) |
| B-09 | Dernière demande traitée | Message vide cohérent entre « Congés à valider » et « Demandes de l'équipe » (D-15) |
| B-10 | Liste des délégués | Matricule affiché pour distinguer les homonymes (D-11) |

## 4. Bloc C — Simulation d'organisation (/equipes/simulation, compte rh ou admin)
| ID | Action | Attendu |
|---|---|---|
| C-01 | Awa Kane sous Astou Diouf | Tableau « Effet sur les équipes » + ligne « sans lien » |
| C-02a | Rattacher un manager sous son futur subordonné | Refus « boucle hiérarchique », bouton désactivé |
| C-02b | Salarié manager de lui-même | Non proposé |
| C-03 | Changement d'unité | Effectif avant/après corrects |
| C-03b | Poste prévu « À pourvoir » (15) puis rattacher un salarié du même poste | À pourvoir 15 → 14, effectif +1 ; calcul cohérent avec le libellé du formulaire (D-36) |
| C-04 | Lien pointillé / intérim | Présent dans « Changements prévus » |
| C-05/06 | Corbeille, rechargement | Simulation vide |
| C-07 | Lot de 2 changements, « Appliquer » | Boîte de dialogue intégrée (D-07), succès, organigramme à jour ; restaurer ensuite l'organisation d'origine |
| C-08 | Atomicité : un changement invalide dans le lot | Aucun changement appliqué |
| C-09 | Retour à l'état d'origine | Organisation identique à l'état initial |
| C-10 | Comptes paie, manager, salarié | Refus d'accès |
| C-11 | Listes de salariés | Matricule et unité visibles, pas de tiret orphelin (D-01, D-02, D-38) |
| C-12 | Salarié sorti / entrée future (QA0008, QA0007) | Non proposés à la date du jour (D-03, D-04) |

## 5. Bloc D — Organigramme
| ID | Action | Attendu |
|---|---|---|
| D-01 | Recherche « Marie-Thérèse », puis « QA0008 » | Trouvé par nom (accents) et par matricule |
| D-02 | Panneau d'un salarié sorti | Statut cohérent avec /salaries (D-03) |
| D-03 | Vue Directions à 125 salariés | Lisible dès l'ouverture (repli ou zoom sur la racine — D-08) |
| D-04 | Nom de 80 caractères | Pas de débordement de la carte (D-05) |
| D-05 | Compte salarié | Lecture seule : pas de « + » actif ni d'actions d'édition (D-09) |
| D-06 | Menu d'une unité › Modifier › « Dépend de » | Types distingués (direction/service/unité) et matricule (D-39) |
| D-07 | 8 services QA | Chacun rattaché à sa direction ; aucune direction vide sauf Commerce Achats (créer le service ou documenter) |

## 6. Bloc E — Congés et demandes
| ID | Rôle | Action | Attendu |
|---|---|---|---|
| E-01 | salarié | Deux demandes de congé annuel futures | « Ouverte » → niveau manager |
| E-02 | manager | Approuver E1 | Passe au niveau RH |
| E-03 | admin/rh | Validation finale | « Approuvée », solde débité |
| E-04 | même compte | Décider les deux niveaux d'une demande | Refus « Séparation des tâches » |
| E-05 | manager | Rejeter avec motif | « Rejetée » ; le salarié voit le motif (D-18) |
| E-06 | salarié | /conges | Ses seules demandes, états à jour, formulaire vidé après envoi (D-16) |
| E-07 | salarié | Demande datée dans le passé | Directement au niveau RH |
| E-08 | salarié | Fin avant début | Message français clair (D-23) |
| E-09 | salarié | Chevauchement avec un congé approuvé | **Refus** (D-24) |
| E-10 | salarié | Absence dans un mois de paie validé | **Refus ou alerte bloquante** (D-25) |
| E-11 | salarié | Solde insuffisant / maternité sans droit | **Refus ou alerte** ; solde jamais négatif sans règle explicite (D-26) |
| E-12 | salarié | Congé à cheval sur deux années | Jours calculés par année |
| E-13 | rh | Congé non payé approuvé puis recalcul du mois | **Bulletin réduit sans double saisie** (D-27) |
| E-14 | salarié | /mon-espace › Mes demandes | Affiche les demandes de congé approuvées (D-33) |
| E-15 | salarié | Acompte 50 000 F, attestation, correction de présence, « Autre » | Cinq demandes « Ouverte » |
| E-16 | salarié | Acompte disproportionné (10 000 000 F pour un salaire de ~551 200 F) | **Refus ou plafond** (D-31) |
| E-17 | salarié | Montant 0, négatif ou « abc » | Message d'erreur visible (D-29) |
| E-18 | rh | Rejeter sans motif / avec motif | Motif obligatoire |
| E-19 | rh | Acompte approuvé | Retenue ou avance créée automatiquement dans la paie (D-32) |
| E-20 | tous | Données réelles dans /demandes | Absentes de la base de test (D-17) |

## 7. Bloc F — Paie
| ID | Rôle | Action | Attendu |
|---|---|---|---|
| F-01 | paie | Créer un traitement (mois passé de test) | Brouillon |
| F-02 | paie | Calculer | Bulletins en quelques secondes ; masse salariale cohérente |
| F-03 | paie | Contrôler | Erreurs bloquantes et alertes listées ; message précis pour un salarié sans structure salariale, avec lien de correction (D-41) |
| F-04 | paie | Envoyer en revue | « En revue » |
| F-05 | paie | Approuver | Refus « rôle rh requis » |
| F-06 | rh | Approuver | Bouton visible et fonctionnel pour rh, masqué pour paie (D-19) |
| F-07 | admin | Approuver | « Approuvée » ; compteur d'approbations incrémenté (D-20) ; `approved_by` renseigné |
| F-08 | admin | Valider un mois futur | Refus « impossible de valider un mois futur » |
| F-09 | admin | Valider un mois préparé par soi-même | Dérogation motivée obligatoire, journalisée |
| F-10 | admin | Valider un mois « Calculée » sans approbation | **Refus** : approbation préalable obligatoire (D-43) |
| F-11 | salarié | /mes-bulletins avant et après validation | Aucun bulletin avant ; uniquement les siens après ; lecture REST de `salary_slips` d'un autre salarié = 0 ligne |
| F-12 | admin | « Remettre en Calculée » un mois « Réouverte » | Bouton disponible (D-44) |
| F-13 | admin | Remettre en Calculée un mois « Payée » | Export des paiements proposé avant annulation (D-47) |
| F-14 | paie | Recalculer un mois ancien | Effectif d'origine seul, pas de bulletins QA ajoutés (D-45) |
| F-15 | paie | Clôturer un mois sans paiement enregistré | Refus ou alerte (D-48) |
| F-16 | paie | Présences (8 h d'absence) → Variables du mois → recalcul | Brut réduit au prorata |
| F-17 | paie | Prêt 120 000 F, 6 échéances | Actif, retenue mensuelle |
| F-18 | paie | Prêt supérieur au net, mois recalculé | **Retenue plafonnée au net, erreur bloquante si net ≤ 0** (D-30) |
| F-19 | paie | Montant 0 / négatif / 0 échéance | Message d'erreur visible (D-29) |
| F-20 | admin | Bandeaux de gouvernance | « Période clôturée » seulement sur les mois clôturés (D-21) |
| F-21 | paie | Mois futur avec salarié actif sans structure | Alerte à la création du traitement, pas seulement à l'approbation (D-42) |
| F-22 | admin | Rapport de clôture, livre de paie, synthèse CSV | Montants identiques aux bulletins |

## 8. Bloc G — Transversal
| ID | Action | Attendu |
|---|---|---|
| G-01 | Largeur 400 px sur /conges, /mon-espace, /organigramme, /paie | Aucun défilement horizontal |
| G-02 | Montants | Séparateur de milliers, ≤ 2 décimales, alignés à droite |
| G-03 | Libellés de champs | Tous accessibles ; ordre de tabulation logique |
| G-04 | Focus clavier (Tab) | Contour 2 px visible sur chaque élément |
| G-05 | Déconnexion puis retour arrière | Écran de connexion, aucune donnée |
| G-06 | Menu mobile | « Se déconnecter » atteignable (D-12) |
| G-07 | Inscription | « Créer un compte » masqué quand SIGNUP_ENABLED=false ; l'API répond 403 (D-40) |
| G-08 | Temps de chargement (127 salariés) | /salaries, /organigramme, /simulation, /mon-equipe, /paie < 3 s ; relever les valeurs |
| G-10 | Tableau de bord annuel (année avec mois validés, payés et clôturés) | Le graphique « Masse salariale validée par mois » montre tous les mois validés, payés ou clôturés ; total annuel = somme des bulletins en base (D-52) |
| G-09 | Journal des modifications | Chaque transition de paie, dérogation et annulation est journalisée avec auteur et motif |

## 9. Vérification des correctifs (une ligne par défaut)
À rejouer après chaque lot de corrections ; cocher la colonne « Corrigé » avec la date.
| Défaut | Gravité | Test de vérification | Corrigé |
|---|---|---|---|
| D-01, D-02, D-11, D-38 | Maj./Min. | C-11, B-10 | |
| D-03, D-04 | Maj./Min. | C-12, D-02 | |
| D-07, D-13 | Min. | C-07, B-07 | |
| D-08 | Maj. | D-03 | |
| D-09, D-10 | Min. | D-05, A-07 | |
| D-12 | Min. | G-06 | |
| D-14, D-15, D-16, D-18 | Min. | B-08, B-09, E-06, E-05 | |
| D-17, D-22 | Min. | E-20, F-01 | |
| D-19 | Maj. | F-06 | |
| D-20, D-21 | Min. | F-07, F-20 | |
| D-23 | Min. | E-08 | |
| D-24 | Maj. | E-09 | |
| D-25 | Maj. | E-10 | |
| D-26 | Maj. | E-11 | |
| D-27 | Maj. | E-13 | |
| D-28 | Min. | F-12 | |
| D-29 | Min. | E-17, F-19 | |
| D-30 | Maj. | F-18 | |
| D-31 | Maj. | E-16 | |
| D-32 | Min. | E-19 | |
| D-33 | Min. | E-14 | |
| D-34, D-35 | Min. | B-03, B-04 | |
| D-36, D-37 | Min. | C-03b | |
| D-39 | Min. | D-06 | |
| D-40 | Min. | G-07 | |
| D-41, D-42 | Min./À trancher | F-03, F-21 | |
| D-43 | Maj. | F-10, `tests/sql/d43_approbation.sql` | Corrigé le 05/11/2026 (migration 20261107120000) : validation directe réservée à l'admin avec motif |
| D-44 | Maj. | F-12 | |
| D-45 | Maj. | F-14 | |
| D-46 | Min. | F-09 (champ de motif visible dès l'ouverture) | |
| D-47 | Maj. | F-13 | |
| D-48 | Min. | F-15 | |
| D-49 | Maj. | H-03, `tests/sql/d49_periode_cloturee.sql` | Corrigé le 05/11/2026 (migration 20261107110000) |
| D-50, D-51 | Min./À trancher | F-15, I-09 | |
| D-52 | Maj. | G-10, F-22 | 05/11/2026 (corrigé et vérifié) |
| D-53 | Maj. | I-04 (bulletin à brut nul sans alerte) | |
| D-54 | À vérifier | I-03b | |
| D-55 | Maj. | I-10, M-04 (`export_ipres_css`) | |
| D-56 | À trancher | I-02a, I-02b | |
| D-57 | Maj. | I-02c | |
| D-58 | Maj. | J-06b | |
| D-59 | Maj. | L-02 | |
| D-60 | Min. | J-07 | |
| D-61 | Min. | M-04, M-01 | |
| D-62, D-63 | Faux positifs | `tests/api/isolation.test.mjs` | Test corrigé le 05/11/2026 (statuts de bulletin Brouillon/Validé ; le manager lit ses propres bulletins) : 10/10 |

## 10. Modèle de compte rendu
```
Campagne du AAAA-MM-JJ — version/commit : ____ — sauvegarde : ____ — testeur : ____
Bloc A : _/8   Bloc B : _/10   Bloc C : _/13   Bloc D : _/7   Bloc E : _/20   Bloc F : _/22   Bloc G : _/9
Défauts corrigés (section 9) : _/48   Nouveaux défauts : D-49…
Données de test créées à nettoyer : …
```
Règle de nettoyage : ne supprimer qu'après accord ; conserver la sauvegarde de départ et restaurer les mois de paie dans leur état d'origine.
