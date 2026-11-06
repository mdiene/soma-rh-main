# SOMA-RH — Projet « Modules métiers » : mise en place, développement, formulaires, expérience utilisateur

Version 1 — 6 novembre 2026. Complète `MODULES_METIER_VERTICAUX_SOMA_RH.md` (spécification v2) et `RESULTATS_RECHERCHE_TEXTES_A_FOURNIR.md`. Aucune valeur légale non confirmée n'est pré-remplie (règle de la spécification §3).

## 1. Principe produit

Un module métier est un **plus** : désactivé, SOMA-RH se comporte exactement comme aujourd'hui (la paie, les bulletins et `verify-payroll` ne bougent pas). Activé, il apporte quatre choses, uniquement pour les salariés rattachés à ce métier :

1. des **champs complémentaires** sur la fiche salarié et le contrat ;
2. des **modèles de postes** et règles de temps dans le planning ;
3. des **éléments de paie** (primes, indemnités, heures converties) saisissables par période ;
4. des **contrôles de conformité** et un **calcul de l'influence sur le salaire** (brut, net, coût employeur), visible avant validation.

## 2. Quels modules, dans quel ordre

| Ordre | Module | Identifiant | Pourquoi maintenant | Statut des textes |
|---|---|---|---|---|
| 1 | **Industrie et mines** (postes continus, rotations, primes de risque et de fond) | `soma-mod-industrie-mines-sn` | SOMA est une société minière : premier cas d'usage réel. Proposition à confirmer : le module n'existe pas encore dans la spécification v2 | Primes et seuils par convention ou accord : à saisir ; équivalences ✖ |
| 2 | **Services, intérim, SAV, professions libérales, enseignement privé** | `soma-mod-services-interim-sn` | Manifeste v0.2.1 déjà écrit ; garde-fous légaux nets (art. 291 à 294) | Taux de fin de mission ✖ (7 % provisoire) |
| 3 | **Sécurité privée et gardiennage** | `soma-mod-securite-gardiennage-sn` | Manifeste v0.1.1 écrit ; forte valeur de contrôle (attestation de régularité sociale) | Seuils d'équivalence ✖ (saisis par le client) |
| 4 | **Transport et chauffeurs** | `soma-mod-transport-sn` | Indemnités de déplacement (CCNI art. 61) | Multiples à saisir |
| 5 | **Nettoyage, voirie, BTP** | `soma-mod-nettoyage-btp-sn` | Primes de salissure, hauteur, risque | Convention de branche ✖ |
| 6 | **Hôtellerie et restauration** | `soma-mod-horeca-sn` | Horaires à coupure, avantages en nature | Arrêté 012914 : logement ◐, nourriture ✖ |

Capacité transversale réutilisée par tous : **déplacements et per diem** (multiples du taux horaire, CCNI art. 61), sans montants pré-remplis.

## 3. Page « Métiers » dans les paramètres

Route `parametres/metiers` (nouvel onglet de `SettingsPage`, rôles `rh` et `admin` ; `paie` en lecture).

**Catalogue** : une carte par module — nom, pictogramme, une phrase de valeur, badge d'état (Brouillon · Prêt · Actif), jauge de complétude des paramètres (✔ confirmé · ◐ secondaire · ✖ à saisir), nombre de salariés rattachés, interrupteur d'activation.

**Assistant d'activation en 4 étapes** (volet latéral, pas de page séparée) :
1. *Aperçu* : ce que le module ajoute (champs, rubriques, contrôles), textes de loi liés avec statut.
2. *Paramètres à saisir* : formulaire généré depuis le manifeste ; chaque champ affiche sa source et son statut ; saisie obligatoire des valeurs ✖ bloquantes, tracée (qui, quand, justificatif facultatif).
3. *Simulation d'impact* : sélection de salariés ou d'une période de test ; avant/après du brut, du net et du coût employeur ; aucune écriture.
4. *Activation* : récapitulatif, confirmation, entrée dans le journal d'audit ; bouton « Désactiver » toujours disponible (les données saisies sont conservées, les bulletins déjà calculés ne changent pas).

**Affectation des salariés** : au niveau du contrat (« métier » = un module actif) ; import en masse par sélection dans la liste des salariés.

## 4. Modèle de données (migrations à écrire)

Toutes les tables : RLS activée, politiques par rôle (`has_role(array['rh'|'paie'])`), index sur les clés étrangères, montants en `numeric`.

