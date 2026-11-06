# Résultats — simulation à 100 salariés (04/11/2026)

Base : locale, même base que le développement, après sauvegarde `backups/soma-rh-20261104-185558.dump`.
Méthode : les 100 salariés ont été créés par le générateur officiel `scripts/qa-reset-scenario.ps1 -Scenario pme-100` (ajouté pour l'occasion, 2 lignes modifiées), puis les 98 liens hiérarchiques posés dans /equipes. Aucune donnée réelle (S00xx) n'a été modifiée. Aucun mot de passe n'est consigné ici.

## 1. Effectif avant / après
| | Avant | Après |
|---|---|---|
| Fiches salariés | 27 (3 QA + 24 réels) | **127** (100 QA + 26 S + 1 inactif `s003254`) |
| Organigramme au 04/11/2026 | — | 125 salariés (QA0007 entre le 16/11/2026 ; `s003254` inactif ; QA0008 sorti mais affiché, voir D-03) |
| Salariés sans manager direct (organigramme) | 117 | **19** : 17 réels S + OUSMANE TRAORE (réel) + QA0008 (sorti) |

## 2. Répartition par unité (cible du prompt / obtenu)
Le générateur crée 8 services génériques, pas les directions du prompt : la répartition cible (30/22/14…) n'a pas été reproduite. Les 8 directions « QA Direction … » ont été créées mais restent **vides (0 salarié)**.

| Direction cible (prompt) | Cible | Service QA obtenu | Obtenu |
|---|---|---|---|
| Direction générale | 4 | — (QA0001 seul, hors service) | — |
| Exploitation / Mine | 30 | QA Exploitation | 13 |
| Production / Usine | 22 | QA Laboratoire + QA Maintenance | 13 + 12 |
| Logistique & Transport | 14 | QA Logistique | 13 |
| Finance & Comptabilité | 8 | QA Finance | 13 |
| RH & Paie | 6 | QA Ressources humaines | 12 |
| HSQE | 8 | QA Sécurité | 11 |
| Commerce & Achats | 8 | QA Administration | 12 |

## 3. Tests de simulation (/equipes/simulation, compte admin)
| Test | Action | Attendu | Observé | Résultat |
|---|---|---|---|---|
| C-01 | Awa Kane sous Astou Diouf | Tableau « Effet sur les équipes » + ligne « sans lien » | Khady Cissé 5→4 (−1), Astou Diouf 0→1 (+1), sans lien 19→19 | PASS |
| C-02a | Astou Diouf sous Awa Kane (son futur subordonné, changement C-01 en attente) | Refus + bouton désactivé | « Ce changement créerait une boucle hiérarchique. », bouton grisé | PASS |
| C-02b | Salarié manager de lui-même | Refus | Le salarié n'est pas proposé dans la liste des managers | PASS |
| C-03 | Awa Kane vers QA Maintenance | Effectif avant/après | Laboratoire 13→12, Maintenance 12→13 | PASS (partiel) |
| C-03b | « À pourvoir avant/après » | Visible si poste prévu | Colonnes absentes : aucun poste prévu créé | NON TESTÉ |
| C-05 | Corbeille | Simulation vide | « Aucun changement simulé » | PASS |
| C-06 | Recharger la page | Simulation vide | Simulation vide | PASS |
| C-07 | Lot de 2 changements (Awa Kane et Ndèye Mbaye sous Astou Diouf), « Appliquer 2 changements » | Succès, organigramme à jour, notification | Le lot s'affiche bien (Astou Diouf 0→2, Khady Cissé 5→4, Sokhna Camara 4→3, sans lien 19→19) mais « Appliquer » déclenche un `confirm()` natif (« Appliquer 2 changement(s) ? Tout est appliqué ensemble… ») que le navigateur intégré refuse automatiquement : aucune requête envoyée, base inchangée | BLOQUÉ (outil) |
| C-04, C-08, C-09 | Lien pointillé/intérim, atomicité, retour à l'état d'origine | — | Non exécutés (dépendent de l'application d'un lot) | NON TESTÉ |
| C-10 | Refus pour paie/manager/salarié | — | Non exécuté | NON TESTÉ |

Rien n'a été appliqué lors des tests de simulation : l'organisation n'a pas été modifiée par ces essais.

## 4. Défauts
| N° | Gravité | Page | Constat |
|---|---|---|---|
| D-01 | Majeur | /equipes/simulation, /equipes/organigramme | Les listes de salariés n'affichent pas le matricule : libellés « Khady N'Diaye — » (5 homonymes), « Élimane Kane — » (6), « Moussa Diop — » (4)… impossible de distinguer deux personnes. Seule la page /equipes affiche le matricule. Le sélecteur n'accepte pas non plus la recherche par matricule. |
| D-02 | Mineur | /equipes/simulation | Libellé avec tiret final orphelin (« Awa Kane — ») quand l'emploi est vide. |
| D-03 | Majeur à vérifier | /equipes/organigramme vs /salaries | QA0008 Coumba Sy est « Sorti » dans /salaries mais « Actif » dans l'organigramme, dans QA Administration, et compté dans les 19 anomalies. Les listes de la simulation la proposent aussi. À confirmer selon la date de sortie. |
| D-04 | Mineur | /equipes/simulation | QA0007 (entrée le 16/11/2026) est proposé alors qu'il n'est pas dans l'organigramme du jour. |
| D-05 | Mineur | /equipes/organigramme | Un nom de 80 caractères (QA0004 « Coumba Ndiaye-Ndiaye-… ») est affiché en entier dans les cartes : à vérifier pour le débordement. |
| D-06 | Majeur (donnée de test) | /equipes/organigramme | Les 8 services QA ne sont rattachés à aucune direction (« Sans direction » = 25 salariés) et aucun service n'a de « Responsable ». Les 8 directions QA sont vides. Aucun chemin d'interface simple trouvé pour rattacher un service à une direction depuis l'écran d'organigramme (pastilles de carte à glisser, difficile à piloter via le navigateur). |

Note D-07 (mineur, UX) : la confirmation d'« Appliquer » est une fenêtre native `confirm()`. Elle est incompatible avec les tests automatisés et avec certains navigateurs ; une boîte de dialogue intégrée à l'application serait testable et plus cohérente avec le design.

## 5. Temps de chargement
Non mesurés chiffrés. Qualitativement, /salaries (127 lignes), /equipes/organigramme (125 salariés, vue Directions) et /equipes/simulation se sont affichées sans attente visible. Mesure /mon-equipe avec qa-manager non faite.

## 6. Ce qui n'a pas pu être fait
- Rattacher les 8 services aux 8 directions, désigner des responsables, créer un poste prévu (donc C-03b « À pourvoir »).
- C-04, C-07 à C-10, blocs recette B à G (aucun autre rôle essayé).
- Répartition cible 30/22/14… : le générateur ne la produit pas ; il faudrait étendre `generate.sql` ou le faire par migration de test.
- Le navigateur intégré ne permet ni l'exécution JavaScript ni l'accès à la console : pas de mesure de performance fine.

## 7. Suites proposées
1. Corriger D-01 (afficher matricule + emploi dans tous les sélecteurs) : c'est ce qui bloque le plus un usage à 100 salariés.
2. Faire créer par le générateur les directions rattachées aux services, avec un responsable par service et un poste prévu par unité.
3. Rejouer C-04, C-07 à C-10 avec ces données.

Note : `scripts/_run-pme100.bat` est un lanceur temporaire à supprimer.

---

## 8. Tests complémentaires (mêmes données, 04/11/2026)

| Test | Rôle | Action | Attendu | Observé | Résultat |
|---|---|---|---|---|---|
| C-04 | admin | Lien pointillé Awa Kane ↔ Astou Diouf | Présent dans « Changements prévus » | « Rattachement pointillé avec Astou Diouf », bouton Appliquer 1 changement ; retiré à la corbeille | PASS |
| D-1 | admin | Recherche organigramme « Marie-Thérèse » puis « QA0008 » | Résultat trouvé | Trouvé par nom (accents OK) et par matricule ; clic ouvre le panneau (matricule, poste, unité, manager, liens, équipes) | PASS |
| D-2 | admin | Panneau QA0008 | Cohérent avec /salaries | « Actif » + « Aucun manager direct à cette date » alors que /salaries dit « Sorti » | FAIL (D-03 confirmé) |
| A-1 | salarié (QA0011) | Menu | Mon espace, Organigramme, Congés, Mes bulletins | Exactement ces 4 entrées | PASS |
| A-2 | salarié | URL directes /equipes, /equipes/simulation, /mon-equipe, /salaries, /demandes, /parametres | Redirection, aucune donnée | Les 6 redirigent vers /mon-espace | PASS |
| D-3 | salarié | Organigramme | Lecture seule | Pas de bouton « Créer » ; panneau d'une carte sans action d'édition ; voit les 125 salariés | PASS (voir D-09) |
| G-1 | salarié | Déconnexion puis retour arrière | Aucune donnée | Page de connexion | PASS |
| B-1 | manager (QA0013) | « Mon équipe » | Calendrier, soldes, présence | Calendrier de novembre 2026, soldes (« Aucune dotation… »), Présence 30 jours | PASS |
| B-3 | manager | Montants / prêts | Aucun | Aucun montant ni prêt | PASS |
| B-4 | manager | Périmètre | QA0011 oui, QA0012 non | 5 salariés affectés : QA0011, QA0005, QA0029, QA0037, QA0045 ; QA0012 absent | PASS |
| B-2 | manager | Seuils orange | Orange à ≥3 absences ou ≥20 h sup. | Toutes les valeurs sont à 0 : non vérifiable | NON TESTÉ |
| B-5 | manager | Valider/refuser une demande | Demande en attente | « Aucune demande pour votre équipe » | NON TESTÉ |

### Défauts supplémentaires
| N° | Gravité | Page | Constat |
|---|---|---|---|
| D-08 | Majeur (volume) | /equipes/organigramme | À 125 salariés, l'ajustement initial de la vue (« fit ») rend les cartes illisibles (points minuscules) ; il faut zoomer à la main. À améliorer : repli par défaut des équipes ou zoom sur la racine. La molette sur le canevas zoome (le défilement de la page est capturé). |
| D-09 | Mineur à vérifier | /equipes/organigramme (salarié) | Des pastilles « + » restent visibles sur les cartes pour un salarié, alors que l'édition est interdite. À vérifier si elles ouvrent quelque chose. Le salarié voit aussi « 19 anomalie(s) ». |
| D-10 | Mineur | Menu latéral, juste après connexion (salarié) | Pendant le chargement, le menu affiche « aucun rôle attribué » et les entrées « Congés » et « Paramètres » quelques instants, avant de se corriger. La page /parametres redirige bien ensuite. |
| D-11 | Mineur | /mon-equipe | La liste « Délégué » propose « Khady N'Diaye » deux fois (homonymes, cf. D-01). |
| D-12 | Mineur (mobile) | Menu latéral | En fenêtre étroite (menu hamburger), le menu se referme au défilement : impossible d'atteindre « Se déconnecter » sans élargir la fenêtre. |

Non fait : comptes rh et paie (bloc A), blocs E, F, G (sauf retour arrière), mesures de temps de chargement chiffrées.

## 9. Compléments : lot en attente (C-07) et Bloc E (congés à deux niveaux)

| ID | Rôle | Action | Attendu | Observé | Résultat |
|---|---|---|---|---|---|
| C-07 | rh/admin (Chrome) | Appliquer le lot de 2 changements (Awa Kane et Ndèye Mbaye sous Astou Diouf), puis restaurer l'organisation | Message de succès, organigramme à jour, restauration propre | Lot appliqué et organisation d'origine rétablie et vérifiée | PASS (via Chrome, voir D-07) |
| E-1 | salarié QA0011 | Déposer deux demandes de congé annuel (17–18/11 et 24–25/11) | Demandes créées, « Ouverte » | Créées | PASS |
| E-2 | manager QA0013 | Voir les demandes dans « Mon équipe » et approuver E1 | Visible, passe au niveau RH | E1 passée « niveau RH » | PASS |
| E-3 | admin | Validation finale de E1 | État « Approuvée » | « Approuvée » | PASS (soldes avant/après non vérifiés : aucune dotation enregistrée pour l'équipe) |
| E-5 | manager | Rejeter E5 avec motif | État « Rejetée » | « Rejetée » (motif saisi par simulation de prompt, voir D-13) | PASS |
| E-4 | — | Un même compte ne peut pas valider les deux niveaux | Refus | Non testé | NON TESTÉ |
| E-6 | salarié | Le salarié voit le refus et l'approbation | Visible | Non vérifié | NON TESTÉ |

### Défauts complémentaires
| N° | Gravité | Page | Description |
|---|---|---|---|
| D-13 | Mineur | /mon-equipe (Rejeter) | Le refus utilise un `prompt()` natif du navigateur pour le motif : inutilisable dans le navigateur intégré (erreur « prompt() is not supported », le bouton ne réagit pas). Préférer un champ de saisie dans la page. |
| D-14 | Mineur | /mon-equipe | Le type de congé s'affiche en code brut « CONGE_ANNUEL » au lieu de « Congé annuel payé ». |
| D-15 | Mineur | /mon-equipe | Après traitement de la dernière demande, la section « Congés à valider » disparaît sans message vide, alors que « Demandes de l'équipe » indique par ailleurs « Aucune demande » : incohérent. |
| D-16 | Mineur | /conges | Le formulaire « Nouvelle demande » conserve les valeurs de la demande précédente après envoi. |
| D-17 | Mineur | /demandes (admin) | Les listes affichent des données de vrais salariés (S00xx) dans la même base : à séparer de la base de test. |

Non fait : E-4, E-6, blocs A (rh/paie), F, G ; rattachement des 8 services QA aux 8 directions QA ; postes prévus (C-03b) ; mesures chiffrées des temps de chargement.

### Mise à jour E-6
| E-6 | salarié QA0011 | Consulter /conges après traitement | Voir l'approbation et le refus, et seulement ses propres demandes | 2 lignes : 17–18/11 « Approuvée », 24–25/11 « Rejetée » ; aucune demande d'autres salariés | PASS |

| N° | Gravité | Page | Description |
|---|---|---|---|
| D-18 | Mineur | /conges (salarié) | Le salarié voit l'état « Rejetée » mais pas le motif du refus saisi par le manager (la colonne « Motif » n'affiche que son propre motif de demande). |

Reste non testé : E-4 (un même compte validant les deux niveaux).

### Bloc G (partiel, compte salarié)
| ID | Action | Observé | Résultat |
|---|---|---|---|
| G-3 | Largeur 400 px sur /conges, /mon-espace, /equipes/organigramme | Pas de défilement horizontal (largeur du contenu = largeur de la fenêtre) | PASS |
| G-4a | Libellés des champs sur /conges | Tous les champs et boutons ont un libellé accessible | PASS (la navigation clavier Tab n'a pas été testée) |

### Bloc A — comptes rh et paie (accès par adresse directe)
| ID | Rôle | Action | Attendu | Observé | Résultat |
|---|---|---|---|---|---|
| A-rh | rh | Menu + 9 adresses directes | Accès aux écrans RH | 21 entrées de menu (RH + paie + Paramètres). /equipes, /equipes/simulation, /equipes/organigramme, /salaries, /demandes, /mes-bulletins, /parametres accessibles ; /mon-equipe redirige vers le tableau de bord ; /mon-espace affiche « Votre compte n'est pas encore relié à une fiche salarié » | PASS |
| A-paie | paie | Menu + 9 adresses directes | Pas d'accès aux écrans réservés RH | /equipes, /equipes/simulation, /mon-equipe, /demandes redirigent vers le tableau de bord (refus correct). Accessibles : organigramme, salariés, mes-bulletins, mon-espace (message « compte non relié »), parametres | PASS (à confirmer : le rôle paie doit-il voir « Salariés », « Organigramme » et « Paramètres » ? onglet « Accès » ne montre que « Mon compte », aucune liste de comptes) |

Point d'attention (mineur) : le rôle paie voit dans Paramètres les onglets « Référentiels RH » et « Journal des modifications » ; vérifier que ces onglets n'exposent rien d'inapproprié pour ce rôle.

## 10. Bloc F — Paie (période de test : Décembre 2026, créée pour l'occasion)
Choix validé par l'utilisateur : nouveau traitement « Décembre 2026 ». Aucun mois existant modifié. Sauvegarde juste avant impossible depuis la session (pas d'accès à Docker/PowerShell) : dernière sauvegarde disponible antérieure au chargement pme-100.

| ID | Rôle | Action | Attendu | Observé | Résultat |
|---|---|---|---|---|---|
| F-1 | paie | Créer le traitement 2026-12 | Brouillon créé | « Brouillon » créé | PASS |
| F-2 | paie | Calculer les bulletins | Bulletins calculés | 125 bulletins en ~4 s ; brut 92 493 907 F, net 70 586 556 F, masse salariale 106 328 337 F | PASS |
| F-3 | paie | Contrôler (gouvernance) | Contrôle de préparation | « Contrôle réussi », avertissements « Aucune variable du mois saisie » (125 salariés) et variations de net pour S0001 et S0010 | PASS |
| F-4 | paie | Envoyer en revue | Calculée → En revue | « En revue » | PASS |
| F-5 | paie | Approuver la paie (même compte) | Refus | « Droits insuffisants : rôle « rh » requis pour approuver une paie » | PASS (refus correct) |
| F-6 | rh (qa-rh) | Approuver la paie | Bouton disponible | Bouton « Approuver la paie » absent pour qa-rh, présent pour paie (refusé) et admin | FAIL (D-19) |
| F-7 | admin | Approuver la paie | En revue → Approuvée | « Approuvée » | PASS |
| F-8 | admin | Valider la paie de décembre | Validation | Refus « Période 12/2026 : impossible de valider un mois futur » (règle métier correcte) | PASS (validation non testable avant décembre) |
| F-9 | — | Séparation saisie/validation par un même compte | Refus | Non testée de bout en bout (validation impossible sur un mois futur) | NON TESTÉ |
| F-10 | salarié | Ne voir que ses bulletins | — | Non testé (aucun bulletin validé pour QA0011) | NON TESTÉ |

Défauts :
| N° | Gravité | Page | Description |
|---|---|---|---|
| D-19 | Majeur | /paie/gouvernance | Incohérence entre l'interface et les droits : le bouton « Approuver la paie » est affiché au rôle paie (qui reçoit « Droits insuffisants : rôle « rh » requis ») et masqué au rôle rh, seul autorisé. Un compte rh seul ne peut donc pas approuver depuis l'écran. |
| D-20 | Mineur | /paie/gouvernance | Le compteur « 0 approbation(s) » reste à 0 après l'approbation de Décembre. |
| D-21 | Mineur | /paie/gouvernance | Des bandeaux « PÉRIODE CLÔTURÉE — OPÉRATIONS BLOQUÉES » restent affichés alors que le traitement courant n'est pas clôturé (messages des périodes clôturées visibles en permanence). |
| D-22 | Mineur | /paie | Le traitement de Décembre 2026 inclut des salariés réels (S0001, S0010) en plus des QA : la base de test n'est pas isolée (cf. D-17). |

À nettoyer : le traitement « Décembre 2026 » reste à l'état « Approuvée » (test). Le supprimer ou le remettre en Calculée avant utilisation réelle.

### Bloc G — compléments
| ID | Action | Observé | Résultat |
|---|---|---|---|
| G-2 | Montants sur /paie (cartes et tableau des 125 bulletins) | Séparateur de milliers (« 92 493 907 F »), aucun montant brut non formaté ni à plus de 2 décimales ; colonnes numériques alignées à droite avec chiffres tabulaires | PASS |
| G-5 | Déconnexion puis retour arrière du navigateur (depuis le détail d'un traitement de paie) | Retour sur l'écran de connexion, aucune donnée de paie réaffichée | PASS |
| G-4b | Ordre de tabulation et libellés sur l'écran de connexion | 4 éléments atteignables (e-mail, mot de passe, Se connecter, Créer un compte), tous libellés ; l'indicateur visuel de focus n'a pas pu être vérifié par script | PARTIEL |

Point d'attention (sécurité) : l'écran de connexion propose « Pas encore de compte ? Créer un compte ». À vérifier : qui peut s'inscrire, avec quels droits par défaut (idéalement aucun rôle tant qu'un admin n'a pas attribué de rôle).

## 11. Bloc E (suite), simulations de congés, paie, prêts et demandes

### E-4 : séparation des tâches sur les congés
| ID | Rôle | Action | Attendu | Observé | Résultat |
|---|---|---|---|---|---|
| E-4 | admin (qa-admin) | Approuver la demande « Recette E4 » (niveau manager), puis tenter le niveau RH avec le même compte | Refus du second niveau | 1er clic : passe au niveau RH. 2e clic : refus « Séparation des tâches : la même personne ne peut pas décider deux niveaux d'une même demande » | PASS |

### Simulations de congés (salarié QA0011, 9 demandes)
| Demande | Observé |
|---|---|
| Permission 06–07/07, maladie 10–12/08, absence non payée 14–16/09, congé annuel 12–16/10 | Créées. Les demandes datées dans le passé arrivent directement au niveau RH (sans niveau manager) ; les demandes futures passent par le manager d'abord |
| Maternité 11/01–18/04/2027 (98 j) | Acceptée pour une salariée QA0011 sans contrôle de cohérence (type, ancienneté, solde) |
| Chevauchement avec le congé déjà approuvé du 17–18/11 | Acceptée sans alerte (D-24) |
| Fin avant début (20/12 au 18/12) | Refusée avec le message brut « new row for relation "leave_applications" violates check constraint "leave_applications_check" » (D-23) |
| Absence non payée du 10/06 (mois validé) | Acceptée puis approuvée au niveau RH sans blocage (D-25) |
| Congé à cheval sur deux années (24/12/2026–04/01/2027) | Acceptée, 12 jours |

Les 5 demandes passées ont été approuvées par l'admin de test : le salarié reçoit bien une notification « Votre demande de congé est approuvée » pour chacune. Les soldes de congé du salarié passent en négatif (« Congé annuel payé : −7 j ») sans aucun blocage (D-26).

### Paie : recalcul et effet des absences
| ID | Action | Observé | Résultat |
|---|---|---|---|
| F-11 | Recalculer Juillet, Août, Septembre, Octobre 2026 (états « Calculée ») | 125 bulletins chacun en ~4 s ; les contrôles passent de « 98 erreur(s) » (salariés sans bulletin) à « 0 erreur » | PASS |
| F-12 | Approuver une absence non payée (14–16/09) puis recalculer Septembre | Brut inchangé (551 200 F) : l'approbation du congé n'alimente PAS la paie | À noter (D-27) |
| F-13 | Saisir 8 h d'absence dans Présences le 14/09, reprise automatique en « Variables du mois », puis recalcul de Septembre | Brut QA0011 : 551 200 → 525 760 F (−25 440 F) | PASS |
| F-14 | Remettre un mois « Calculée » en brouillon | Le bouton « Annuler » de la page d'un traitement « Calculée » ne produit aucun effet visible ; seul « Recalculer » est disponible. La remise en « Calculée » n'existe que depuis En revue/Approuvée | NON CONCLUANT (D-28) |

### Prêts (écran « Prêts et régularisations »)
| ID | Action | Observé | Résultat |
|---|---|---|---|
| P-1 | Prêt 120 000 F, 6 échéances, première retenue 12/2026 (QA0011) | Créé, statut « Actif », reste 120 000 F | PASS |
| P-2 | Montant 0 / montant négatif / 0 échéance | Refusés sans aucun message à l'écran (aucune ligne créée) | FAIL (D-29, mineur) |
| P-3 | Prêt 5 000 000 F en 1 échéance dès 10/2026 (QA0012), puis recalcul d'Octobre | Net à payer de QA0012 = **−3 948 133 F**, aucune erreur ni alerte aux contrôles, prêt marqué « Soldé » avec 5 000 000 F « retenus » | FAIL (D-30, majeur) |

### Demandes des salariés (acompte, attestations)
| ID | Action | Observé | Résultat |
|---|---|---|---|
| R-1 | Acompte 50 000 F, acompte 10 000 000 F, attestation de salaire, correction de présence, « Autre » | Cinq demandes créées « Ouverte ». Montant 0 et montant « abc » refusés sans message | PASS / D-29 |
| R-2 | Acompte de 10 000 000 F pour un salarié payé ~551 200 F | Accepté sans plafond ni avertissement | FAIL (D-31) |
| R-3 | RH : approuver 4 demandes et rejeter l'acompte de 10 M avec motif obligatoire (via la fenêtre de confirmation) | Traitées ; le motif est exigé pour un rejet | PASS |
| R-4 | Effet de l'acompte approuvé sur la paie | Aucun prêt/avance ni retenue créés automatiquement ; il faut saisir manuellement un prêt | À noter (D-32) |

### Défauts supplémentaires
| N° | Gravité | Page | Description |
|---|---|---|---|
| D-23 | Mineur | /conges | Dates incohérentes : message technique brut de base de données au lieu d'un message français |
| D-24 | Majeur | /conges | Une demande qui chevauche un congé approuvé est acceptée |
| D-25 | Majeur | /conges, /paie | Absence acceptée et approuvée dans un mois déjà validé (juin) sans blocage ni alerte |
| D-26 | Majeur | /conges, /mon-espace | Aucun contrôle de solde : les soldes deviennent négatifs, la maternité de 98 j est acceptée |
| D-27 | Majeur | Congés → Paie | Un congé non payé approuvé ne réduit pas le bulletin tant qu'une absence en heures n'est pas saisie dans Présences ; double saisie source d'oublis |
| D-28 | Mineur | /paie/{id} | Pas de moyen clair de remettre un mois « Calculée » en brouillon ; le bouton « Annuler » ne réagit pas |
| D-29 | Mineur | /paie/ajustements, /mon-espace | Saisies invalides refusées sans message d'erreur |
| D-30 | Majeur | Paie / Prêts | Retenue de prêt non plafonnée : net négatif, aucun contrôle de préparation |
| D-31 | Majeur | /mon-espace | Aucune limite sur le montant d'un acompte |
| D-32 | Mineur | /demandes, Paie | Un acompte approuvé n'a aucun effet automatique sur la paie |
| D-33 | Mineur | /mon-espace | « Mes demandes : Aucune demande » alors qu'il existe des demandes de congé approuvées |

Nettoyage à prévoir (données de test créées) : demandes « Sim - … » du salarié QA0011, prêt « Sim - prêt scolarité » (QA0011) et prêt « Sim - prêt supérieur au net » (QA0012, Soldé), absence 8 h de QA0011 au 14/09/2026, traitement « Décembre 2026 ». Les mois Juillet à Octobre ont été recalculés (125 bulletins, état « Brouillon » sur les lignes).

## 12. Bloc B-2 : seuils orange de « Mon équipe » (compte manager)
Données saisies dans Présences par le compte rh : QA0011 absence 8 h les 28, 29, 30/10 puis les 04, 05, 06/11 ; QA0005 maladie 8 h le 03/11 et heures supplémentaires 20 h le 04/11.

| ID | Observé | Résultat |
|---|---|---|
| B-2a | Avec les saisies du 28/10 au 03/11 : tout reste à 0 dans « Présence » (les affectations de l'équipe datent du 04/11 et l'écran ignore les présences antérieures à la date d'affectation) | À noter (D-34) |
| B-2b | Avec les saisies du 04/11 au 06/11 : QA0011 affiche 3 absences (orange) ; QA0005 affiche 20 h sup (orange) | PASS (seuils 3 absences et 20 h respectés) |
| B-2c | QA0005 affiche « 1 » absence alors qu'une seule ligne d'heures sup a été saisie sans cocher « Présent » : une ligne enregistrée sans « Présent » compte comme absence non justifiée | À noter (D-35) |

| N° | Gravité | Page | Description |
|---|---|---|---|
| D-34 | Mineur | /mon-equipe | La section « Présence » ne compte que les présences postérieures à la date d'affectation du salarié à l'équipe : l'historique des 30 jours est vide après un changement de manager. À confirmer comme comportement voulu |
| D-35 | Mineur | /presences, /mon-equipe | Enregistrer une ligne (heures sup, maladie) sans cocher « Présent » compte une absence non justifiée |

Rappel : ces données de présence de test (QA0011, QA0005) sont conservées à la demande de l'utilisateur ; nettoyage plus tard.

## 13. C-03b : poste prévu « À pourvoir » (compte rh)
Action : dans l'organigramme (filtre « Directions »), menu de l'unité « QA Exploitation » → « Prévoir un poste à pourvoir… » : poste TECHNICIEN, effectif prévu 15. Message : « Poste prévu enregistré pour « QA Exploitation » : il apparaît « à pourvoir » tant qu'il n'est pas occupé. »

| ID | Action | Attendu | Observé | Résultat |
|---|---|---|---|---|
| C-03b | Simulation (non appliquée) : rattacher un salarié au poste TECHNICIEN à QA Exploitation | « Effectif avant/après » et « À pourvoir avant/après » | Effectif 13 → 14 ; TECHNICIEN · QA Exploitation : à pourvoir 15 → 14 | PASS |

| N° | Gravité | Page | Description |
|---|---|---|---|
| D-36 | Mineur | Organigramme / Simulation | Le formulaire de poste prévu annonce « postes à pourvoir = effectif prévu − salariés rattachés », mais le calcul compte uniquement les salariés du même poste : avec 13 salariés QA sans poste, il reste 15 à pourvoir et non 2 |
| D-37 | Mineur (données) | Générateur QA | Les salariés QA n'ont aucun poste renseigné, ce qui empêche de tester le pourvoi d'un poste avec eux ; à ajouter dans `scripts/qa-reset-scenario.ps1` |
| D-38 | Mineur | Simulation | Les listes de salariés n'affichent ni matricule ni unité (nombreux homonymes : « Khady N'Diaye » ×5, « Élimane Kane » ×6) ; impossible de distinguer les personnes (cf. D-01, D-11) |
Le poste prévu TECHNICIEN dans QA Exploitation est conservé (données de test).

## 14. Rattachement des 8 services QA aux directions QA (compte rh)
Correction du constat initial (« aucun chemin simple dans l'interface ») : le chemin existe. Organigramme → filtre « Directions » → menu de l'unité → « Modifier (nom, responsable…) » → champ « Dépend de ».

| Service | Direction de rattachement | Résultat |
|---|---|---|
| QA Exploitation | QA Direction Exploitation Mine | OK |
| QA Laboratoire | QA Direction Production Usine | OK |
| QA Maintenance | QA Direction Production Usine | OK |
| QA Logistique | QA Direction Logistique Transport | OK |
| QA Finance | QA Direction Finance Comptabilité | OK |
| QA Ressources humaines | QA Direction RH Paie | OK |
| QA Sécurité | QA Direction HSQE | OK |
| QA Administration | QA Direction Générale | OK |

Vérification après rechargement : « Dépend de » conservé pour les 3 services contrôlés (Exploitation, Sécurité, Administration). QA Direction Commerce Achats n'a aucun service (aucun service QA correspondant). Le compteur « 19 anomalie(s) » (salariés sans lien hiérarchique) est inchangé : il ne dépend pas du rattachement des unités.
Remarque (mineur, D-39) : la liste « Dépend de » mélange directions, services et unités réelles, sans indiquer le type, et ne propose pas de matricule/type pour les homonymes.

## 15. Sécurité et accessibilité : inscription et focus clavier
| ID | Action | Observé | Résultat |
|---|---|---|---|
| S-1 | Écran de connexion → « Créer un compte », soumission avec une adresse fictive (aucun compte créé) | Message « Inscription fermée : création de compte sur invitation admin uniquement ». Le serveur refuse l'inscription (SIGNUP_ENABLED=false par défaut, réponse 403) | PASS |
| G-4c | Indicateur de focus clavier (revue du code, `index.css`) | Contour 2 px (#0f6e6a) avec décalage défini pour le focus clavier ; champs avec anneau de focus | PASS (revue de code, non vérifié visuellement) |

| N° | Gravité | Page | Description |
|---|---|---|---|
| D-40 | Mineur | Connexion | Le lien « Pas encore de compte ? Créer un compte » et le texte « Le premier compte créé pourra se déclarer administrateur dans Paramètres » restent affichés alors que l'inscription est fermée : message trompeur, et risque si l'inscription était ouverte par erreur (SIGNUP_ENABLED=true) sur une base sans administrateur. Masquer le lien quand l'inscription est fermée |

## 16. Validation d'un mois et bulletins du salarié (F-9, F-10)
Période de test : « Décembre 2025 » (mois passé, inexistant, créé pour l'occasion). Calcul : 99 bulletins, dont QA0011 (brut 546 000 F).

| ID | Rôle | Action | Observé | Résultat |
|---|---|---|---|---|
| F-15 | paie | Envoyer Décembre 2025 en revue | « En revue » | PASS |
| F-16 | admin | Approuver la paie | Refus : « Validation impossible : 23 contrôle(s) bloquant(s) doit/doivent être résolu(s) ». Le contrôle de préparation liste 23 salariés réels (S0002…) « actifs sans structure salariale : aucun bulletin possible » | BLOQUÉ (par les données réelles) |
| F-9 | — | Validation complète d'un mois et séparation saisie/validation | Non réalisable sans modifier les structures salariales de salariés réels ; non fait | NON TESTÉ |
| F-10a | salarié | /mes-bulletins | « Aucun bulletin disponible » avec un message clair en français, alors que des bulletins validés d'autres salariés existent (Janvier, Février, Juin 2026) | PASS |
| F-10b | salarié | Lecture directe de la table `salary_slips` par l'API REST avec son jeton | 0 ligne (isolation par RLS) | PASS |

| N° | Gravité | Page | Description |
|---|---|---|---|
| D-41 | Mineur | /paie/gouvernance | Le blocage d'approbation cite 23 salariés sans structure salariale, mais la liste n'est affichée que partiellement (« + 116 autre(s) ») et le message de refus ne dit pas où les corriger |
| D-42 | À trancher | /paie | Un mois peut être créé et calculé avant la date d'embauche/structure de salariés actifs ; le calcul produit 99 bulletins sur 125 et laisse l'erreur au moment de l'approbation seulement |

État laissé : le traitement « Décembre 2025 » est « En revue » (test, à supprimer ou remettre en « Calculée » lors du nettoyage). Décembre 2026 reste « Approuvée ».

## 17. Structures salariales des 23 salariés réels, Décembre 2025 et cascade de retour (05/11/2026)

Correction de l'état laissé en section 16 : Décembre 2025 est désormais **Validée** (122 bulletins).

| ID | Action | Observé | Résultat |
|---|---|---|---|
| F-16b | Reculer à la date d'entrée la date de début de l'affectation de structure salariale des 23 salariés réels (S0001–S0018, S0020–S0023, S0026), montants inchangés | 23 mises à jour acceptées ; le contrôle ne signale plus « sans structure salariale » | PASS |
| F-17 | Remettre Décembre 2025 « En revue » en « Calculée » | Refusé : « Remettez d'abord à l'état Calculée les mois suivants déjà validés » (Janvier à Juin 2026) | PASS (garde-fou correct) |
| F-18 | Cascade : Juin (26 paiements à annuler, case de confirmation), Mai et Avril (Clôturée → « Rouvrir » → Réouverte), Mars (Payée), Février, Janvier | Tous revenus en « Calculée » ou « Réouverte » ; les paiements de Juin et de Mars ont été annulés | PASS |
| F-19 | Recalculer Décembre 2025 puis le contrôler | 122 bulletins, 0 erreur, 122 alertes | PASS |
| F-9 | Validation d'un mois par le préparateur | Décembre 2025 (préparé par le compte paie) validé par l'admin sans étape d'approbation. Janvier à Juin 2026 (préparés par l'admin) : la validation exige un motif de dérogation journalisé (« Séparation des tâches : la personne qui a préparé cette paie ne peut pas la valider ») | PASS (séparation des tâches appliquée ; dérogation admin motivée) |
| F-20 | Remise en état de Janvier à Juin 2026 | Janvier, Février, Mars, Avril, Mai, Juin à l'état « Validée » ; paiements de Mai (26) et Juin (26) rétablis (mode espèces, référence d'origine) | PASS partiel |

Constats :
| N° | Gravité | Page | Description |
|---|---|---|---|
| D-43 | Majeur | /paie/{id} | Un mois « Calculée » passe directement à « Validée » : aucune approbation enregistrée (`approved_by` vide, table `payroll_approvals` vide pour Décembre 2025), alors que le parcours « En revue → Approuvée » existe |
| D-44 | Majeur | /paie/{id} | Un mois « Réouverte » n'offre ni « Recalculer » ni « Remettre en Calculée » (REVERTIBLE exclut ce statut) : seule une action API le débloque |
| D-45 | Majeur | Paie | Recalculer un mois ancien (avril, mai) ajoute 99 bulletins QA « Brouillon » à côté des 26 bulletins réels déjà validés ; le calcul des mois passés n'est pas cantonné à son effectif d'origine |
| D-46 | Mineur | /paie/{id} | La fenêtre de validation n'affiche le champ « Motif de la dérogation » qu'après un premier clic sur « Valider » ; l'interface met plusieurs secondes à refléter les changements d'état |
| D-47 | Majeur | Paie | Remettre en « Calculée » un mois « Payée » annule les paiements sans sauvegarde préalable : les paiements de Mars n'ont pas pu être rétablis (date et références d'origine inconnues) |

État laissé : Décembre 2025 à Juin 2026 « Validée » ; Juillet à Novembre « Calculée » ; Décembre 2026 « Approuvée ». Les clôtures de Mars, Avril et Mai ne sont pas rétablies (Mars sans paiements, Avril sans paiements enregistrés). Sauvegarde des paiements dans le navigateur : `backup_salary_payments` (52 lignes).

### Mise à jour finale (05/11/2026) : retour à l'état d'origine
- Paiements de Mars rétablis pour les 26 salariés réels : espèces, date **28/03/2026** (date présumée : paiement le 28 du mois, selon la consigne de l'utilisateur), référence « Reprise recette : date présumée 28/03 ».
- Mars, Avril et Mai : passés « Payée » puis « Clôturée » (Avril n'a aucun paiement enregistré et a pourtant pu être marqué payé : D-48, mineur, la clôture ne vérifie pas la présence de paiements).
- État final : Décembre 2025, Janvier, Février, Juin « Validée » ; Mars, Avril, Mai « Clôturée » ; Juillet à Novembre « Calculée » ; Décembre 2026 « Approuvée ».

## 18. Synthèse finale de la recette (05/11/2026)

### Résultat par bloc
| Bloc | Périmètre | Verdict | Commentaire |
|---|---|---|---|
| A | Accès par rôle (salarié, manager, rh, paie, admin) | **PASS** | Menus et adresses directes conformes pour les 5 rôles ; refus corrects (redirections). Point à confirmer : le rôle paie voit « Salariés », « Organigramme » et « Paramètres » |
| B | Manager, « Mon équipe » | **PASS** | Périmètre, absence de montants/prêts, seuils orange (3 absences, 20 h sup.) respectés. Réserve D-34/D-35 |
| C | Simulation d'organisation | **PASS** | C-01 à C-07 et C-03b réussis ; lot appliqué et organisation restaurée ; attachement des 8 services par « Dépend de » |
| D | Organigramme et recherche | **PASS avec réserves** | Recherche par nom et matricule correcte ; D-01 (matricule absent des listes), D-03 (salarié sorti affiché actif), D-08 (illisible à 125 salariés) |
| E | Congés et demandes | **PASS fonctionnel, FAIL règles métier** | Circuit à deux niveaux, séparation des tâches (E-4) et vue salarié corrects ; aucun contrôle de chevauchement, de solde ni de mois validé (D-24, D-25, D-26) |
| F | Paie | **PASS avec défauts majeurs** | Calcul, contrôles, séparation des tâches (F-9), isolation des bulletins (F-10) corrects ; défauts D-19, D-30, D-43, D-44, D-45, D-47 |
| G | Transversal (mobile, formats, clavier, déconnexion, inscription) | **PASS** | Aucun défilement horizontal à 400 px, montants formatés, déconnexion sûre, inscription fermée ; D-12 (menu mobile), D-40 (lien « Créer un compte ») |

48 défauts consignés (D-01 à D-48) : environ 14 majeurs, le reste mineurs.

### Les cinq problèmes à traiter en priorité
1. **D-30 : retenue de prêt non plafonnée.** Un prêt de 5 000 000 F donne un net de −3 948 133 F sans erreur ni alerte au contrôle. Plafonner la retenue au net disponible et ajouter un contrôle bloquant « net négatif ».
2. **D-43 : validation sans approbation.** Un mois passe de « Calculée » à « Validée » sans approbation enregistrée (table `payroll_approvals` vide). Imposer « En revue → Approuvée » avant la validation, ou supprimer le raccourci.
3. **D-19 : bouton « Approuver la paie » inversé.** Affiché au rôle paie (qui est refusé) et masqué au rôle rh (seul autorisé) : un compte rh ne peut pas approuver depuis l'écran.
4. **D-24, D-25, D-26 : congés sans contrôles métier.** Chevauchement accepté, absence acceptée dans un mois déjà validé, soldes négatifs, maternité de 98 jours sans contrôle. Ajouter les contrôles à la saisie et à l'approbation.
5. **D-27 : un congé non payé n'alimente pas la paie.** Il faut en plus saisir les heures dans Présences, ce qui est une double saisie source d'oublis. Alimenter automatiquement les variables du mois à l'approbation du congé.

À suivre juste après : D-44 (aucun bouton pour débloquer un mois « Réouverte »), D-45 (le recalcul d'un mois passé ajoute des bulletins QA), D-47 (annuler un mois « Payé » efface les paiements sans sauvegarde), D-01 (matricule absent des listes), D-31 (acompte sans plafond).

### Données de test conservées (nettoyage à prévoir)
Demandes « Sim - … » et prêts QA0011/QA0012, absence du 14/09, présences de QA0011/QA0005, bulletins QA ajoutés aux mois de Janvier à Mai, Décembre 2026 « Approuvée », Décembre 2025 « Validée » (mois de test), poste prévu TECHNICIEN, affectations de structure reculées pour les 23 salariés réels. Aucune donnée supprimée.

## 19. Simulation de l'année 2025 et complément de Mars, Avril, Mai, Juin, Juillet 2026 (05/11/2026)

Méthode : traitements créés par l'API (même insertion que l'écran « Nouveau traitement »), calculés par `run_payroll_entry`, validés, payés **le 28 du mois** (espèces, référence « Simulation recette : paiement au 28 »), puis marqués « Payée » et « Clôturée » par `try_transition_payroll_entry`.

| Mois | Bulletins | Brut (F) | Net (F) | État final |
|---|---|---|---|---|
| 2025-01 | 102 | 79 697 645 | 60 647 802 | Clôturée |
| 2025-02 | 106 | 81 780 545 | 62 297 865 | Clôturée |
| 2025-03 | 106 | 81 824 245 | 62 326 989 | Clôturée |
| 2025-04 | 108 | 83 852 145 | 63 865 690 | Clôturée |
| 2025-05 | 116 | 84 884 248 | 64 966 296 | Clôturée |
| 2025-06 | 116 | 84 961 248 | 65 019 422 | Clôturée |
| 2025-07 | 118 | 86 706 088 | 66 312 257 | Clôturée |
| 2025-08 | 119 | 87 958 488 | 67 173 002 | Clôturée |
| 2025-09 | 121 | 89 384 688 | 68 271 361 | Clôturée |
| 2025-10 | 122 | 90 728 308 | 69 281 337 | Clôturée |
| 2025-11 | 122 | 90 802 408 | 69 332 429 | Clôturée |
| 2025-12 | 122 | 90 855 982 | 69 369 133 | Validée (non payée) |
| 2026-03 / 04 / 05 | 125 | ≈ 92,0 / 92,1 / 92,2 M | ≈ 70,3 / 70,4 / 70,5 M | Clôturée, tous payés |
| 2026-06 | 125 | 91 375 533 | 69 622 412 | Payée |
| 2026-07 | 125 | 92 401 144 | 70 556 180 | Payée (validé puis payé) |

Contrôles : 0 erreur bloquante sur les 11 mois de 2025 (seule alerte « sans variables du mois » pour tous les salariés), aucun net nul ou négatif, effectif croissant cohérent avec les dates d'entrée (102 en janvier → 122 en octobre), montée régulière de la masse salariale.

| ID | Observé | Résultat |
|---|---|---|
| F-23 | Calcul de 11 mois en ~1 s chacun (100 à 122 bulletins) | PASS |
| F-24 | Les 23 salariés réels sont calculés dès Janvier 2025 grâce aux affectations reculées | PASS |
| F-25 | Valider un mois « Calculée » par l'API sans approbation ni motif : accepté pour les 11 mois | FAIL (confirme D-43) |
| F-26 | Insérer des paiements sur des mois **Clôturée** (Mars, Avril, Mai 2026) : accepté | FAIL (D-49) |
| F-27 | Marquer « Payée » puis « Clôturée » un mois dont tous les bulletins ont été payés | PASS |

| N° | Gravité | Page / base | Description |
|---|---|---|---|
| D-49 | Majeur | Base `salary_payments` | Des paiements peuvent être ajoutés à une période déjà « Clôturée » (insertion REST acceptée) : la clôture ne gèle pas les paiements |
| D-50 | Mineur | Données | Décembre 2025, Janvier et Février 2026 sont « Validée » sans paiement alors que les mois suivants sont payés et clôturés : aucun contrôle de continuité (un mois ne devrait pas être clôturé tant qu'un mois antérieur n'est pas payé) |
| D-51 | À trancher | Paie | Les bulletins de 2025 sont calculés avec la structure salariale de 2026 (affectation reculée) : aucun historique de salaire réel avant 2026 |

### D-52 : tableau de bord annuel incomplet après paiement et clôture (constaté le 05/11/2026)
| N° | Gravité | Page / base | Description |
|---|---|---|---|
| D-52 | Majeur | Tableau de bord annuel (« Masse salariale validée par mois »), livre de paie, variation du net, journal | Seuls les traitements à l'état « Validée » étaient comptés. Dès qu'un mois passait « Payée » ou « Clôturée », il disparaissait du graphique et des cumuls annuels ; en 2025, seul Décembre (resté « Validée ») s'affichait. |

Correctif : migration `db/migrations/20261107100000_mois_valides_payes_clotures.sql` (retour : `db/rollback/20261107100000_mois_valides_payes_clotures_down.sql`) qui élargit le filtre à « Validée », « Payée », « Clôturée » dans `hr_dashboard_year`, `payroll_entry_checks`, `payroll_entry_comparison`, `v_payroll_register` (cumuls des bulletins) et `export_payroll_journal`. Côté interface : `isPayrollValidated()` dans `web/src/lib/api.ts`, utilisée par le livre de paie imprimable, les rapports et la comparaison. Vérification : bascule 2025 → 11 mois + Décembre visibles, total annuel égal à la somme des bulletins (batterie F-22, G-10).

## 20. Blocs H à M : base de données, moteur de paie, sécurité, résilience, parcours (05/11/2026, société unique)

Méthode : appels REST et RPC authentifiés (compte admin) depuis le navigateur intégré, sur la base de test. Périmètre : une seule société, donc K-01 (isolation entre sociétés) est hors périmètre. Correctif D-52 appliqué et vérifié : le graphique 2025 compte les 12 mois, dashboard = somme des bulletins (788 863 584 F, écart 0).

| ID | Test | Observé | Résultat |
|---|---|---|---|
| H-03a | Modifier un paiement d'un mois clôturé | Accepté (200) | **FAIL** (D-49) |
| H-03b | Modifier un bulletin validé d'un mois clôturé | Refusé : « La paie clôturée est immuable ; une réouverture motivée est requise » | PASS |
| H-03c | Modifier le traitement clôturé | Même refus | PASS |
| H-03d | Modifier les variables du mois (`payroll_inputs`) d'un mois clôturé | Accepté (200) | **FAIL** (D-49) |
| H-05 | Trois calculs simultanés d'un même mois | 125 bulletins, 0 doublon | PASS |
| H-06a | Matricule en double | Refusé (contrainte `employees_employee_number_key`) | PASS |
| H-06b/c | Prêt négatif ou sans échéance par modification directe | Refusé : aucune écriture directe sur `loans` (passage obligé par `create_loan`) | PASS |
| H-07 | `audit_verify` | Aucune rupture de chaîne (liste vide) | PASS |
| H-07b | `payroll_snapshots_verify` | Introuvable avec ce paramètre (la fonction n'a pas de paramètre `p_payroll_entry_id`) | À vérifier |
| H-08 | Lecture de 2 775 bulletins sans pagination | 2 775 lignes reçues, aucune troncature | PASS |
| H-09 | Temps unitaires | Registre d'un mois 135 ms, salariés 49 ms, bulletins d'un an 80 ms, tableau annuel 316 ms | PASS |
| H-10 | Fins de mois (28 février 2025) | Périodes correctes | PASS |
| I-02a | Embauche le 11/08 | Bulletin d'août au **salaire plein** (1 296 000 F, comme un mois complet) | **FAIL / à trancher** (D-56) |
| I-02b | Sortie le 20/08 | Bulletin d'août au salaire plein | **FAIL / à trancher** (D-56) |
| I-02c | Recalcul de septembre après la sortie | Un bulletin « Brouillon » de septembre reste pour le salarié sorti | **FAIL** (D-57) |
| I-03 | Barème IR (1 part) à 9 niveaux de salaire (50 000 à 5 000 000 F) | Concordant avec le barème progressif (20/30/35/37/40 %) et l'abattement de 30 % plafonné à 900 000 F | PASS |
| I-03b | Réduction pour charges de famille à 500 000 F | 1,5 part : 10 % de l'impôt ; 2, 3 et 5 parts : 200 000, 400 000, 800 000 F (le minimum légal, pas 20 %, 40 %, 80 %) | **À vérifier** (D-54) |
| I-invariants | Sur 2 777 bulletins : net rémunération = brut − retenues salariales ; net à payer = net rémunération + non imposable − retenues nettes | 0 écart | PASS |
| I-04 | Brut nul ou net négatif | 22 bulletins QA0009 à brut 0 (TRIMF 75 F prélevé, net imposable −75 F) et le net −3 948 133 F de QA0012, sans alerte | **FAIL** (D-30, D-53) |
| F-22 | Dashboard annuel 2025 contre somme des bulletins | 788 863 584 F des deux côtés | PASS |
| I-10/M-04 | `export_ipres_css` | Erreur : « function public.compute_salary_slip(uuid, timestamp without time zone, date) does not exist » | **FAIL** (D-55) |
| M-01 | Création d'un salarié (QA0101), affectation, calcul d'août | Bulletin généré sans erreur | PASS (prorata : voir D-56) |
| M-02 | `sortie_salarie` puis `solde_tout_compte` | Sortie enregistrée (statut « Left », motifs imposés DEMISSION…), solde de tout compte généré | PASS |
| M-04 | `certificat_travail` | Généré ; « en qualité de non renseigné » pour un salarié sans poste | PASS partiel (D-61) |
| J-01 | Lecture anonyme de 8 tables sensibles et de 3 RPC | Toutes refusées (401, `permission denied`) | PASS |
| J-03 | Sans jeton, signature modifiée, `alg=none`, jeton à `exp` passé | 401 dans tous les cas | PASS |
| J-04 | Jeton forgé avec `role=service_role` | 401 (signature invalide) | PASS |
| J-05 | Filtre PostgREST avec guillemet et `OR 1=1`, filtre `or` malformé | Aucun effet (liste vide / erreur 400) | PASS |
| J-06 | Message d'échec de connexion | Identique pour un compte inconnu et un compte existant (« Adresse ou mot de passe invalide ») | PASS |
| J-06b | 14 tentatives rapides | Blocage dès la 2e tentative (429) ; l'inscription est aussi bloquée : « Compte verrouillé suite à trop d'échecs, réessayez dans 1800 secondes » | **À traiter** (D-58) |
| J-07 | En-têtes de sécurité (CSP, HSTS, X-Frame-Options, nosniff) sur l'API et le front | Absents | **FAIL** (D-60, à confirmer sur l'hébergement final) |
| L-02 | 50 requêtes simultanées | Registre : p50 8,3 s, p95 11,3 s ; tableau annuel : p50 7,1 s, p95 12,2 s ; liste des salariés : p95 2,6 s ; 100 % de succès | **FAIL** (D-59) |

| N° | Gravité | Zone | Description |
|---|---|---|---|
| D-49 (complément) | Majeur | Base | Les paiements (`salary_payments`) et les variables du mois (`payroll_inputs`) d'un mois clôturé restent modifiables ; seuls les bulletins et le traitement sont immuables |
| D-53 | Majeur | Moteur | Un salarié à structure salariale nulle (QA0009) reçoit chaque mois un bulletin à brut 0, avec TRIMF 75 F prélevé et un net imposable négatif, sans erreur ni alerte au contrôle |
| D-54 | À vérifier | Moteur | Réduction pour charges de famille égale au minimum légal à partir de 2 parts (200 000 F à 2 parts) au lieu d'un pourcentage de l'impôt (20 % → 261 800 F à 500 000 F) ; à rapprocher du classeur de référence et du CGI |
| D-55 | Majeur | RPC `export_ipres_css` | Appelle `compute_salary_slip(uuid, timestamp, date)`, signature inexistante : l'export IPRES/CSS est inutilisable |
| D-56 | À trancher (majeur si prorata requis) | Moteur | Aucune proratisation à l'entrée ni à la sortie en cours de mois : salaire plein dans les deux cas |
| D-57 | Majeur | Moteur | Le recalcul ne supprime pas les bulletins « Brouillon » des mois suivants d'un salarié sorti ; le contrôle ne le signale pas |
| D-58 | Majeur (exploitation) | API `/auth/v1` | Le verrouillage après échecs semble compter par adresse source, pas par compte : 14 tentatives sur des comptes fictifs ont bloqué toutes les connexions et inscriptions pendant 30 minutes. Derrière un même réseau, un seul utilisateur peut bloquer tous les autres |
| D-59 | Majeur (performance) | Base / API | Sous 50 requêtes simultanées, les lectures du registre de paie et du tableau annuel passent à 7–12 s (contre 135 et 316 ms à l'unité) : pas de marge de charge |
| D-60 | Mineur à vérifier | Front / API | Aucun en-tête de sécurité HTTP ; vérifier sur l'hébergement final (Vercel, proxy) |
| D-61 | Mineur | Certificat / numérotation | « en qualité de non renseigné » sans poste ; `next_employee_number` propose S0199 (série réelle S0001–S0026) ; message de `etat_dgid` sans la liste des types acceptés |

Effets de bord sur la base de test : salarié **QA0101** créé (entré le 11/08/2026, sorti le 20/08/2026, statut « Left ») avec ses bulletins brouillons d'août à décembre ; blocage de connexion de 30 minutes sur l'adresse locale après le test J-06.

### Tests automatisés rejoués (05/11/2026, 13:20)

| Suite | Résultat | Remarques |
|---|---|---|
| `tests/api/isolation.test.mjs` | **10/10** | Premier passage 8/10 : deux **faux positifs du test** (D-62 : le test ignorait le statut de bulletin `Validé` ; D-63 : un manager est aussi salarié et lit ses propres bulletins). Test corrigé ; les politiques RLS (`salary_slips_select` : paie/RH, ou son propre bulletin au statut `Validé`) sont conformes. Statuts réels des bulletins : Brouillon 528, Validé 2249. |
| `tests/api/routes.test.mjs` | **13/13** | Échec initial dû à l'environnement (verrouillage de connexion D-58, puis `docker exec` cassé sur le conteneur API, erreur « setns » de Docker Desktop). Résolu par `docker compose up -d --force-recreate api`. |
| `scripts/verify-payroll.ps1` (août 2026) | **PASS** : 26 bulletins, brut 5 017 834,60, net 4 765 432,33 | Aucun écart avec la référence `backups/payroll-baseline-2026-08.json`. |

Constats complémentaires : D-62 et D-63 sont classés « faux positifs » ; D-58 est confirmé (30 min de blocage par adresse source après des échecs répétés) ; incident Docker `exec` sur l'API à ajouter aux notes d'exploitation.

### Correction D-49 (05/11/2026, 13:35)

Migration `20261107110000_d49_periode_cloturee_paiements_variables.sql` (rollback fourni) : triggers `salary_payments_closed_guard` et `payroll_inputs_closed_guard` refusant toute écriture sur une période « Clôturée » (« La paie clôturée est immuable »). Test `tests/sql/d49_periode_cloturee.sql` : **OK**. Conséquence : `sync_attendance_to_payroll_inputs` échoue sur un mois clôturé (réouverture nécessaire).

### Correction D-43 (05/11/2026, 13:42)

Migration `20261107120000_d43_approbation_avant_validation.sql` (rollback fourni) : `transition_payroll_entry` refuse « Calculée » → « Validée » pour tout rôle sauf `admin`, qui doit saisir un motif (audit `validation_derogatoire`). Test `tests/sql/d43_approbation.sql` : **OK**. Note : appliquée via Claude Code sur le poste.

