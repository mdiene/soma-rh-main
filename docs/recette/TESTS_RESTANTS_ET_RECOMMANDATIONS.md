# SOMA-RH — Tests restants pour challenger la base et le SaaS, et recommandations

Établi le 05/11/2026 après la recette « 100 salariés » et la simulation 2025–2026 ([résultats](RESULTATS_SIMULATION_100_2026-11-04.md)).
Chaque ligne renvoie à un identifiant à ajouter à la [batterie](BATTERIE_TESTS_RECETTE.md) (bloc H à M). Priorité : P1 avant tout usage réel, P2 avant ouverture à d'autres clients, P3 amélioration.

## 1. Base de données et intégrité (bloc H)
| ID | Priorité | Test | Attendu / recommandation |
|---|---|---|---|
| H-01 | P1 | Rejouer toutes les migrations sur une base vide, puis comparer le schéma à la base de développement | Schémas identiques ; migrations idempotentes |
| H-02 | P1 | Restaurer un dump de `backups/` sur une base neuve et rejouer `verify-payroll.ps1` | Aucune perte, bulletins identiques |
| H-03 | P1 | Écrire sur une période clôturée par l'API REST : paiements (D-49), bulletins, variables, présences, prêts, affectations de structure | Toutes les écritures refusées par la base, pas seulement par l'écran |
| H-04 | P1 | Modifier une affectation de structure ou une règle de paie après validation d'un mois | Bulletins validés inchangés ; le recalcul exige la remise en état |
| H-05 | P1 | Double exécution simultanée de `run_payroll_entry` et de la validation (deux onglets) | Un seul résultat, pas de doublons de bulletins (verrou ou contrainte unique) |
| H-06 | P2 | Contraintes : montants négatifs, dates incohérentes, clés orphelines, doublons de matricule, e-mail unique | Refus avec message métier |
| H-07 | P2 | Intégrité de la chaîne d'audit (`audit_chain.sql`) après une campagne complète | Chaîne valide ; toute modification manuelle détectée |
| H-08 | P2 | Volumétrie : 1 000 puis 5 000 salariés, 5 ans de bulletins | Calcul < 60 s, listes paginées ; attention à la limite de lignes par défaut de PostgREST (les lectures au-delà sont tronquées en silence) |
| H-09 | P2 | Index et plans d'exécution des listes /salaries, /paie, Présences | Aucun balayage complet à 10 000 bulletins |
| H-10 | P3 | Fuseaux horaires et changement de mois (dates en UTC) | Aucun décalage d'un jour sur les périodes |

## 2. Moteur de paie (bloc I)
| ID | Priorité | Test | Attendu |
|---|---|---|---|
| I-01 | P1 | Comparaison au classeur de référence pour un échantillon de 30 cas (oracle) | Écart nul au centime |
| I-02 | P1 | Entrée et sortie en cours de mois, proratas, mois à 28/29/30/31 jours, année bissextile | Montants prorata corrects |
| I-03 | P1 | Barèmes IR et cotisations : tranches, plafonds, arrondis aux seuils | Conforme à la réglementation en vigueur ; table des barèmes datée |
| I-04 | P1 | Net négatif : retenue de prêt, acompte, avance (D-30) | Retenue plafonnée, erreur bloquante |
| I-05 | P2 | Heures supplémentaires (taux 15/40/60/100 %), travail de nuit, jours fériés | Majorations correctes |
| I-06 | P2 | Prime de 13e mois, gratification, indemnités de licenciement, solde de tout compte | Calculs et traces conformes |
| I-07 | P2 | Rétroactivité : changement de salaire au 01/xx rattrapé en M+2 | Rappel de salaire calculé sur chaque mois |
| I-08 | P2 | Congés payés : acquisition, report, indemnité compensatrice (D-26, D-27) | Soldes jamais négatifs sans règle ; alimentation automatique de la paie |
| I-09 | P2 | Simulation multi-années 2024–2026 avec historique de salaire réel (D-51) | Évolution salariale historisée |
| I-10 | P3 | Écritures comptables (`export_payroll_journal`) équilibrées, comptes SYSCOHADA | Débit = crédit ; rapprochement avec le livre de paie |
| I-11 | P3 | Déclarations (cotisations sociales, IR) : états de synthèse mensuels | Totaux égaux aux bulletins |

