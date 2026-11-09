# Retour de recherche juridique (L7, HORECA, branches) — tri du 09/11/2026

Le document reçu annonce « texte lu » pour les 18 points, mais **aucun numéro de Journal officiel n'est cité** et plusieurs références (L.84, L.85, L.158…) suivent la numérotation de l'ancien Code. La spécification du Code du travail 2026, lue dans ce projet (`CODE_TRAVAIL_2026_SPECIFICATION_SOMA_RH.md`), donne d'autres numéros et, sur trois points, d'autres valeurs. Règle appliquée : **la spécification lue l'emporte** ; tout le reste est classé « secondaire » (◐) ou « contredit » (✘). Aucun taux n'est codé à partir de ce retour.

Légende : ✔ confirmé par un texte lu dans le projet · ◐ plausible, non confirmé · ✘ contredit par un texte lu ou par une autre source.

| Point | Ce que dit le retour | Ce que dit déjà le projet | Verdict | Suite |
|---|---|---|---|---|
| A1 Certificat de travail | art. L.84 ; dates d'entrée et de sortie, nature et suite des emplois | **art. 140** : exclusivement dates d'entrée et de sortie, nature et dates des emplois successifs, catégorie de la convention ; aucun renseignement tendancieux | ✔ (spec) | **Fait** : migration `20261210090000` (retrait de la naissance et du matricule, ajout de la catégorie). Reste : historique des emplois, preuve de remise |
| A2 Solde de tout compte | art. L.85, dénonciation sous 3 mois, mentions du reçu | art. 200-201 : paiement dès la cessation ; délai de dénonciation non retrouvé dans la spec | ◐ | Citer l'article exact du Code 2026 avant L7-03 |
| B3 Indemnité de licenciement | CCNI art. 34, 25 % / 30 % / 40 % par an, base : moyenne des 12 derniers mois | art. 135, 151 : **renvoi au barème conventionnel** ; art. 197 : base = moyenne 12 mois de **tous** les éléments hors frais ; le code a déjà 25/30/40 en dur | ◐ | Valeur à saisir par convention, à confirmer sur le texte de la CCNI |
| B3 bis Retraite | « mêmes taux que le licenciement » | le code applique **25/30/45/50 %** pour la retraite | ✘ | À trancher avec le texte de la CCNI |
| B4 Préavis | CCNI art. 31 : cadres 3 mois, employés/ouvriers 1 mois | art. 144 : barème par **décret ou convention** | ◐ | À confirmer ; non codé |
| B5 Congés à la sortie | art. L.158, 1/12 des rémunérations | **art. 255** : congé non pris sur les **2 dernières années**, même base que l'allocation de congé (art. 253, 197) | ✔ (spec) | Le retour donne la bonne idée, le mauvais article |
| B6 Fin de CDD | décret 2009-1412, 7 % | **art. 167** du Code : 7 % de la rémunération brute totale | ✔ valeur, source corrigée | Rien à changer |
| B7 Impôt et cotisations | CGI art. 30-2°, exonérations larges | non lu | ◐ | À confirmer au CGI avant tout traitement |
| C8 Acquisition des congés | **2,25 jours ouvrables par mois**, majorations 1/2/3/6 jours à 10/15/20/25 ans | **art. 249 : 2 jours ouvrables par mois** (+1 jeune travailleur, +1 par enfant de moins de 14 ans pour les mères) ; majoration d'ancienneté renvoyée aux règlements ou à la convention | ✘ pour 2,25 | **Rien changé** : 2 jours par mois reste la règle. Barème d'ancienneté à saisir si la convention le donne |
| C9 Report / compensation | art. L.156 | art. 248 (report ≤ 2 ans, 6 jours obligatoires), art. 255 | ✔ en substance | Numérotation à retenir : 248 et 255 |
| C10 Événements familiaux | CCNI art. 28, plafond 10 jours payés | art. 251 : **10 jours ouvrables par an** | ✔ plafond ; ◐ durées par événement | Durées à saisir |
| D11 SMIG | **370,526 F/h**, décret 2019-100, depuis décembre 2019 | l'application utilise 370,526 (point D-003, « à confirmer ») ; un résumé reçu plus tôt donnait 333,807 | ◐ | 370,526 maintenu. **D-003 reste ouvert** tant qu'aucune référence au Journal officiel n'est fournie |
| D12 Équivalences d'heures | gardiennage 56 h, HORECA 45-52 h, transport 48 h (décret 70-183) | ces chiffres avaient déjà été écartés : ils viennent d'un décret **nigérien** (2017-682) | ✘ | Seuils laissés **vides** jusqu'à lecture du décret sénégalais |
| E13 Retenue logement | arrêté 5040 : **1 heure de SMIG par jour et par pièce** | un premier résumé donnait **0,5 heure de SMIG × 30 jours** (≈ 5 558 F/mois) ; 1 h × 30 j ≈ 11 116 F par pièce | ✘ (deux sources secondaires opposées) | L'alerte `retenue_logement_plafond` garde 0,5 h × 30 j **en paramètre** ; à corriger quand le texte est lu |
| E14 Avantages en nature | arrêté 012914 : logement par pièce, nourriture = 1 h de SMIG par jour | un résumé donnait 33 500 / 20 000 / 13 500 F par pièce ; la nourriture n'avait aucun texte | ◐ / ✘ | Forfaits logement conservés en « secondaire » ; **nourriture non codée** |
| E15 Service et pourboires | art. L.119, entre dans l'assiette du congé | art. 197 : primes et avantages entrent dans la base du congé | ◐ | Principe cohérent ; traitement fiscal et social à fournir |
| E16 Convention hôtellerie art. 60 | simple renvoi aux textes en vigueur | — | ◐ | Aucune valeur à reprendre |
| F17 Branches (transport, BTP, gardiennage) | primes et majorations citées sans chiffres sûrs (nuit 50 %, panier 1,5 × SMIG) | majorations de nuit du gardiennage hors périmètre (décision du 30/10) | ✘ | Non codé ; textes de branche toujours à fournir (T-MV-10) |
| F18 CCNI art. 61 | déplacement : 3 × le salaire horaire (2 repas), 5 × (découché) | art. 61 lu dans la copie de 1982, **sans ces multiples** dans nos notes | ◐ | Vérifier les multiples dans la copie de la CCNI du projet, puis les saisir dans les paramètres Transport |

## Décisions attendues de ta part
1. **SMIG** : fournir le décret (numéro et date de publication au Journal officiel) pour clore D-003.
2. **Retenue logement** : lire l'arrêté 5040/ITLS/SM de 1956 pour trancher 0,5 h × 30 jours ou 1 h par jour et par pièce.
3. **Retraite** : confirmer dans la CCNI si les coefficients sont 25/30/45/50 ou les mêmes que pour le licenciement.
4. **Congés** : confirmer que l'art. 249 (2 jours par mois) s'applique bien, le retour proposant 2,25.
5. **CCNI art. 61** : relire les multiples 3 et 5 dans la copie du projet.

## Ce qui a été fait à partir de ce retour
- Certificat de travail aligné sur l'art. 140 (migration `20261210090000_certificat_travail_art140.sql`).
- Aucun autre changement de calcul : L7-03 et L7-05 restent bloqués par le point 3 et par le texte du solde de tout compte (A2).
