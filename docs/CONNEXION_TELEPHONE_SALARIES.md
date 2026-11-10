# Connexion des salariés par numéro de téléphone (cadrage)

> **Remplacé le 10/11/2026** par `DECISION_CONNEXION_TELEPHONE.md` et `PROMPT_CONNEXION_TELEPHONE_SALARIES.md` : autorisation par l'administrateur (SMS plus tard), mot de passe de 5 à 8 caractères. Ce document est conservé pour l'historique (piste Twilio Verify).

Date : 10/11/2026 · Décisions du propriétaire : SMS par **Twilio Verify**, mot de passe **6 à 8 caractères alphanumériques** (minimum natif de Supabase Auth), livraison **d'abord en ligne** (Supabase + Vercel), la passerelle locale recevant ensuite un SMS simulé pour les tests.

## 1. Besoin
En plus de la connexion actuelle (e-mail + mot de passe), un salarié peut créer lui-même un compte avec son numéro de téléphone et accéder à **son espace personnel**, avec exactement les droits d'un salarié. Ce mode de connexion ne donne **jamais** d'autre rôle, et aucun rôle ne peut lui être attribué ensuite.

## 2. Parcours
1. **Création du compte** : « Se connecter avec mon téléphone » > « Créer mon compte ». Le salarié saisit son numéro.
2. Si le numéro correspond à **un seul salarié actif** sans compte, un SMS contient un code à 6 chiffres (valable 10 min, 5 essais maximum). Le message à l'écran est toujours le même (« Si ce numéro est enregistré, un SMS vient d'être envoyé »), pour ne pas révéler qui est salarié.
3. Il saisit le code. Si le code est bon, l'écran de **création du mot de passe** s'ouvre (6 à 8 caractères, lettres et chiffres uniquement, sans espace ni caractère spécial).
4. Le compte est créé, relié à sa fiche, et il arrive sur son espace (bulletins, congés, demandes, documents).
5. **Connexions suivantes** : numéro + mot de passe.
6. **Mot de passe oublié** : même chemin que la création (numéro, SMS, code, nouveau mot de passe).

## 3. Règles métier
- Le numéro de référence est `employees.phone_personal`, normalisé au format international `+221 7X XXX XX XX` (formats saisis acceptés : `77 123 45 67`, `00221…`, `+221…`). Mobiles : préfixes 70, 75, 76, 77, 78.
- **Numéro unique** : si deux salariés actifs ont le même numéro, l'inscription est refusée et la RH reçoit une alerte.
- **Rôle unique** : un compte téléphone n'a que l'accès « salarié » (ses propres données, comme `my_employee_id()`). Les rôles `admin`, `rh`, `paie`, `manager` ne peuvent pas lui être attribués (contrainte en base, pas seulement dans l'écran). Une personne qui doit aussi administrer utilise un compte e-mail séparé.
- Changement du numéro sur la fiche : le compte est suspendu jusqu'à nouvelle vérification par SMS.
- Salarié sorti (état « Sorti ») : le compte est désactivé.
- Les actions sont journalisées : création de compte, réinitialisation, connexion échouée répétée, suspension.

## 4. Conception technique (en ligne)
- **Identité** : utilisateur Supabase Auth avec une adresse technique `221771234567@tel.soma-rh.invalid` et `app_metadata.account_kind = 'employee_phone'`. Pas besoin d'activer le fournisseur « Phone » de Supabase. L'écran convertit le numéro saisi en cette adresse.
- **SMS** : Twilio Verify (code, durée de vie, limite d'essais et envoi gérés par Twilio). Les clés Twilio restent dans les secrets des fonctions Supabase, jamais dans l'application web.
- **Edge Functions** (clé `service_role` côté serveur uniquement) :
  - `phone-auth-request` {phone, purpose: `signup` | `reset`} : contrôle de correspondance, limites, envoi du SMS.
  - `phone-auth-verify` {phone, code, purpose} : vérifie le code et renvoie un **ticket** à usage unique (10 min, stocké haché).
  - `phone-auth-set-password` {ticket, password} : valide `^[A-Za-z0-9]{6,8}$`, crée le compte (ou change le mot de passe), lie `employees.user_id`.
- **Tables** (RLS activée, aucune politique : accès par `service_role` seulement) : `employee_phone_accounts` (user_id, employee_id, phone_e164, statut, dates), `phone_auth_attempts` (limitation par numéro et par adresse IP), `phone_auth_tickets`.
- **Verrou de rôles** : déclencheur sur `user_roles` qui refuse tout `insert`/`update` pour un utilisateur présent dans `employee_phone_accounts` ; `has_role()` renvoie faux pour ces comptes ; les fonctions d'administration des comptes (`admin_link_employee`, `claim_first_admin`, etc.) refusent aussi.
- **Écran** : onglet « Téléphone » sur `LoginPage.tsx` (connexion, création, mot de passe oublié) ; l'e-mail reste inchangé.
- **Version locale** : la passerelle `api/server.mjs` reçoit les mêmes trois routes, avec un fournisseur SMS simulé (code affiché dans le journal) pour les tests.

## 5. Sécurité et points d'attention
- Un mot de passe de 6 à 8 caractères reste court : protections obligatoires : 5 échecs de connexion par compte puis blocage 15 min, limites de SMS (3 par heure et par numéro, plafond par IP), réponses identiques qu'un numéro existe ou non, SMS non rejouable.
- Le blocage par compte nécessite un mécanisme dédié (la protection native de Supabase limite par adresse) ; à confirmer selon le forfait Supabase.
- Les numéros sont des données personnelles (loi sénégalaise 2008-12, CDP) : mention d'information au moment de l'inscription.
- Coût : chaque SMS est facturé par Twilio (inscription, réinitialisation). Prévoir une limite mensuelle.
- Détournement de ligne (SIM swap) : un tiers qui contrôle la ligne pourrait réinitialiser le compte. Le compte ne donne accès qu'aux données du salarié ; la RH peut suspendre un compte.

## 6. À fournir par le propriétaire
1. Un compte Twilio avec un service **Verify** (identifiants à enregistrer soi-même avec `supabase secrets set`, sans les envoyer dans le chat) et l'autorisation d'envoi vers le Sénégal.
2. La validation du texte du SMS et de la mention d'information.
3. Les numéros de téléphone à jour sur les fiches (`phone_personal`).
