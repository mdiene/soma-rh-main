# Proposition — Assistant de création d'un salarié (wizard)

Date : 12/11/2026 · Statut : **proposition, rien n'est codé** · Sélection interactive des composants : https://claude.ai/artifact/Cg2NQmHk1CLSLs9kcSeK9K (page privée ; « Copier ma sélection » renvoie le choix dans la conversation).

## 1. La demande
Lors de la création d'un salarié :
1. un **assistant** qui accompagne la saisie, avec une **fenêtre (modale) par section**, validée une à une jusqu'à la fin ;
2. des **questions qui facilitent la saisie**, étape par étape ;
3. à la fin, une **revue** puis la **sauvegarde** ;
4. pouvoir **choisir les composants** à construire, avec leurs explications.

## 2. Ce que fait l'application aujourd'hui (constaté)
- `/salaries/nouveau` : une longue page de 5 sections (Identité, Coordonnées, Famille et fiscalité, Contrat et classification, Paiement), puis **Créer le salarié**. Le matricule est attribué automatiquement.
- Après la création, sur la fiche : **déclaration d'embauche** (référence, date), puis **Structure salariale** (rôle paie ou administrateur ; le RH la voit en lecture seule), plafond de prêt, historique des emplois.
- Constats de la campagne du 12/11/2026 qui motivent l'assistant :
  - l'embauche se fait **en trois temps** et par **deux rôles** ;
  - enregistrer la structure avant la fin de son chargement donne « null value in column structure_id … violates not-null constraint » ;
  - la section « Structure salariale » est parfois absente sur une fiche neuve (RPR-16) ;
  - des **homonymes** existent en base (deux « Aissatou Cissé ») : un contrôle de doublons doit avertir sans bloquer ;
  - les dossiers sont presque vides (18 pièces manquantes par salarié) ;
  - les règles dépendent du type de contrat (CDI, CDD, journalier, stage, apprentissage, prestation) mais le formulaire pose les mêmes questions à tous.

## 3. Analyse de la demande
| Point | Lecture | Conséquence |
|---|---|---|
| « Modal en fenêtre par section » | Une fenêtre large avec un en-tête d'étapes, une section à la fois. Le composant `Modal` existe déjà (focus, Échap). | Réutiliser `Modal` ; prévoir le plein écran sur téléphone (option). |
| « Valider une à une » | Validation locale de chaque section, sans écriture en base tant que tout n'est pas validé. | Pas de fiche à moitié créée ; il faut un moyen de **reprendre** (brouillon). |
| « Questions facilitant la saisie » | Questions conditionnelles (type de contrat, famille, cadre) et aides « pourquoi cette question ». | Moteur de règles de saisie testable (unitaire), partagé avec l'ancien formulaire. |
| « Revue et sauvegarde » | Récapitulatif par section avec « Modifier », alertes, puis création. | Écriture **atomique** recommandée (création en une opération). |
| Rôles | Le RH crée la fiche, la paie affecte la structure. | Étape rémunération **déléguée** (tâche et notification) si l'utilisateur n'a pas le rôle paie. |

## 4. Parcours cible
1. *(option)* Écran de départ : documents à avoir sous la main.
2. **Identité** → 3. **Coordonnées** → 4. **Famille et fiscalité** → 5. **Contrat et classification** (questions selon le contrat) → 6. **Paiement** → 7. **Déclarations et affiliations** → 8. **Rémunération** (paie seulement, sinon tâche déléguée) → 9. *(option)* **Pièces du dossier** → 10. **Revue et sauvegarde**.
3. Après sauvegarde : ouvrir la fiche, créer un autre salarié, imprimer la fiche.
- Chaque étape : en-tête d'étapes, **Précédent** / **Valider et continuer**, champs obligatoires bloquants, aide « Pourquoi cette question ? ».
- Un lien **Saisie complète** garde l'ancien formulaire pour les habitués.