## 3. Sécurité de l'API et des données (bloc J)
| ID | Priorité | Test | Attendu |
|---|---|---|---|
| J-01 | P1 | Pour chaque table et rôle, lecture/écriture REST directe avec le jeton du rôle (matrice complète) | Aucune fuite hors périmètre ; salarié = ses lignes seulement |
| J-02 | P1 | Accès à la fiche d'un autre salarié par identifiant (IDOR) : bulletins, demandes, prêts, présences | 0 ligne ou 403 |
| J-03 | P1 | Jeton expiré, jeton falsifié, algorithme `none`, ancien jeton après changement de rôle | 401 ; droits relus à chaque appel |
| J-04 | P1 | Élévation de privilège : un salarié modifie son propre rôle ou `user_roles` | Refusé |
| J-05 | P1 | Injection : filtres PostgREST malveillants, SQL dans les champs, XSS dans noms, notes et motifs, injection de formule dans les exports CSV | Échappement, aucune exécution |
| J-06 | P1 | Limitation de débit de /auth/v1/token et verrouillage après échecs | Blocage temporaire, message neutre |
| J-07 | P2 | En-têtes (CSP, HSTS, X-Frame-Options), CORS limité aux origines autorisées, cookies/stockage du jeton | Conforme ; jeton hors `localStorage` si possible |
| J-08 | P2 | Mots de passe : politique, réinitialisation, expiration de session, déconnexion de tous les appareils | Politique appliquée |
| J-09 | P2 | Fonctions `SECURITY DEFINER` : chemin de recherche fixé, contrôle des droits internes | Aucune fonction exécutable par un rôle non autorisé |
| J-10 | P2 | Journalisation des accès aux données personnelles (RGPD) et droit à l'effacement | Journal consultable ; procédure d'anonymisation |
| J-11 | P2 | Secrets : aucune clé dans le dépôt ni dans les bundles front (`web/.env.production`) | Analyse des secrets propre |
| J-12 | P3 | Dépendances : `npm audit`, images Docker, versions PostgreSQL/PostgREST | Aucune vulnérabilité critique |

## 4. Multi-société et SaaS (bloc K)
| ID | Priorité | Test | Attendu |
|---|---|---|---|
| K-01 | P1 | Créer deux sociétés et vérifier l'isolation (company_id) sur toutes les tables, vues et RPC | Aucune donnée croisée |
| K-02 | P2 | Intégration d'un nouveau client : création de société, référentiels, premier administrateur, import Excel | Parcours sans intervention base de données |
| K-03 | P2 | Import massif de salariés (CSV/Excel) avec erreurs | Rapport ligne par ligne, rien d'appliqué à moitié |
| K-04 | P2 | Rôles personnalisés et délégations, droits par société | Matrice de droits documentée et testée |
| K-05 | P2 | Sauvegarde/restauration par société, export complet des données du client | Procédure testée |
| K-06 | P3 | Quotas, plans, facturation, désactivation d'un client | Selon le modèle commercial |
| K-07 | P3 | Montée de version sans interruption (migration en ligne) | Rollback testé |

## 5. Résilience, exploitation et performance (bloc L)
| ID | Priorité | Test | Attendu |
|---|---|---|---|
| L-01 | P1 | Coupure en plein calcul ou en pleine validation (arrêt du conteneur) | Transaction annulée, état cohérent |
| L-02 | P2 | Charge : 50 utilisateurs simultanés sur /paie, /conges, /mon-equipe | p95 < 2 s |
| L-03 | P2 | Panne de l'API ou de la base : messages d'erreur clairs, reprise automatique | Aucun écran blanc |
| L-04 | P2 | Supervision : journaux applicatifs, alertes, métriques de calcul de paie | Tableau de bord d'exploitation |
| L-05 | P2 | Sauvegarde automatique planifiée et test de restauration mensuel | Dernière sauvegarde < 24 h |
| L-06 | P3 | Navigateurs (Chrome, Edge, Firefox, Safari), tablette, accessibilité WCAG AA | Aucun blocage |
| L-07 | P3 | Hors ligne et reconnexion : saisie perdue, session expirée en plein formulaire | Brouillon conservé |

