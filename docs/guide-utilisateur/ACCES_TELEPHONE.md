# Accès par téléphone — guide utilisateur

Décisions et sécurité : `docs/DECISION_CONNEXION_TELEPHONE.md`.

## Demander mon accès par téléphone (salarié)
1. Sur l'écran de connexion, ouvrez l'onglet **Téléphone**, puis **Créer mon accès**.
2. Saisissez votre numéro (celui de votre fiche, ex. `77 123 45 67`) et envoyez.
   Le message est toujours le même : « Votre demande a été enregistrée. L'administrateur doit l'autoriser. »
3. L'administrateur vous contacte pour vérifier votre identité, puis autorise votre accès (valable 48 h, une seule fois).
4. Revenez sur **Créer mon accès** > **Ma demande est autorisée : continuer**. Saisissez de nouveau votre numéro **et votre date de naissance**.
5. Choisissez votre mot de passe : **5 à 8 lettres ou chiffres, sans espace ni caractère spécial**. Évitez votre numéro, votre nom, votre matricule, votre date de naissance et les suites (12345).
6. Ensuite, connectez-vous avec votre numéro et ce mot de passe : vous accédez à votre espace (mes bulletins, congés, demandes).

## Autoriser une demande (administrateur)
1. La demande apparaît dans les **alertes** du tableau de bord (« Demande d'accès par téléphone »), avec un lien vers **Paramètres > Accès**.
2. Dans le tableau, vérifiez le nom, le matricule, le service et le numéro masqué. **Appelez le salarié** sur le numéro de sa fiche.
3. Cochez **Autoriser l'accès par téléphone**, ou cliquez sur **Refuser**. L'autorisation expire au bout de 48 h.
4. Alertes particulières : « redemandée n fois » (quelqu'un insiste : vérifiez), « numéro partagé » (deux fiches ont le même numéro : corrigez-les, puis cliquez sur *Classer*).
5. **Révoquer l'accès** d'un compte actif : bouton dans « Comptes actifs par téléphone ». Le salarié ne peut plus se connecter.
6. Sur la fiche d'un salarié, sous « Téléphone personnel », le statut est affiché : non demandé / en attente / autorisé / actif / révoqué. Modifier le numéro désactive l'accès jusqu'à une nouvelle autorisation.

## Mot de passe oublié
Même parcours que la demande d'accès : **Mot de passe oublié** > saisir le numéro > attendre l'autorisation de l'administrateur > ressaisir numéro + date de naissance > nouveau mot de passe.

## FAQ
- **« Impossible d'ouvrir l'activation pour le moment »** : la demande n'est pas encore autorisée, a expiré (48 h), ou la date de naissance est inexacte. Après 5 erreurs de date, le numéro est bloqué 30 minutes.
- **Mon numéro n'est pas reconnu** : demandez à la RH de corriger le numéro de votre fiche. Le message reste le même, par sécurité.
- **« Trop d'échecs »** : après 5 mots de passe faux, la connexion est bloquée 1 minute, puis plus longtemps si cela recommence (30 minutes au maximum).
- **Puis-je être manager ou RH avec ce compte ?** Non : ce mode ne donne que l'espace salarié. Un compte e-mail distinct est nécessaire pour un autre rôle.
- **Le numéro change** : la RH modifie la fiche ; l'accès est désactivé et doit être de nouveau demandé.

*Captures d'écran : à produire avec Playwright dans `docs/guide-utilisateur/captures-sim/` une fois le parcours e2e exécuté.*