## 5. Composants (sélectionnables dans l'artefact)
Niveaux : **Socle** (indispensable), **Recommandé**, **Option**, **Plus tard**. Effort : S ≈ 1 j, M ≈ 3 j, L ≈ 6 j (ordre de grandeur).

| Groupe | Composants (niveau, effort) |
|---|---|
| A. Structure | A1 Fenêtre d'assistant à étapes (socle, M) · A2 Progression et retour sur étape validée (reco, S) · A3 Plein écran téléphone (option, S) · A4 Saisie complète conservée (reco, S) |
| B. Étapes | B1 Identité (socle, S) · B2 Coordonnées (socle, S) · B3 Famille et fiscalité (socle, M) · B4 Contrat et classification (socle, M) · B5 Paiement (socle, S) · B6 Déclarations et affiliations (reco, S) · B7 Rémunération (reco, M) · B8 Pièces du dossier (option, M) · B9 Revue et sauvegarde (socle, M) |
| C. Questions guidées | C1 Selon le type de contrat (socle, M) · C2 Parts fiscales (reco, M) · C3 Cadre ou non-cadre (reco, S) · C4 Choix guidé de la catégorie (reco, M) · C5 « Pourquoi cette question ? » (reco, S) · C6 Écran « documents sous la main » (option, S) |
| D. Contrôles | D1 Validation par étape (socle, S) · D2 Doublons (reco, M) · D3 Formats (reco, S) · D4 Aperçu des alertes de conformité (option, M) · D5 Cohérence contrat/convention/catégorie (reco, M) |
| E. Enregistrement | E1 Brouillon navigateur (reco, S) · E2 Brouillon serveur (plus tard, L) · E3 Création en une opération (reco, L) · E4 Trace au journal (reco, S) · E5 Pré-remplissage depuis une candidature (option, M) |
| F. Rôles et suites | F1 Rémunération déléguée à la paie (reco, M) · F2 Actions après sauvegarde (reco, S) · F3 Documents générés (option, L) · F4 Créer l'accès du salarié (option, M) |
| G. Qualité | G1 Tests de bout en bout (socle, M) · G2 Tests des règles et de la base (reco, M) · G3 Page du guide et captures (socle, S) · G4 Accessibilité (socle, S) |

Dépendances gérées par l'artefact : cocher un composant ajoute ceux dont il dépend ; décocher en retire les dépendants.