## 6. Parcours métier non couverts (bloc M)
| ID | Priorité | Test |
|---|---|---|
| M-01 | P1 | Cycle complet d'un nouveau salarié : embauche, contrat, structure salariale, premier bulletin, fiche de sortie |
| M-02 | P1 | Départ d'un salarié : solde de tout compte, désactivation du compte, conservation des bulletins |
| M-03 | P2 | Changement de manager et de service en cours de mois, délégation et intérim, effets sur les validations de congés |
| M-04 | P2 | Documents : attestations de travail et de salaire générées, bulletins PDF imprimables, archivage |
| M-05 | P2 | Notifications : e-mails ou in-app pour demande, approbation, rejet, bulletin disponible |
| M-06 | P2 | Contrats à durée déterminée et fin de période d'essai, alertes d'échéance |
| M-07 | P3 | Tableaux de bord annuels et mensuels : cohérence avec le livre de paie |

## 7. Recommandations (par ordre d'exécution)
1. **Fermer les trous d'intégrité côté base (P1)** : verrouiller toute écriture sur une période clôturée par triggers (D-49, H-03), rendre l'approbation obligatoire avant validation (D-43), plafonner les retenues au net (D-30). Les règles ne doivent pas dépendre de l'écran : l'API REST est directement exposée.
2. **Corriger les incohérences droits/écran (P1)** : bouton d'approbation (D-19), bouton de déblocage d'un mois « Réouverte » (D-44), recalcul cantonné à l'effectif d'origine (D-45).
3. **Mettre en place les contrôles métier des congés et demandes (P1/P2)** : chevauchement, solde, mois validé, plafond d'acompte, alimentation automatique de la paie (D-24 à D-27, D-31, D-32).
4. **Automatiser la recette** : transformer les blocs F, H, I et J en tests API/SQL rejouables à chaque migration (le dossier `tests/` existe déjà) ; lancer `verify-payroll.ps1` et la matrice de droits en intégration continue.
5. **Séparer la base de test de la base réelle** (D-17, D-22) : base `soma_rh_qa` distincte, générée par `qa-reset-scenario.ps1`, pour ne plus mêler salariés réels et salariés QA.
6. **Sauvegarde avant toute opération destructive** (D-47) : export automatique des paiements et des bulletins avant « Remettre en Calculée » ou suppression.
7. **Historiser les salaires** (D-51) pour que les simulations pluriannuelles reflètent des données réelles, puis tester la rétroactivité (I-07).
8. **Préparer l'ouverture SaaS** : isolation multi-société, import massif, procédures de sauvegarde, supervision et politique de sécurité (blocs J et K) avant tout second client.
9. **Qualité d'interface** : matricule dans toutes les listes, organigramme lisible à 125 salariés, messages d'erreur métier à la place des messages techniques (D-01, D-08, D-23, D-29).

## 8. Plan de campagne suggéré
| Étape | Contenu | Durée indicative |
|---|---|---|
| 1 | Correctifs P1 (point 1 à 3), puis relance des blocs F et H | 1 à 2 semaines |
| 2 | Blocs I et J (oracle de paie, matrice de droits, injections) | 1 semaine |
| 3 | Blocs K à M et charge | 1 à 2 semaines |
| 4 | Rejeu complet de la batterie, cochage de la table de vérification (section 9) | 2 jours |

## 9. Avancement des blocs H à M (05/11/2026, société unique)
Légende : ✔ exécuté (résultat dans la section 20 des résultats) · ◐ partiel · ✘ non exécuté. K est hors périmètre : une seule société.

| Bloc | Exécuté | Partiel | Non exécuté |
|---|---|---|---|
| H | H-03, H-05, H-06, H-07, H-08, H-09, H-10 | H-04 (modification après validation non rejouée) | H-01, H-02 (Docker requis), H-06 en saisie ligne par ligne |
| I | I-02, I-03, invariants, I-04 | I-01 (comparaison au classeur non rejouée), I-10 | I-05, I-06, I-07, I-08, I-09, I-11 |
| J | J-01 (anonyme), J-03, J-04, J-05, J-06, J-07 | J-09 (RPC anonymes uniquement) | J-02, J-08, J-10, J-11, J-12 et J-01 par rôle |
| K | — | — | Hors périmètre (société unique) |
| L | L-02 | — | L-01, L-03, L-04, L-05, L-06, L-07 |
| M | M-01, M-02 | M-04 | M-03, M-05, M-06, M-07 |

