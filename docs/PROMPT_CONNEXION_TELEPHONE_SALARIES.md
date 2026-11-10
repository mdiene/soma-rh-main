# Prompt Claude Code — Connexion des salariés par numéro de téléphone (validation par l'administrateur, SMS plus tard)

Tu travailles dans `C:\IT-Mozaic\soma-rh-main` (React 18/Vite/TS, Postgres + RLS, deux déploiements : **local** = passerelle `api/server.mjs` + PostgREST ; **en ligne** = Supabase Auth + Vercel, projet `mzhdwdpesbggxtjxxgab`). Langue : français. Contexte : Sénégal.

## 0. À lire d'abord
`CLAUDE.md`, `README.md` (modes local / en ligne), `api/server.mjs` (section `/auth/v1/*`, limitation 30 connexions / 15 min / IP, verrouillage D-58), la page de connexion dans `web/src/`, `web/src/lib/api.ts`, les fonctions `has_role`, `my_employee_id`, `admin_link_employee`, `admin_list_users`, `claim_first_admin`, la table `user_roles`, la table `employees` (colonnes `phone_personal`, `phone_work`, date de naissance, matricule), le **système d'alertes / notifications existant de l'administrateur** (tableau de bord, cloche ou page d'alertes : le retrouver, ne pas en créer un second), `docs/recette/simulation-200/DOSSIER_DE_REPRISE.md` (RPR-03 : verrouillage de connexion). Utiliser `graphify query` pour explorer.

## 1. Besoin (décision du propriétaire, 10/11/2026)
En plus de la connexion actuelle (e-mail + mot de passe), un **salarié** peut se connecter avec **son numéro de téléphone** et accéder à **son espace personnel** (mêmes règles et mêmes droits qu'un compte salarié aujourd'hui : « Mon espace », « Mes bulletins », demandes, congés… sans rien de plus).

**Pour ne pas être bloqué par un opérateur SMS, la confirmation se fait d'abord par l'administrateur dans l'interface.** L'envoi de SMS viendra plus tard, sans refaire le reste.

1. **Demande d'accès** : sur l'écran de connexion, « Se connecter avec mon numéro de téléphone » → « Créer mon accès ». Le salarié saisit son numéro (celui de sa fiche, `employees.phone_personal`). Si le numéro correspond à une fiche, une **demande de connexion** est enregistrée et apparaît dans **les alertes de l'administrateur**. Le salarié voit : « Votre demande a été enregistrée. L'administrateur doit l'autoriser. Revenez saisir votre numéro plus tard. »
2. **Autorisation** : l'administrateur ouvre l'alerte, voit le salarié (nom, matricule, numéro masqué, date de la demande) et **coche la case « Autoriser l'accès par téléphone »** (ou refuse). Action journalisée.
3. **Création du mot de passe** : une fois autorisé, le salarié **saisit de nouveau son numéro** et accède à la page où il crée son mot de passe : **5 à 8 caractères, lettres et chiffres uniquement, aucun caractère spécial** (`^[A-Za-z0-9]{5,8}$`).
4. **Connexion ensuite** : numéro de téléphone + mot de passe.
5. **Réinitialisation** : même parcours (demande → autorisation de l'administrateur → nouveau mot de passe). Une autorisation ne sert qu'une fois.
6. **Verrou de rôle** : ce mode de connexion ne donne accès **qu'au compte salarié**. Aucun autre rôle ne doit pouvoir lui être attribué, ni par l'interface, ni par l'API, ni par SQL direct passé par un rôle applicatif (admin compris).
7. **Plus tard (hors périmètre, à préparer)** : validation par SMS. Prévoir un paramètre `phone_access_validation` = `admin` (défaut, seule valeur implémentée) | `sms` (non implémenté), et l'interface `SmsProvider` vide, pour qu'on puisse brancher un opérateur sans changer le parcours ni le schéma.

## 2. Exigences de sécurité (non négociables)
- **Pas d'énumération** : la demande répond toujours le même message (« Votre demande a été enregistrée… ») que le numéro existe ou non ; aucune demande n'est créée si le numéro ne correspond à aucune fiche ou correspond à plusieurs fiches (dans ce cas, alerte discrète à l'administrateur : « numéro partagé »).
- **Normalisation du numéro** : format E.164 `+221XXXXXXXXX` (9 chiffres ; mobiles 70, 75, 76, 77, 78 ; accepter la saisie avec espaces, `00221`, `+221`). Comparer sur la forme normalisée. Un numéro = un compte.
- **Risque sans SMS** : qui connaît le numéro d'un collègue pourrait, après autorisation, créer le mot de passe à sa place. Mesures obligatoires : (1) l'autorisation est **à usage unique et valable 48 h**, puis expire ; (2) la page de création du mot de passe n'est ouverte qu'au numéro autorisé **et** demande une **seconde information connue du seul salarié, contrôlée sur la fiche (date de naissance)** — paramétrable (`phone_access_second_factor`, activé par défaut) ; (3) l'alerte affiche à l'administrateur de quoi vérifier l'identité (nom, matricule, service) et il autorise **après avoir contacté le salarié** ; (4) alerte à l'administrateur si le même numéro est redemandé après autorisation.
- **Limites** : au plus 3 demandes par numéro par 24 h et 10 par IP par heure ; au plus 5 essais de seconde information avant verrouillage 30 min **du numéro** ; verrouillage progressif des tentatives de connexion **par couple numéro + IP** (pas de blocage collectif : voir RPR-03).
- **Mot de passe court (5 à 8)** : compensé par les limites ci-dessus et le refus des mots de passe triviaux (numéro de téléphone, 12345, 00000, identique au nom, au matricule ou à la date de naissance). Si la plateforme impose un minimum supérieur à 5 (Supabase Auth : vérifier `minimum_password_length`), choisir l'option qui permet de respecter 5 à 8 (mots de passe gérés par notre fonction serveur) ; si c'est impossible, appliquer le minimum de la plateforme, **le documenter et le signaler dans le compte rendu** — ne pas bloquer le travail pour cela.
- **Journalisation** : audit des événements (demande, autorisation, refus, expiration, mot de passe créé/changé, connexion réussie/échouée, verrouillage) **sans jamais écrire le mot de passe** dans les journaux, la console ou les réponses.
- **Changement de numéro** sur la fiche par RH : le compte téléphone est **désactivé** jusqu'à une nouvelle autorisation.
- **Verrou de rôle côté base** (défense en profondeur) : un compte dont le moyen de connexion est le téléphone ne peut être lié qu'à `user_roles.role = 'salarie'`. Contrainte/déclencheur sur `user_roles` + refus dans `admin_*` et dans toute fonction qui attribue un rôle ; test SQL qui tente d'ajouter `rh`, `paie`, `admin`, `manager` à ce compte et **doit échouer**, y compris en tant qu'admin. Pour donner un autre rôle à une personne, il faudra d'abord créer un compte e-mail distinct.
- **Seul l'administrateur** (`has_role(array['admin'])`) peut autoriser, refuser ou révoquer. Le rôle rh et le rôle paie ne le peuvent pas.
- Le compte est **rattaché à la fiche** (`my_employee_id()`) à la création, sans action manuelle. Les politiques RLS existantes pour le salarié restent la seule source d'accès (ne rien élargir). Les tables de demandes et de jetons ne sont **pas lisibles** par les rôles applicatifs hors fonctions `security definer` et vues réservées à l'administrateur.

## 3. Architecture attendue
Deux déploiements, **un seul contrat** côté interface (`web/src/lib/phoneAuth.ts`) :
- `demanderAcces(telephone)` → réponse neutre ;
- `ouvrirActivation(telephone, secondeInfo)` → si une autorisation valide existe, renvoie un **jeton d'installation** (15 min, usage unique), sinon la même réponse neutre « en attente » ;
- `definirMotDePasse(jeton, motDePasse)` ;
- puis connexion par numéro + mot de passe.

- **En ligne (Supabase)** : comme les codes SMS ne servent plus, privilégier des **fonctions Edge** (`supabase/functions/phone-auth`) ou des fonctions SQL `security definer` appelées en RPC pour la demande et l'activation ; la création de l'utilisateur et la définition du mot de passe passent par l'API admin avec la clé `service_role` en secret de la fonction, jamais dans le front. L'inscription ouverte à n'importe quel numéro reste interdite. Écrire une courte note de décision (`docs/DECISION_CONNEXION_TELEPHONE.md`) : option retenue, gestion du mot de passe 5–8, verrouillage par numéro, évolution vers le SMS (Send SMS Hook de Supabase ou fournisseur direct : Orange/Sonatel, Twilio, Infobip, Africa's Talking, avec coût et délivrabilité), sans rien coder de fournisseur maintenant.
- **Local (passerelle)** : mêmes routes dans `api/server.mjs` (`/auth/v1/phone/request`, `/open`, `/set-password`) et connexion par `/auth/v1/token` avec identifiant téléphone, mêmes limites et même verrouillage que l'existant.
- **Alertes de l'administrateur** : une demande en attente crée une alerte dans le **système d'alertes existant** (type « Demande d'accès par téléphone », lien direct vers l'écran d'autorisation, compteur visible). L'écran liste les demandes (en attente, autorisées, refusées, expirées), avec la case **« Autoriser l'accès par téléphone »**, un bouton « Refuser » et « Révoquer l'accès » pour un compte déjà actif. Prévoir un statut sur la fiche salarié : « Accès par téléphone : non demandé / en attente / autorisé / actif / révoqué ».
- **Interface salarié** : écran de connexion avec deux onglets (« E-mail » / « Téléphone »), parcours en 3 étapes (numéro, [seconde information], mot de passe), messages clairs et neutres, accessibilité WCAG AA (`web/e2e/a11y.spec.ts` reste au vert), **mobile d'abord**. Champ mot de passe avec affichage/masquage et rappel de la règle « 5 à 8 lettres ou chiffres, sans caractère spécial ».

## 4. Règles de travail du projet
- Branche `feat/connexion-telephone`, un commit par étape.
- Migration horodatée dans `db/migrations/`, rollback dans `db/rollback/`, test SQL dans `tests/sql/`, application par `docker cp` + `psql -f` puis `notify pgrst, 'reload schema'` ; régénérer `web/src/lib/database.types.ts`. Nouvelles tables : RLS activée, politiques par rôle (`has_role(array['admin'])`), index sur les clés étrangères. La migration doit aussi fonctionner sur Supabase (rôle `postgres`, pas de rôle `soma`).
- Contrôles avant commit : `npm run check`, `npm run build`, `node --test ../tests/unit/*.test.mjs` (ajouter des tests unitaires de normalisation du numéro et de validation du mot de passe), `scripts/test-sql.ps1`, `scripts/verify-payroll.ps1`, `npx playwright test e2e/menu.spec.ts e2e/a11y.spec.ts`.
- Tests e2e du parcours complet : demande → alerte visible chez l'administrateur → autorisation → ouverture par le salarié → mot de passe → connexion ; numéro inconnu (réponse identique, aucune alerte) ; numéro partagé ; autorisation expirée ; autorisation réutilisée (refusée) ; mauvaise seconde information ×5 (verrouillage) ; refus ; révocation ; réinitialisation ; verrou de rôle (un compte téléphone ne voit ni `/paie`, ni `/salaries`, ni `/parametres`) ; isolation (voit uniquement ses données) ; un compte rh ou paie ne peut pas autoriser.
- Ne pas casser la connexion e-mail existante ni ses limites (30 connexions / 15 min / IP). Ne pas commiter de données personnelles ni de secrets.

## 5. Livrables
1. Migrations + rollback + tests SQL ; routes passerelle ; fonctions Edge ou SQL retenues ; `phoneAuth.ts`, écrans salarié et écran/alerte administrateur.
2. `docs/DECISION_CONNEXION_TELEPHONE.md` (options, choix, risques sans SMS et mesures, plan d'évolution vers le SMS).
3. Guide utilisateur : « Demander mon accès par téléphone », « Autoriser une demande (administrateur) », « Mot de passe oublié » (captures Playwright dans `docs/guide-utilisateur/captures-sim/`), et mise à jour de la FAQ.
4. Compte rendu final : ce qui est fait, ce qui reste, tests et résultats, risques résiduels (mot de passe court, usurpation de numéro avant activation) et mesures proposées.

Ne pas attendre de validation pour démarrer : présente un plan court (étapes, fichiers touchés) puis enchaîne. Ne pose une question que pour une décision irréversible.
