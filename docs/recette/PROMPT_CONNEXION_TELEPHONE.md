# Prompt Claude Code — Connexion des salariés par numéro de téléphone (SMS Twilio Verify)

Tu travailles dans `C:\IT-Mozaic\soma-rh-main` (React/Vite/TS, Postgres, Supabase en ligne, passerelle locale `api/server.mjs`). Langue : français.
Lis d'abord : `docs/CONNEXION_TELEPHONE_SALARIES.md` (cadrage validé), `web/src/pages/LoginPage.tsx`, `web/src/lib/api.ts`, `db/migrations/20261028170200_security_rls.sql` (`has_role`, `my_employee_id`), `db/migrations/20261212090000_documents_supabase_storage.sql` (exemple de fonctions et de politiques).

## Décisions (ne pas rediscuter)
SMS par Twilio Verify · mot de passe 6 à 8 caractères alphanumériques (`^[A-Za-z0-9]{6,8}$`) · identité par adresse technique `<numéro sans +>@tel.soma-rh.invalid` · en ligne d'abord, passerelle locale avec SMS simulé ensuite · mode actuel (e-mail) inchangé · ce compte n'a que l'accès salarié, aucun autre rôle possible.

## Règles
- Branche `feat/connexion-telephone`, un commit par étape. Migrations horodatées dans `db/migrations/` avec `db/rollback/…_down.sql` et test `tests/sql/…`. Nouvelles tables : RLS activée, aucune politique (accès `service_role` seul), index sur les clés étrangères.
- Aucune clé Twilio ni `service_role` dans le code, les fichiers suivis ou le navigateur : secrets des fonctions Supabase seulement (`TWILIO_ACCOUNT_SID`, `TWILIO_AUTH_TOKEN`, `TWILIO_VERIFY_SID`). Ne jamais journaliser un code SMS ni un mot de passe en clair en mode production.
- Ne rien lancer sur Supabase en ligne sans que le propriétaire l'ait demandé ; fournir les commandes (`supabase functions deploy`, `supabase secrets set`).
- Avant de finir : `npm run check`, `npm run build`, tests SQL, e2e concernés, `menu.spec.ts` et `a11y.spec.ts` au vert.

## Étapes
1. **Base** : fonction `public.normalize_sn_phone(text)` (E.164 `+221`, préfixes mobiles 70/75/76/77/78, formats saisis `77 123 45 67`, `00221…`) ; tables `employee_phone_accounts`, `phone_auth_attempts`, `phone_auth_tickets` ; fonction `public.employee_for_phone(text)` (un seul salarié actif, sinon null et alerte RH en cas de doublon) ; déclencheur sur `employees` : si `phone_personal` change, suspendre le compte ; si l'état devient « Sorti », désactiver le compte.
2. **Verrou de rôles** : déclencheur `before insert or update` sur `user_roles` qui lève une exception pour tout utilisateur présent dans `employee_phone_accounts` ; `has_role()` renvoie faux pour ces comptes ; `admin_link_employee`, `claim_first_admin` et les fonctions d'administration des comptes refusent ces utilisateurs. Tests SQL : tentative d'attribution de chaque rôle (admin, rh, paie, manager) refusée, y compris par un administrateur.
3. **Edge Functions** (`supabase/functions/phone-auth-request`, `-verify`, `-set-password`) : conformes à §4 du cadrage ; réponses identiques que le numéro existe ou non ; limites : 3 SMS par heure et par numéro, plafond par IP, 5 vérifications de code maximum ; ticket à usage unique, 10 min, stocké haché ; validation serveur du mot de passe ; création du compte par l'API d'administration (adresse technique confirmée, `app_metadata.account_kind='employee_phone'`) et liaison `employees.user_id` ; journal d'audit (création, réinitialisation, échecs).
4. **Blocage par compte** : après 5 échecs de mot de passe, blocage de 15 min pour les comptes téléphone (mécanisme à choisir et documenter selon le forfait Supabase ; à défaut, vérification dans l'Edge Function de connexion `phone-auth-login` qui remplace l'appel direct pour ce mode).
5. **Écran** : onglet « Téléphone » dans `LoginPage.tsx` : connexion (numéro + mot de passe), création de compte (numéro, code, mot de passe, confirmation), mot de passe oublié ; saisie du numéro tolérante (espaces, `+221`), messages en français, accessibilité (libellés, focus, clavier numérique `inputmode`). Mention d'information sur les données personnelles. L'e-mail reste inchangé.
6. **Passerelle locale** : mêmes trois routes dans `api/server.mjs` avec un fournisseur SMS simulé (code écrit dans le journal du conteneur, activé seulement si `SMS_MODE=simule`).
7. **Tests** : SQL (normalisation, unicité, verrou de rôles, suspension), unitaires (validation du mot de passe), e2e Playwright avec SMS simulé (création, connexion, oubli, numéro inconnu, numéro en double, tentative d'accès à `/paie`, `/parametres`, `/salaries` refusée, isolation : le salarié ne voit que ses données).
8. **Documents** : guide utilisateur (page « Se connecter avec mon téléphone »), mise à jour de `README.md`, `docs/CONNEXION_TELEPHONE_SALARIES.md` (statuts), compte rendu `docs/recette/CONNEXION_TELEPHONE_RESULTATS.md`.

## Livrable
Compte rendu par étape (fait, partiel, reporté), fichiers modifiés, migrations, commandes à exécuter par le propriétaire (déploiement des fonctions, secrets Twilio, application des migrations sur Supabase), points ouverts.
