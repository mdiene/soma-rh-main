# Matrice des cas d'usage — palier 11 (12/11/2026)

Source : `matrice.csv` (une ligne par UC). Base remise à zéro puis rejouée ; dernier résultat de chaque UC dans `resultats-playwright.jsonl`.

**Totaux** : VERT 124 · ORANGE 0 · ROUGE 0 · BLOQUÉ 1 · NON JOUÉ 11

| Bloc | Rôle | Parcours | Statut | Preuve |
|---|---|---|---|---|
| A | admin | Déclarer le premier administrateur ; création de compte ; société, départements, grilles, rubriques | NON JOUÉ | le compte mdiene existait déjà ; écrans affichés seulement |
| A | admin | UC-A-ACCES | VERT | admin /parametres?onglet=acces |
| A | admin | UC-A-BAREMES | VERT | admin /parametres?onglet=baremes |
| A | rh | UC-A-CONNEXION | VERT | formulaire e-mail et onglet Téléphone affichés |
| A | rh | UC-A-EMPLOIS | VERT | 23 emplois créés par l'interface |
| A | admin | UC-A-GRILLES | VERT | admin /parametres?onglet=grilles |
| A | admin | UC-A-LIAISON-COMPTES | VERT | 4 comptes reliés à une fiche par l'interface |
| A | admin | UC-A-MODELES | VERT | admin /parametres?onglet=modeles |
| A | admin | UC-A-RUBRIQUES | VERT | admin /parametres?onglet=rubriques |
| A | admin | UC-A-SOCIETE | VERT | admin /parametres?onglet=societe |
| A | admin | UC-A-TAUX | VERT | admin /parametres?onglet=paie |
| A | rh | UC-TEL-AUTORISATION | VERT | demande visible chez l’administrateur   rh sans case d’autorisation |
| A | rh | UC-TEL-CONNEXION | VERT | activation et connexion   /paie  /salaries  /parametres inaccessibles |
| A | rh | UC-TEL-MAUVAISES-DATES | VERT | après 5 mauvaises dates  la bonne date est refusée |
| A | rh | UC-TEL-REFUS | VERT | demande refusée : activation fermée |
| A | rh | UC-TEL-REINIT | VERT | mot de passe réinitialisé par une nouvelle demande autorisée |
| A | rh | UC-TEL-REUTILISATION | VERT | seconde ouverture sans nouvelle autorisation refusée |
| A | rh | UC-TEL-REVOCATION | VERT | après révocation  la connexion est refusée |
| B | rh | Ayants droit, documents du salarié, avenant, mutation | NON JOUÉ | non explorés |
| B | rh | UC-B-CERTIFICAT | VERT | certificat affiché  statut Left |
| B | rh | UC-B-DOSSIERS | VERT | rh /dossiers-salaries |
| B | rh | UC-B-EMBAUCHE-CDD | VERT | déjà créé lors d'une exécution précédente |
| B | rh | UC-B-EMBAUCHE-COD | VERT | type enregistré : COD |
| B | rh | UC-B-EMBAUCHE-PRESTATION | VERT | type enregistré : PRESTATION |
| B | rh | UC-B-EMBAUCHE-STAGE | VERT | type enregistré : STAGE |
| B | rh | UC-B-FICHE | VERT | fiche S0728 |
| B | rh | UC-B-LISTE | VERT | rh /salaries |
| B | rh | UC-B-NOUVEAU | VERT | rh /salaries/nouveau |
| B | rh | UC-B-RIB | VERT | RIB enregistré sur la fiche |
| B | rh | UC-EMB-P5 | VERT | 0 embauches créées par le compte RH |
| B | rh | UC-EMB-P6 | VERT | 0 embauches créées par le compte RH |
| B | rh | UC-EMB-P7 | VERT | 8 embauches créées par le compte RH |
| B | rh | UC-EMB-P8 | VERT | 25 embauches créées par le compte RH |
| B | rh | UC-EMB-P9 | VERT | 25 embauches créées par le compte RH |
| B | rh | UC-SORTIE | VERT | statut Active  motif DEMISSION |
| C | rh | Heures supplémentaires, vacations et nuit | NON JOUÉ | parcours d'écriture à écrire (écran Présences/Planning non explorés en saisie) |
| C | rh | Planning métier : affectation de postes | NON JOUÉ | écran affiché seulement (UC-C-PLANNING) |
| C | rh | UC-C-PLANNING | VERT | rh /planning |
| C | rh | UC-C-PRESENCES | VERT | rh /presences |
| D | rh | Absences exceptionnelles, maladie, maternité | NON JOUÉ | types de congé non rejoués |
| D | salarié | UC-CONGE-DEMANDE | VERT | état Ouverte |
| D | rh | UC-CONGE-DOT | VERT | dotation de 24 jours ouvrables |
| D | rh | UC-CONGE-VALIDATION | VERT | état final : Approuvée |
| D | manager | UC-D-CONGES-MGR | VERT | mgr_1 /conges |
| D | rh | UC-D-CONGES-RH | VERT | rh /conges |
| D | manager | UC-D-MON-EQUIPE | VERT | mgr_1 /mon-equipe |
| E | paie | Régularisations (hors prêts) | NON JOUÉ | écran affiché seulement (UC-E-AJUSTEMENTS) |
| E | paie/rh | UC-CALC-OCT | VERT | 200 bulletin(s) calculé(s). en 4 s |
| E | paie/rh | UC-CALC-P5 | VERT | 100 bulletin(s) calculé(s). |
| E | paie/rh | UC-CALC-P6 | VERT | 125 bulletin(s) calculé(s). |
| E | paie/rh | UC-CALC-P7 | VERT | 150 bulletin(s) calculé(s). |
| E | paie/rh | UC-CALC-P8 | VERT | 175 bulletin(s) calculé(s). |
| E | paie/rh | UC-CALC-P9 | VERT | 200 bulletin(s) calculé(s). |
| E | paie/rh | UC-E-AJUSTEMENTS | VERT | rh /paie/ajustements |
| E | paie/rh | UC-E-GOUVERNANCE | VERT | rh /paie/gouvernance |
| E | paie/rh | UC-E-SIMULATEUR | VERT | simulateur affiché pour S0728 |
| E | rh | UC-E-TABLEAU-PAIE | VERT | paie / |
| E | paie/rh | UC-E-TRAITEMENTS | VERT | rh /paie |
| E | paie/rh | UC-E-TRAITEMENTS-PAIE | VERT | paie /paie |
| E | paie/rh | UC-E-VARIABLES | VERT | rh /paie/variables |
| E | paie/rh | UC-NOVEMBRE-CALCUL | VERT | paie de novembre créée pour les parcours RPR : 199 bulletin(s) calculé(s). |
| E | paie/rh | UC-PRET | VERT | 1 prêt(s) pour S0888 |
| E | paie/rh | UC-PRET-PLAFOND | VERT | Retenue mensuelle trop élevée : 50000 F (dont 0 F de prêts en cours) pour un plafond de 46170 F (33.3 % du brut de 138513 F). Augmentez le nombre d'échéances ou |
| E | paie/rh | UC-RECALCUL-PRORATA | VERT | ligne RET_PRORATA du bulletin d'octobre de S0883 : 1 |
| E | rh | UC-RPR-01 | VERT | bandeau et refus d'envoi en revue citant S0724 |
| E | rh | UC-RPR-02 | VERT | approuvée par paie2   refus de rh et de la personne qui a préparé |
| E | rh | UC-RPR-04 | VERT | motif obligatoire  bouton désactivé tant que le champ est vide |
| E | rh | UC-RPR-06 | VERT | message de lecture seule pour rh |
| E | rh | UC-RPR-10 | VERT | département créé  visible sur la fiche  supprimé |
| E | rh | UC-RPR-14 | VERT | préfixe et chiffres paramétrables par l’admin  désactivés pour rh |
| E | paie/rh | UC-WORKFLOW-OCT | VERT | état Clôturée |
| E | paie/rh | UC-WORKFLOW-P5 | VERT | Envoyer en revue: bouton « Envoyer en revue » absent | Approuver la paie: bouton « Approuver la paie » absent | Valider la paie: bouton « Valider la paie » abse |
| E | paie/rh | UC-WORKFLOW-P6 | VERT | Envoyer en revue: bouton « Envoyer en revue » absent | Approuver la paie: bouton « Approuver la paie » absent | Valider la paie: bouton « Valider la paie » abse |
| E | paie/rh | UC-WORKFLOW-P7 | VERT | état Clôturée |
| E | paie/rh | UC-WORKFLOW-P8 | VERT | état Clôturée |
| E | paie/rh | UC-WORKFLOW-P9 | VERT | état Clôturée |
| E | paie | Variables du mois : saisie | NON JOUÉ | écran affiché seulement (UC-E-VARIABLES) |
| F | paie | Ordres de virement, bulletins imprimés par lot, rapport de clôture | NON JOUÉ | non exploré |
| F | paie | Paiements par lot | BLOQUÉ | fonction absente (voir PROPOSITION_PAIEMENTS_INDIVIDUELS.md) |
| F | paie | Suivi des cotisations : saisie d'un versement | NON JOUÉ | détail du mois affiché seulement |
| F | paie/rh | UC-F-COMPTABLE | VERT | onglet « Écritures comptables » affiché avec export CSV |
| F | paie/rh | UC-F-COTISATIONS | VERT | rh /paie/cotisations |
| F | paie/rh | UC-F-COTISATIONS-DETAIL | VERT | détail du mois affiché (saisie des versements : non jouée) |
| F | paie/rh | UC-F-ETATS | VERT | rh /etats |
| F | paie/rh | UC-F-ETATS-PAIE | VERT | paie /etats |
| F | paie/rh | UC-F-LIVRE | VERT | onglet « Livre de paie » affiché avec export CSV |
| F | paie/rh | UC-F-PATRONALES | VERT | onglet « Charges patronales » affiché avec export CSV |
| F | paie/rh | UC-F-RESUME | VERT | onglet « État résumé des cotisations » affiché avec export CSV |
| G | rh/admin | Centre de conformité : correction ciblée, constante versionnée, validation par l'administrateur | VERT (e2e conformité 7/7, sans captures dédiées) | web/e2e/conformite.spec.ts |
| G | rh | UC-G-CENTRE | VERT | rh /centre-conformite |
| G | rh | UC-G-MODULES | VERT | rh /modules |
| H | salarié | Demande de modification de profil (Mon profil et demandes) | NON JOUÉ | écran affiché seulement (UC-H-PROFIL-SAL) |
| H | salarié | UC-H-BULLETINS | VERT | sal_1 /mes-bulletins |
| H | salarié | UC-H-CONGES | VERT | sal_1 /conges |
| H | salarié | UC-H-DEMANDES-RH | VERT | rh /demandes |
| H | salarié | UC-H-PROFIL | VERT | rh /mon-espace |
| H | salarié | UC-H-PROFIL-MGR | VERT | mgr_1 /mon-espace |
| H | salarié | UC-H-PROFIL-SAL | VERT | sal_1 /mon-espace |
| I | rh | Simulation de réorganisation, organigramme interactif | NON JOUÉ | écrans affichés seulement |
| I | rh | UC-I-EQUIPE | VERT | 2 affectation(s) manager enregistrée(s) |
| I | rh | UC-I-EQUIPES | VERT | rh /equipes |
| I | rh | UC-I-JOURNAL | VERT | rh /journal |
| I | rh | UC-I-JOURNAL-PARAM | VERT | admin /parametres?onglet=journal |
| I | rh | UC-I-ORGANIGRAMME | VERT | rh /equipes/organigramme |
| I | manager | UC-I-ORGANIGRAMME-EQ | VERT | mgr_1 /equipes/organigramme |
| I | rh | UC-I-PILOTAGE | VERT | rh /pilotage |
| I | rh | UC-I-SIMULATION | VERT | rh /equipes/simulation |
| I | rh | UC-I-TABLEAU | VERT | rh / |
| J | mgr_1 | UC-INTERDIT-mgr_1-/journal | VERT |  |
| J | mgr_1 | UC-INTERDIT-mgr_1-/paie | VERT |  |
| J | mgr_1 | UC-INTERDIT-mgr_1-/parametres | VERT |  |
| J | sal_1 | UC-INTERDIT-sal_1-/journal | VERT |  |
| J | sal_1 | UC-INTERDIT-sal_1-/mon-equipe | VERT |  |
| J | sal_1 | UC-INTERDIT-sal_1-/paie | VERT |  |
| J | sal_1 | UC-INTERDIT-sal_1-/parametres | VERT |  |
| J | sal_1 | UC-INTERDIT-sal_1-/salaries | VERT |  |
| J | rh | UC-ISOLATION-sal_1 | VERT | 6 bulletins visibles |
| J | admin | UC-ROLE-admin-/centre-conformite | VERT |  |
| J | admin | UC-ROLE-admin-/journal | VERT |  |
| J | admin | UC-ROLE-admin-/paie | VERT |  |
| J | admin | UC-ROLE-admin-/paie/gouvernance | VERT |  |
| J | admin | UC-ROLE-admin-/parametres | VERT |  |
| J | admin | UC-ROLE-admin-/salaries | VERT |  |
| J | mgr_1 | UC-ROLE-mgr_1-/conges | VERT |  |
| J | mgr_1 | UC-ROLE-mgr_1-/demandes | VERT |  |
| J | mgr_1 | UC-ROLE-mgr_1-/mon-equipe | VERT |  |
| J | paie | UC-ROLE-paie-/etats | VERT |  |
| J | paie | UC-ROLE-paie-/paie | VERT |  |
| J | paie | UC-ROLE-paie-/paie/gouvernance | VERT |  |
| J | paie | UC-ROLE-paie-/paie/variables | VERT |  |
| J | rh | UC-ROLE-rh-/conges | VERT |  |
| J | rh | UC-ROLE-rh-/dossiers-salaries | VERT |  |
| J | rh | UC-ROLE-rh-/equipes | VERT |  |
| J | rh | UC-ROLE-rh-/salaries | VERT |  |
| J | sal_1 | UC-ROLE-sal_1-/mes-bulletins | VERT |  |
| J | sal_1 | UC-ROLE-sal_1-/mon-espace | VERT |  |