## 10. Éléments non pris en compte et à développer
### À développer dans l'application
| Domaine | Élément manquant | Défaut / test lié |
|---|---|---|
| Moteur de paie | Proratisation à l'entrée et à la sortie en cours de mois (si la règle de gestion l'exige) | D-56, I-02 |
| Moteur de paie | Suppression des bulletins brouillons des mois suivants après une sortie, et contrôle correspondant | D-57 |
| Moteur de paie | Contrôle bloquant : brut nul, net imposable négatif, net négatif ; TRIMF non prélevé à brut nul | D-30, D-53 |
| Moteur de paie | Revue de la réduction pour charges de famille (barème en vigueur) | D-54, I-03b |
| Moteur de paie | Historique des salaires (affectations datées sur plusieurs années), rappels de salaire rétroactifs | D-51, I-07 |
| Moteur de paie | 13e mois, gratifications, indemnités de licenciement, congés payés (acquisition, report, indemnité) | I-06, I-08 |
| Déclarations | Réparer `export_ipres_css` ; états DGID : lister les types ; états de synthèse mensuels | D-55, I-11 |
| Base de données | Verrouiller les paiements et les variables du mois d'une période clôturée (triggers) | D-49, H-03 |
| Base de données | Approbation obligatoire avant validation | D-43 |
| Exploitation | Verrouillage de connexion par compte et non par adresse source ; message neutre | D-58, J-06 |
| Exploitation | Capacité : pool de connexions, index, cache des agrégats du tableau annuel, test de charge reproductible | D-59, L-02 |
| Sécurité | En-têtes HTTP (CSP, HSTS, X-Frame-Options, nosniff), stockage du jeton hors `localStorage`, politique de mot de passe | D-60, J-07, J-08 |
| Sécurité | Journalisation des accès aux données personnelles, anonymisation (droit à l'effacement) | J-10 |
| Exploitation | Supervision (journaux, alertes), sauvegarde planifiée et test de restauration mensuel | L-04, L-05 |
| Documents | Bulletins PDF, attestations, certificat de travail avec le poste, archivage | M-04, D-61 |
| Notifications | E-mails ou notifications pour demandes, approbations, rejets, bulletin disponible | M-05 |
| Contrats | Alertes de fin de CDD et de période d'essai | M-06 |
| Import | Import massif de salariés (CSV/Excel) avec rapport par ligne | K-03 |
| Numérotation | Série de matricules cohérente (D-61) | M-01 |

### À tester mais non réalisé faute d'accès ou de périmètre
| Test | Raison | Pour le réaliser |
|---|---|---|
| H-01, H-02 (migrations sur base vide, restauration d'une sauvegarde) | Pas d'accès à Docker ni à PowerShell depuis cette session | Lancer sur la machine locale, base neuve, puis `verify-payroll.ps1` |
| I-01 (oracle du classeur) | Même raison | `scripts/verify-payroll.ps1` et `tests/oracle` |
| J-01 par rôle, J-02, J-04 par rôle (salarié, manager, rh, paie) | Les mots de passe de `tests/.env.qa` ne sont pas accessibles à cette session | Lancer `tests/api/isolation.test.mjs` en local ou fournir une session par rôle |
| J-05 (XSS stocké, injection CSV dans les exports) | Nécessite d'écrire des données hostiles dans les fiches | Jeu de données dédié, base `soma_rh_qa` séparée |
| L-01 (coupure en plein calcul), L-03, L-07 | Nécessitent d'arrêter les services | Procédure locale `docker compose stop` pendant un calcul |
| K-01 à K-07 | Société unique : hors périmètre | À planifier avant la deuxième société |
| M-03, M-05, M-06, M-07 | Fonctions absentes ou non vérifiables sans jeu de données (délégations, e-mails, CDD) | Développer puis tester |

Ces éléments sont aussi à reporter dans la feuille de route : voir le tableau « À développer » ci-dessus.

## 11. Rejeu des suites automatisées (05/11/2026)

- J (isolation par rôle) : `isolation.test.mjs` 10/10 (anonyme, 2 salariés, RH, paie, manager). Reste à faire : isolation du rôle `paie` en lecture sur les données RH non nécessaires et tests par rôle sur les RPC.
- Routes d'authentification et documents : `routes.test.mjs` 13/13.
- `verify-payroll.ps1` (août 2026) : PASS, aucun écart avec la référence.
- Prochaine étape : corrections prioritaires D-49, D-43, D-30/D-53, D-58, puis rejeu de la batterie.