| Table | Rôle |
|---|---|
| `module_manifest(module_id, version, status, hash, manifest jsonb, activated_at, activated_by)` | Catalogue et version activée (manifeste signé par hash à l'activation) |
| `module_activation(module_id, enabled, enabled_at, enabled_by, disabled_at)` | État d'activation et historique |
| `module_parameter_value(module_id, param_key, value jsonb, legal_status, source, valid_from, valid_to, entered_by, entered_at)` | Valeurs saisies ou confirmées ; versions datées sans chevauchement (contrainte d'exclusion `gist`) |
| `employee_module_data(employee_id, module_id, data jsonb, valid_from, valid_to)` | Champs complémentaires par salarié (validés par le schéma du manifeste) ; colonne `extra jsonb` évitée sur `employee` pour ne pas toucher au cœur |
| `module_payroll_input(id, employee_id, module_id, period_start, input_code, quantity, amount, note, status)` | Éléments de paie métier saisis par période ; statut brouillon/validé |
| `module_payroll_line(slip_id, module_id, input_code, label, base, rate, amount, is_taxable, is_cotisable)` | Lignes calculées et figées sur le bulletin (traçabilité et explication) |

Fonctions :
- `module_active_for(employee_id, date)` : modules actifs pour un salarié.
- `module_payroll_adjustments(employee_id, period_start, period_end)` : retourne les rubriques métier calculées (graphe de dépendances, paramètre manquant = alerte, pas de valeur inventée).
- `simulate_module_impact(employee_ids, period, module_id)` : appelle `compute_salary_slip` avec et sans les éléments métier, retourne les écarts.
- Modification minimale de `compute_salary_slip` : ajout au brut et aux assiettes des lignes de `module_payroll_adjustments`, sans autre changement. Après cette migration : `verify-payroll` doit rester **identique modules éteints** ; puis `-Save` seulement sur évolution voulue (règle du projet).

Chaque migration : `db/migrations/AAAAMMJJHHMMSS_nom.sql`, appliquée dans `soma-rh-local-postgres-1`, `notify pgrst, 'reload schema'`, puis régénération de `web/src/lib/database.types.ts`.

## 5. Formulaires (générés depuis le manifeste)

Un moteur de formulaire unique (`ModuleForm`) lit les `custom_fields` du manifeste : types texte, nombre, date, booléen, liste, multiple du taux horaire ; validation à la saisie ; aide contextuelle avec l'article de loi ; indicateur de statut légal.

| Module | Fiche salarié et contrat | Saisie par période |
|---|---|---|
| Industrie et mines | Affectation (site, poste, équipe de rotation), habilitations, zone à risque | Postes de nuit, heures de poste continu, primes de fond/risque (taux saisis), astreintes |
| Services / intérim | Statut intérimaire, entreprise de travail temporaire, entreprise utilisatrice, motif de mission (liste de l'art. 293), échéance d'agrément | Heures facturables, trajet, indemnité de fin de mission, per diem |
| Gardiennage | Carte professionnelle, port d'arme, logé sur site, catégorie de poste (équivalence) | Vacations 12 h / 24 h, heures de nuit, présence → effectif, prime de risque, panier de nuit |
| Transport | Permis et validité, véhicule affecté | Trajets, kilomètres, découchés, repas (multiples du taux horaire) |
| Nettoyage / BTP | Habilitations, dotation EPI | Primes de salissure, hauteur, outillage |
| HORECA | Service coupé, avantage nourriture/logement | Avantages en nature (logement par pièce : 33 500 / 20 000 / 13 500 F ◐), service |

## 6. Comment les éléments agissent sur le salaire

1. Saisie d'un élément (ou calcul automatique depuis le planning et les présences).
2. Le moteur de règles du module calcule la rubrique (ex. heures de nuit × taux horaire × taux saisi) et la classe : imposable, cotisable (drapeaux saisis si le texte n'est pas lu).
3. `compute_salary_slip` ajoute la rubrique au brut ; IR, TRIMF, CFCE, IPRES, CSS sont calculés par le cœur comme aujourd'hui (IR 40 % puis 43 % au-delà de 50 M, CFCE 3 %, TRIMF par tranche : lus au CGI 2025).
4. La rubrique est figée dans `module_payroll_line` avec sa base, son taux et sa source ; le bulletin l'affiche dans une section « Éléments métier » et `SlipExplain` en détaille le calcul.
5. Paramètre manquant → `compliance_findings` (« paramètre manquant »), pas de montant inventé ; la paie du salarié concerné est bloquée si la sévérité est « blocking ».

## 7. Expérience utilisateur

Charte existante : palette `ink / paper / river / phosphate / signal`, police Archivo, chiffres tabulaires.

- **Découverte** : catalogue en cartes, état vide pédagogique, pictogrammes `lucide-react`.
- **Activation guidée** : assistant en volet latéral, progression visible, simulation avant/après avec écarts en couleur `signal` (hausse) et `river` (neutre).
- **Fiche salarié** : onglet « Métier » n'apparaît que si un module est actif ; formulaire par sections repliables, enregistrement automatique avec retour visuel, historique des valeurs.
- **Saisie de paie** : grille rapide type tableur (tabulation, collage depuis Excel, ajout en masse), puce d'impact en direct par ligne (« + 18 450 F brut · + 12 300 F net ») et total de la période ; barre de statut (brouillon → validé).
- **Planning** : modèles de postes du module (glisser-déposer), alerte instantanée de dépassement de seuil, code couleur nuit/dimanche.
- **Bulletin** : section « Éléments métier » repliable, infobulle de calcul avec article de loi et statut ✔ ◐ ✖.
- **Conformité** : tableau de bord des alertes par module (attestation à renouveler J-30, mission hors motif, paramètre manquant), lien direct vers le champ à corriger.
- **Détails soignés** : squelettes de chargement, mises à jour optimistes, raccourcis clavier (`g m` ouvre Métiers, `/` recherche), annonces d'accessibilité, contraste AA, navigation clavier complète, impression propre.
- **Mobile** : saisie des présences et consultation en une colonne (usage terrain, gardiens et chauffeurs).

## 8. Plan de réalisation (lots)

| Lot | Contenu | Livrable vérifiable |
|---|---|---|
| M0 | Migrations : `module_manifest`, `module_activation`, `module_parameter_value`, `employee_module_data` ; RLS ; chargeur de manifestes ; journal d'audit | `verify-payroll` identique ; test RLS par rôle |
| M1 | Page Métiers : catalogue, assistant d'activation, saisie des paramètres, simulation à blanc | Activer/désactiver un module de test sans effet sur la paie |
| M2 | `ModuleForm` générique ; onglet « Métier » de la fiche ; champs validés | Création d'une fiche avec champs sectoriels |
| M3 | `module_payroll_input`, moteur de règles à graphe, `module_payroll_adjustments`, branchement dans `compute_salary_slip` ; section bulletin | Cas dorés du module intérim ; `verify-payroll -Save` après revue |
| M4 | Module Services/Intérim complet (contrôles art. 291 à 294, agrément, durée maximale) | Tests INT-T01, INT-T02 + nouveaux |
| M5 | Module Gardiennage (équivalence saisie par le client, nuit, attestation) puis Industrie et mines | Tests GARD-T01 + cas dorés signés par le comptable |
| M6 | Planning métier, saisie rapide en grille, widgets de conformité, mobile | Parcours de bout en bout sur la base de test |
| M7 | Transport, Nettoyage/BTP, HORECA | Un cas doré chacun |

Chaque lot : une migration, un retour arrière, `verify-payroll` avant et après, types régénérés, `graphify update .`, rapport court.

## 9. Tests et critères d'acceptation

- Non-régression : modules éteints, empreinte `verify-payroll` identique à la référence enregistrée.
- Module actif sans paramètre bloquant saisi : alerte `compliance_findings`, aucun montant calculé.
- Cas dorés par module avec résultat attendu signé ; arithmétique en `numeric`, arrondi à l'affichage seulement (`fcfa()`).
- RLS : un rôle `salarie` ne voit aucune donnée de module d'un autre salarié ; `paie` lit, `rh` écrit.
- Désactivation : bulletins déjà calculés inchangés.
- Interface : parcours clavier complet, contraste AA, usage sur écran étroit.
- Données personnelles : aucun fichier suivi par Git ne contient de données de salariés.

## 10. Décisions et prérequis

1. Confirmer le module **Industrie et mines** en priorité 1 (proposition, liée à l'activité de SOMA).
2. Déposer le JO n° 4091 du 09/03/1970 (pp. 257 à 260) pour lire les décrets 70-182, 70-183 et 70-184 ; sinon seuils saisis par le client.
3. Confirmer l'IFC intérim (7 % provisoire) et le plafond AT de la CSS.
4. Valider par un spike le langage d'expression des formules (CEL ou JSONLogic) avant le lot M3.
5. Fournir les conventions de branche au fur et à mesure des modules.
