# Décision — connexion des salariés par numéro de téléphone

Date : 10/11/2026 · Remplace le cadrage `CONNEXION_TELEPHONE_SALARIES.md` (SMS Twilio, 6 à 8 caractères) : décision du propriétaire du 10/11/2026 = **autorisation par l'administrateur d'abord, SMS plus tard, mot de passe de 5 à 8 caractères**.

## Parcours retenu
1. **Demande** (écran de connexion > Téléphone > « Créer mon accès ») : réponse toujours identique. Une demande n'est créée que si le numéro correspond à **une seule fiche active** ; plusieurs fiches (ou numéro déjà pris par un autre compte) = alerte « numéro partagé » pour l'administrateur.
2. **Autorisation** : l'administrateur (et lui seul, pas `rh` ni `paie`) voit la demande dans ses alertes (tableau de bord) et dans Paramètres > Accès, contacte le salarié, coche « Autoriser l'accès par téléphone » ou refuse. Valable 48 h, usage unique.
3. **Activation** : le salarié ressaisit son numéro **et sa date de naissance** (contrôlée sur la fiche) ; il reçoit un jeton de 15 min, puis crée son mot de passe (`^[A-Za-z0-9]{5,8}$`, triviaux refusés).
4. **Connexion** : numéro + mot de passe. **Réinitialisation** : même parcours (nouvelle autorisation).

## Options étudiées
| Sujet | Option retenue | Écartée |
|---|---|---|
| Validation | Administrateur dans l'interface (`phone_access_settings.validation = admin`) | SMS Twilio : dépendance à un opérateur, coût, délai |
| Identité | Utilisateur d'authentification à adresse technique `221771234567@tel.soma-rh.invalid` | Fournisseur « Phone » de Supabase (exige un SMS) |
| Logique | Fonctions SQL `security definer` communes (`phone_access_*`), appelées par la passerelle (local) ou la fonction Edge (en ligne) | Logique dupliquée dans chaque déploiement |
| Mot de passe 5–8 en ligne | Mot de passe d'authentification **dérivé** (HMAC-SHA256 avec secret serveur) et connexion par la route `login` de la fonction Edge | Minimum plateforme (6) : violerait la règle métier |
| Verrou de rôle | Déclencheur sur `user_roles` + refus dans `admin_link_employee`/`claim_first_admin` | Contrôle à l'écran seulement |

## Sécurité (sans SMS)
- **Risque principal** : connaître le numéro d'un collègue ne suffit pas à usurper son accès. Il faut (1) que l'administrateur autorise après avoir contacté le salarié, (2) la date de naissance de la fiche, (3) agir dans les 48 h, une seule fois, (4) rester sous les limites : 3 demandes/numéro/24 h, 10/adresse/h, 30 ouvertures/adresse/h, 5 mauvaises dates puis **numéro verrouillé 30 min**.
- Une **redemande après autorisation** alerte l'administrateur (compteur « redemandée n fois »).
- **Connexion** : verrouillage progressif par couple numéro + adresse (5 échecs = 1 min, puis 2, 4… 30 min max), jamais par adresse seule (RPR-03). Le verrou collectif par adresse reste réservé à la connexion e-mail, inchangée (30/15 min/adresse).
- **Rôle** : le compte téléphone n'a que `salarie`, y compris contre l'administrateur et le SQL direct (test `tests/sql/connexion_telephone.sql`). Conséquence connue : attribuer un rôle `manager` (organigramme) à un salarié qui n'a qu'un accès téléphone est refusé ; il faut lui créer un compte e-mail.
- **Numéro modifié sur la fiche** ou **révocation** : compte désactivé, rôle et rattachement retirés (coupure immédiate des droits), jetons révoqués.
- **Journal** (`audit_log`, table `phone_access`) : demande, autorisation, refus, expiration, ouverture, mot de passe créé/changé, connexions réussies/échouées, verrouillages. Jamais de mot de passe ; adresses IP seulement hachées.
- Tables de demandes/jetons/tentatives : RLS activée **sans politique**, aucun droit pour les rôles applicatifs ; seules les fonctions les lisent.

## Risques résiduels
- Mot de passe court (5–8) : compensé par les limites et le refus des triviaux ; reste plus faible qu'un mot de passe long.
- Usurpation avant activation : possible seulement si l'administrateur autorise sans vérifier **et** que l'attaquant connaît la date de naissance. Mesure : toujours rappeler le salarié sur le numéro de la fiche.
- Un tiers peut verrouiller 30 min l'ouverture d'un numéro en saisissant 5 fausses dates (déni de service ciblé, accepté).
- En ligne, le verrouillage de connexion de la fonction Edge est en mémoire d'instance (meilleur effort).

## Évolution vers le SMS (hors périmètre, préparée)
Le paramètre `phone_access_settings.validation` accepte déjà `admin` (seule valeur implémentée) ou `sms` (refusé par `admin_phone_access_decide`). Brancher un opérateur = remplacer l'étape d'autorisation par l'envoi d'un code dans `phone_access_request`/`open`, sans changer le schéma ni le parcours. Fournisseurs à comparer (coût, délivrabilité Sénégal) : Orange/Sonatel (direct), Twilio Verify, Infobip, Africa's Talking ; côté Supabase : Send SMS Hook. L'interface `SmsProvider` n'est pas codée tant qu'aucun opérateur n'est choisi.

## Déploiement
- **Local** : migration `20261213090000_connexion_telephone.sql`, puis reconstruire l'image `api` (`phone.mjs` ajouté au Dockerfile) et `notify pgrst, 'reload schema'`.
- **En ligne** : même migration (aucun rôle `soma` requis) ; `supabase secrets set PHONE_AUTH_PEPPER=<32+ caractères aléatoires>` ; `supabase functions deploy phone-auth --no-verify-jwt` ; `VITE_PHONE_AUTH_URL=https://<projet>.supabase.co/functions/v1/phone-auth` dans Vercel. **La fonction Edge n'est ni déployée ni testée contre Supabase** (code seulement).
