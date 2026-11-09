# Rapport vert / rouge — simulation 10 → 200 salariés

Date : 09/11/2026 · Base locale remise à zéro (compte mdiene conservé) · Périodes 2026-01 à 2026-09 clôturées.
Sources : `JOURNAL_PALIERS.md`, `resultats-playwright.jsonl`, run Playwright final (14 tests passés, 5,1 min).

## 1. Synthèse

| Indicateur | Valeur |
|---|---|
| Effectif simulé | 10 → 25 → 50 → 75 → 100 → 125 → 150 → 175 → 200 |
| Conventions couvertes | 11 |
| Périodes de paie clôturées | 9 (janv.–sept. 2026) |
| Bulletins calculés au dernier palier | 200, 0 erreur |
| Rôles exercés | admin, rh, paie, rh+paie, manager, salarié (comptes distincts) |
| Parcours complet jusqu'à Clôturée sans contournement | Oui, à partir de la correction D-64 |
| Contrôles Playwright (dernier état par cas) | 42 verts, 2 rouges (voir §3) |

Verdict : le cœur du calcul est **conforme** (HS, absence, prime, retenue, paniers vérifiés au franc près au palier 2) et le volume de 200 salariés passe. Les écarts sont des **défauts de parcours, d'alignement écran/base et de sécurité**, pas des erreurs de calcul.

## 2. Matrice des cas d'usage

| Domaine | Cas | Statut |
|---|---|---|
| Embauche | Fiche + déclaration d'embauche + structure, 200 salariés, 11 conventions | VERT |
| Embauche | Structure par le compte RH | ROUGE (lecture seule, RPR-06) |
| Embauche | Affectation avant fin de chargement (erreur brute) | ROUGE (RPR-06) |
| Calcul | HS 15 %, absence, prime, retenue, paniers (palier 2) | VERT |
| Calcul | Volumes 75 à 200 bulletins, 0 erreur | VERT |
| Calcul | Salarié sans structure : « Calculée » avec 0 bulletin, sans message | ROUGE (RPR-01) |
| Calcul | Entrée en cours de mois payée à plein tarif | ORANGE (RPR-09) |
| Workflow | Calculée → Revue → Approuvée → Validée → Payée → Clôturée à comptes distincts | VERT (avec compte rh+paie) |
| Workflow | Approbation par un profil à un seul rôle depuis l'écran | ROUGE (RPR-02) |
| Workflow | Garde de période M-1 | VERT après D-64 (corrigé) |
| Workflow | Validation directe, dérogation sans champ motif | ROUGE (RPR-04) |
| Workflow | Réouverture avec motif, annulation, retraitement | VERT |
| Workflow | Période Réouverte sans bouton Recalculer | ROUGE (RPR-05) |
| Workflow | Remise en Calculée, Recalculer sur paie non clôturée | VERT |
| Droits | 20 comptes, isolation salarié/manager, refus d'écriture, refus calcul sans rôle, période clôturée immuable | VERT |
| Droits | Pages interdites (mgr, sal) | VERT |
| Droits | RH voit la page Gouvernance sans pouvoir agir | ROUGE (RPR-02) |
| Sécurité | Verrouillage de connexion par adresse source | ROUGE (RPR-03) |
| Prêts | Plafond de retenue par rh/paie | ROUGE (RPR-08) |
| Référentiels | Départements, postes, quarts | ORANGE (RPR-10) |
| Ergonomie | Boutons hors écran, Entrée, texte d'accès, catégorie à 0 F | ROUGE mineur (RPR-11) |
| Performance | Enregistrement variables 175, chargement 200 | ORANGE (RPR-15) |

## 3. Les 2 rouges du suivi Playwright

- `UC-INTERDIT-rh-/paie/gouvernance` : la page s'affiche pour le RH. Ce n'est pas une fuite : le RH est approbateur en base. L'attendu du test était faux ; la vraie anomalie est qu'il ne peut pas agir (RPR-02). Le test a été retiré de la liste.
- `UC-CALC-P5` : 99 bulletins sur 100 au premier run (S0375 sans structure, erreur de l'outil de test). Corrigé ensuite (100 bulletins) mais non réenregistré. Passe à VERT au prochain rejeu.

## 4. Points à arbitrer par le métier

1. D-56 : prorata pour entrée en cours de mois (oui/non, base de calcul).
2. Qui approuve : le rôle rh seul, ou rh+paie ? Le dossier de reprise propose d'aligner l'écran sur la base (RPR-02).
3. Plafond de prêt : admin seul, ou admin/rh/paie (RPR-08).
4. Paiements individuels (`salary_payments`) : obligatoires avant « Payée » ou non (RPR-14).
5. Base de fin de campagne : conserver la base simulée ou restaurer `backups\soma-rh-20261109-141842.dump`.

## 6. Décisions du propriétaire (09/11/2026)
1. Prorata D-56 : payé au prorata des jours travaillés (entrée et sortie en cours de mois).
2. Approbation de la paie : administrateur et détenteur du rôle paie (le rôle rh n'approuve pas) ; l'écran est la référence, la base est à aligner (RPR-02).
3. Plafond de retenue sur prêt : variable de configuration, 1/3 par défaut, modifiable par salarié (RPR-08).
4. Paiements individuels : en attente ; proposition dans `PROPOSITION_PAIEMENTS_INDIVIDUELS.md`.
5. Base simulée conservée pour le moment.
6. Migration vers Supabase : sauvegarde de l'ancienne base, chargement d'une base vide, puis migration des données existantes.
Les correctifs sont cadrés dans `PROMPT_CORRECTIFS_RPR.md`.
