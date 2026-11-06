# Mission : monter la base de test à 100 salariés répartis en directions, via la simulation de réorganisation

Tu pilotes le navigateur intégré sur SOMA-RH (interface en français). Tu ne modifies aucun code.

## Contexte
- Application : http://localhost:5173 (API : http://localhost:8000).
- Base de TEST fictive uniquement (salariés QA0011, QA0012, QA0013 et autres). Aucune donnée réelle. Si tu vois des noms ou matricules qui ressemblent à de vrais salariés SOMA (S00xx), arrête-toi et préviens l'utilisateur.
- Connexion : qa-admin@example.test (ou qa-rh@example.test). Le mot de passe est donné par l'utilisateur ; ne jamais l'écrire dans un compte rendu.

## Objectif
Atteindre **100 salariés actifs** répartis dans au moins 6 directions/unités, avec une ligne hiérarchique cohérente, afin de tester l'organigramme, « Mon équipe » et la simulation à volume réaliste.

## Répartition cible (100)
| Direction | Effectif |
|---|---|
| Direction générale | 4 |
| Exploitation / Mine | 30 |
| Production / Usine | 22 |
| Logistique & Transport | 14 |
| Finance & Comptabilité | 8 |
| RH & Paie | 6 |
| HSQE | 8 |
| Commerce & Achats | 8 |

## Étapes
1. Se connecter en rh/admin. Ouvrir /salaries et noter l'effectif actuel et les directions existantes. Créer les unités/directions manquantes (écran Référentiels ou équivalent).
2. Créer les salariés manquants (noms fictifs sénégalais, matricules QA0014 à QA0100 ; contrat, catégorie, date d'entrée et sexe variés). Si une importation (CSV) existe, la préférer à la saisie une par une et noter le résultat. Sinon saisir par lots, en vérifiant le compteur tous les 10.
3. Rattacher chaque salarié à sa direction, puis définir un manager direct : 1 responsable par direction sous la DG, des chefs d'équipe de 5 à 8 personnes sous lui.
4. Passer par /equipes/simulation pour les rattachements : ajouter les changements par lots de 10 à 15, vérifier « Effet sur les équipes » et « Salariés sans lien hiérarchique », puis « Appliquer ». Aucune boucle hiérarchique ne doit être acceptée.
5. Contrôles finaux : effectif = 100 ; chaque direction à l'effectif cible ; 0 salarié sans lien hiérarchique (hors DG) ; organigramme complet, recherche et zoom fonctionnels ; temps de chargement < 5 s sur /salaries, /equipes/organigramme et /mon-equipe (compte manager).
6. Noter tout défaut de performance, d'affichage ou de message d'erreur (texte exact) avec capture.

## Règles
- Ne pas toucher à la paie d'une période réelle, ne pas supprimer de données existantes.
- Ne pas t'arrêter au premier échec : consigne et continue.
- Ne pas créer de comptes de connexion.

## Livrable
Fichier `RESULTATS_SIMULATION_100_AAAA-MM-JJ.md` : effectif avant/après, tableau par direction (cible / obtenu), liste des défauts (gravité, page, étapes, capture `FAIL_<test>.png`), temps de chargement mesurés, et ce qui n'a pas pu être fait. Si tu ne peux pas écrire de fichier, donne le contenu complet dans ta réponse.
