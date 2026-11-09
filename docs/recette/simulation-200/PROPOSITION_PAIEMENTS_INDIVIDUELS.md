# Proposition — enregistrement des paiements (à valider, non implémentée)

Constat : une période passe en « Payée » puis « Clôturée » sans aucun paiement individuel (`salary_payments`). Or le règlement réel peut être un virement groupé, un chèque unique remis à un tiers ou des espèces distribuées.

## Option recommandée : paiement par lot, détail par salarié facultatif
1. **Mode de règlement par défaut sur la fiche salarié** : virement, chèque, espèces, mobile money (Wave, Orange Money).
2. **Lot de paiement par période** (`payroll_payment_batches`) : période, mode, montant total, référence (n° de virement ou d'ordre, n° de chèque, n° du procès-verbal de remise), date, preuve (pièce jointe), auteur.
3. **Passage à « Payée »** : exiger au moins un lot dont la somme couvre le net de la période, ou un motif d'écart signé. Le détail par salarié reste facultatif et se génère automatiquement depuis le mode par défaut (état d'émargement pour les espèces, fichier de virement pour la banque).
4. **Espèces** : état d'émargement imprimable à faire signer ; la clôture exige la date de retour de l'état signé.
5. **Chèque unique pour plusieurs salariés** : un lot de mode « chèque » avec la liste des bénéficiaires et le total, sans obligation de ligne par salarié.
6. **Contrôle de clôture** : somme des lots = net total (sinon alerte bloquante pour la clôture, dérogation admin motivée).

## Pourquoi
Respecte les pratiques locales, garde une piste d'audit sans alourdir la saisie, et prépare le rapprochement bancaire.

## Autres options écartées
- Obligation d'une ligne par salarié : trop lourd pour les paiements en espèces ou par chèque unique.
- Aucune exigence (situation actuelle) : pas de preuve de paiement à la clôture.