## 6. Architecture proposée
- **Interface** : `web/src/components/EmployeeWizard/` (une fenêtre, un composant par étape, un hook d'état partagé) ; point d'entrée sur `/salaries/nouveau` (bouton **Assistant** / **Saisie complète**).
- **Règles de saisie** : module pur testable (questions, branchements, parts proposées), partagé avec le formulaire complet pour éviter deux jeux de règles.
- **Brouillon** : `localStorage` (E1), effacé à la sauvegarde et à l'abandon ; données personnelles : aucune copie dans Git.
- **Écriture** (E3) : fonction `create_employee_from_wizard(...)` en base, une transaction (fiche + déclaration d'embauche + structure si autorisé), droits par `has_role`, trace au journal ; migration datée avec retour arrière, `notify pgrst, 'reload schema'`, types régénérés (`database.types.ts`). Sans E3, l'assistant réutilise les écritures actuelles (fiche, puis structure) avec le risque déjà constaté.
- **Rôles** : étape Rémunération visible pour paie et administrateur ; sinon création d'une tâche et d'une notification « structure salariale à affecter » (F1).

## 7. Phasage
| Phase | Contenu | Effort indicatif |
|---|---|---|
| 1 — Socle | A1, B1 à B5, B9, C1, D1, G1, G3, G4 | ≈ 24 j |
| 2 — Recommandé | A2, A4, B6, B7, C2 à C5, D2, D3, D5, E1, E3, E4, F1, F2, G2 | ≈ 36 j |
| 3 — Options | A3, B8, C6, D4, E5, F3, F4 | ≈ 20 j |
| Plus tard | E2 | ≈ 6 j |

Les efforts sont des ordres de grandeur à affiner après le cadrage ; la phase 1 seule fournit un assistant utilisable.

## 8. Qualité et critères d'acceptation
- Parcours complet joué par Playwright pour chaque type de contrat, avec captures pour le guide ; cas d'erreur (champ obligatoire, doublon, RIB invalide).
- `menu.spec.ts` et `a11y.spec.ts` au vert ; navigation clavier de bout en bout ; focus piégé dans la fenêtre.
- Test SQL de la création atomique (droits par rôle, annulation complète en cas d'erreur) ; `verify-payroll.ps1` sans écart.
- Page **Embaucher un salarié** du guide réécrite ; `guide.test.mjs` et `guide.spec.ts` au vert.

## 9. Risques et points d'attention
| Risque | Parade |
|---|---|
| Deux chemins de saisie qui divergent | Règles de saisie dans un module unique, utilisé par l'assistant et le formulaire complet. |
| Règles fiscales encore « à confirmer » | L'assistant **propose** les parts, ne les impose jamais ; mention ◐ dans l'aide. |
| Fiche créée à moitié | Écriture atomique (E3) ou, à défaut, reprise explicite avec l'état affiché. |
| Données personnelles dans le brouillon | Effacement systématique ; rien en Git ; durée de vie limitée. |
| Droits RH / paie | Tests par rôle ; étape déléguée (F1) plutôt qu'un droit élargi. |
| Doublons et homonymes | Avertir, montrer la fiche existante, ne pas bloquer. |

## 10. Décisions attendues
1. Composants à retenir (artefact) : socle seul, recommandé, ou sélection sur mesure.
2. **Création en une opération (E3)** : accord pour une migration, ou assistant sans migration dans un premier temps.
3. **Étape rémunération** : intégrée pour la paie et déléguée pour le RH (F1) — confirmé ?
4. **Âge minimal et pièces obligatoires** : valeurs à donner par la RH ; aucune valeur légale n'est inventée dans l'assistant.
5. Faut-il garder la **Saisie complète** (A4) à long terme ?

## 11. Prochaine étape
Après le choix des composants : un plan détaillé par phase (`/ecc:plan`), la migration éventuelle revue par `ecc:database-reviewer`, puis développement sur une branche dédiée avec un commit par étape.

## 12. Décisions du propriétaire (12/11/2026)
1. **Une fenêtre (modale) par section**, validée une à une jusqu'à la fin ; **assistant utilisable de bout en bout** (phase 1 de la section 7 comme base).
2. **Calcul du salaire depuis la saisie** (nouveau composant **H1**) : dans l'étape Rémunération, le champ *Salaire net* ouvre par un clic une fenêtre de calcul (celle du simulateur net / brut : « Net à payer souhaité » → « Trouver le sursalaire »). Une fois calculé et validé, le résultat (sursalaire et brut obtenus) est **repris directement dans la fiche en cours de saisie**. Réutiliser la logique de `SimulatorPage` (même moteur que la paie, rien n'est enregistré par la simulation). Effort estimé : M (≈ 3 j). Dépend de B7 (étape Rémunération) et donc de F1 pour le rôle RH.
3. **Saisie complète conservée (A4)** : à la création, l'utilisateur choisit le **type de saisie**, avec assistant ou sans assistant (formulaire actuel). Le choix est proposé à l'ouverture de « Nouveau salarié » (deux boutons) et mémorisé comme préférence de l'utilisateur.
4. **Pièces du dossier (B8)** : dans un premier temps, l'assistant **liste les pièces et on les coche** (reçue / non reçue). Leur **téléversement** se fait ensuite par l'interface déjà opérationnelle (Dossiers administratifs), sans changement.
5. Restent à trancher : création en une seule opération en base (E3, migration) et étape rémunération déléguée à la paie pour le RH (F1).

Impact sur le phasage : la phase 1 inclut désormais **A4** (choix du type de saisie) et **B8 en liste cochable** ; **H1** s'ajoute à la phase 2 (avec B7). Effort supplémentaire : A4 ≈ 1 j, B8 liste ≈ 1 j, H1 ≈ 3 j.

## 13. Réalisé le 12/11/2026 (branche `feat/assistant-creation-salarie`, non fusionnée)
Décisions du propriétaire du soir : création en une seule opération (E3) **oui** ; le RH sans rôle paie ne peut pas affecter la structure (F1) **oui**.

| Composant | État |
|---|---|
| A1 fenêtre par section, A2 retour sur étape validée, A4 choix avec/sans assistant (mémorisable) | fait |
| B1 à B9 (identité, coordonnées, famille, contrat, paiement, déclarations, rémunération, pièces, revue) | fait |
| C1 questions selon le contrat (CDD, stage, apprentissage : dates obligatoires ; prestation ; journalier) | fait |
| D1 validation par étape, D3 contrôles de format (avertissements) | fait |
| E3 création atomique (`create_employee_from_wizard`), E4 trace au journal d'audit | fait (migration `20261217090000`) |
| F1 rémunération réservée au rôle paie ; RH seul : fiche créée sans structure et message de délégation | fait ; **pas de notification dédiée** (le salarié reste signalé par le bandeau « sans bulletin » de la paie) |
| H1 calcul du sursalaire à partir du net en fenêtre, repris dans la saisie | fait (`simulate_net_for_draft`, matricule non consommé) |
| B8 pièces : liste cochable | fait (table `employee_document_receipts`) ; téléversement inchangé |
| G1 à G4 tests, accessibilité, guide | fait (SQL, unitaires 9, e2e 4, a11y, page du guide) |
| Non réalisés | C2 parts fiscales proposées, C3 à C6, D2 doublons, D4, D5, E1 brouillon navigateur, E2, E5, F2 à F4, A3 plein écran |

Constats : le calcul du net exige un salarié existant côté base (le solveur lit la fiche) : la simulation insère puis annule dans une sous-transaction. Les textes d'aide des champs passent de `ink-muted` à `ink-soft` (contraste) dans toute l'application.
**Avant déploiement en ligne** : appliquer la migration `20261217090000_assistant_creation_salarie.sql` sur Supabase, sinon l'assistant échoue (la saisie complète reste utilisable).

## 14. Lot 2 réalisé le 12/11/2026 (branche `feat/assistant-creation-lot2`)
| Composant | État |
|---|---|
| D2 détection des doublons (mêmes nom, prénom et date de naissance, ou même numéro de pièce) | fait : avertissement avec lien vers la fiche, jamais bloquant |
| E1 brouillon dans le navigateur (7 jours, effacé à la création et à l'abandon, conservé par la croix) | fait |
| A3 plein écran sur téléphone (`Modal`, option `fullscreenOnMobile`) | fait |
| F1 notification dédiée à la paie | fait sous forme d'**alerte du tableau de bord** « Structure salariale à affecter par la paie » (fonction `structure_pending_alerts`, migration `20261218090000`), visible des comptes RH et paie ; pas de message individuel |
| C2 parts fiscales proposées | **mécanisme fait, règle non fournie** : `PARTS_RULE` vaut `null`, aucune proposition n'est affichée et une note l'indique. Aucune valeur légale n'est codée. |

**Décision attendue du propriétaire pour C2** : fournir la règle de calcul des parts (base, supplément si marié(e), supplément par enfant, plafond, et si les parts TRIMF suivent les parts IR) avec sa source légale, ou confirmer de garder la saisie manuelle. L'application de la règle tient en une constante de `web/src/lib/employeeWizard.ts` et ses tests.
**Avant mise en ligne** : appliquer la migration `20261218090000_alerte_structure_a_affecter.sql` sur Supabase, sinon le bloc « Alertes réglementaires » des comptes RH et paie affiche « Alertes indisponibles ».
