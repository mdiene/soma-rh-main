# SOMA-RH — Architecture métier et modules verticaux sectoriels (Sénégal) — version 2

> Statut : **brouillon de travail v2, 6 novembre 2026**. Reprend le Google Doc « Spécifications d'Architecture & Métier : Modules Verticaux Extensibles pour SOMA-RH » et le PDF « Archive complète de conception » (modules Services/Intérim). Le Google Doc d'origine n'a pas été modifié.
> Ce document **n'est pas un avis juridique**. Chaque valeur réglementaire porte un statut (§3) ; aucune valeur non vérifiée ne doit être pré-remplie dans le produit.
> Dossier projet : `C:\IT-Mozaic\SOMA-RH-local` (sauvegarde locale à faire, voir tâches).

Légende des statuts : **✔** lu dans les pièces du projet (texte officiel ou classeur de référence) · **◐** source secondaire concordante, texte officiel non lu · **✖** non vérifié, contradictoire ou à fournir.

---

## 1. Ce que la version 2 change par rapport au document de départ

| # | Constat sur le document de départ | Pourquoi | Correction dans la v2 |
|---|---|---|---|
| 1 | Équivalences 56 h / 72 h (gardiennage), 50 h / 45 h (HORECA), 48 / 52 / 54 h (transport) présentées comme règles sénégalaises | Le carnet NotebookLM les attribue au **décret nigérien 2017-682** (et à des textes maliens et ivoiriens). Le décret sénégalais de dérogations (70-183 dans le JO du 9 mars 1970) n'a pas été lu | Seuils **paramétrés, vides par défaut** (« à fournir ») tant que le décret sénégalais n'est pas lu. La règle de calcul, elle, est confirmée : les heures au-delà de la durée légale **ou équivalente** sont des heures supplémentaires (Code du travail 2026, art. 244) |
| 2 | Fenêtre de nuit 21 h–5 h dans le manifeste | Le Code du travail 2026, art. 245, fixe la nuit à **22 h–5 h** ; les modalités passent par arrêté du ministre du Travail | Valeur par défaut 22 h–5 h ; l'arrêté d'application est une tâche ouverte |
| 3 | Heures supplémentaires d'équivalence : un seul taux ×1,15 | Le classeur de référence applique 115 % / 140 % / 160 % / 200 % selon la tranche (jour, nuit, dimanche, férié) ; des sources secondaires divergent sur la nuit (140 % contre 160 %) | Taux tirés d'une table `overtime_rates` datée, jamais codés dans la formule (lot G de la feuille de route) |
| 4 | Prime de nuit « 0,50 × taux horaire » codée en dur | Aucune source lue ne la fixe ; le classeur ne la contient pas | Rubrique déclarée, **taux saisi par le client** (convention ou accord), pas de défaut |
| 5 | Retenue BRS 5 % et IFC placées dans le manifeste du module | Contredit le principe DRY du même document (règles légales dans le cœur). La BRS existe déjà dans le cœur (situation `PRESTATION`) | La **BRS reste au cœur**. Le module ne déclare que le type de travailleur concerné. L'IFC intérim reste dans le module (spécifique) |
| 6 | Per diem Dakar 4 500 / 30 000 F, régions 4 000 / 30 000 F, exonérés IPRES/CSS | Montants sans source. La CCNI (art. 61) fixe les indemnités en **multiples du salaire horaire de base** selon repas et nuitée | Matrice de per diem exprimée en multiples du taux horaire catégoriel, à saisir par convention. Pas de montants en FCFA pré-remplis |
| 7 | « Arrêté interministériel n° 11719 du 17/12/2009 » exige une preuve GPS/NTP | L'arrêté n'a pas été retrouvé (recherche web) ; la seule source est l'étude d'architecture précédente. **Aucun texte lu n'impose le GPS** | La preuve géolocalisée devient une **garantie de produit** (justificatif d'audit), non une obligation légale. Le registre légal garde « arrêté 11719 : à fournir » |
| 8 | Décret 2009-1412 « Art. 10 » : IFC 7 % | Le décret existe (NATLEX : protection des travailleurs des entreprises de travail temporaire). Son contenu et son article 10 n'ont pas été lus. Il vise l'ancien Code ; le maintien sous le Code 2026 est à confirmer (art. 459-461) | Taux 7 % conservé comme **valeur du classeur** (précarité CDD) et marqué ✖ pour l'intérim jusqu'à lecture du décret |
| 9 | Plan SYSCOHADA (661, 422, 431, 447, 664, 521) cité sans lien au SI | Le module Finance du SI SOMA tient déjà le plan SYSCOHADA et la génération d'écritures | Les modules déclarent des **rubriques**, la table de correspondance comptable reste dans Finance |
| 10 | Multi-tenant Redis présenté comme prérequis | Le projet est **monosociété** aujourd'hui (décision enregistrée) et tourne sur Docker local puis Supabase | Cache en mémoire du processus + table de manifestes compilés ; Redis seulement si le multi-société arrive |
| 11 | Évaluation de formules par « interpréteur AST maison » | Risque de réinventer un langage | Retenir un langage d'expression existant, borné et déterministe (voir §6.2) |

Points du document de départ **conservés** : noyau générique sans `if secteur == …`, manifeste déclaratif, quatre piliers (champs, planning, entrées de paie, ajusteurs), injection dynamique de plugins plutôt que compilation statique, audit continu, étanchéité Core/extension.

---

## 2. Architecture cible

### 2.1 Principe

Le **cœur** (Core RH + moteur de paie légal) ne connaît aucun secteur. Un **module vertical** est un paquet déclaratif (manifeste JSON + jeux de tests + documentation) qui s'accroche au cœur par des points d'extension. Un client active un module à la demande ; le cœur le charge sans redéploiement.

```
┌───────────────────────────── CŒUR SOMA-RH (immuable) ─────────────────────────────┐
│ Dossier salarié/contrat · Calendrier · Temps & pointage · Moteur de paie légal      │
│ (IR, TRIMF, CFCE, IPRES, CSS, IPM, BRS) · Clôture · Passation comptable · RBAC/audit│
└───────────────┬──────────────────────────────────────────────────────────────────┘
                │ points d'extension (hooks) + registre de rubriques
 ┌──────────────┼───────────────┬───────────────┬────────────────┬─────────────────┐
 ▼              ▼               ▼               ▼                ▼                 ▼
Sécurité/    HORECA        Transport      Nettoyage/BTP/    Services : intérim,  Enseignement
gardiennage                 & chauffeurs   industrie         libérales, SAV       privé
```

Le cœur déjà construit (lots 0 à 4 de la feuille de route) fournit : règles versionnées (`payroll_settings`, `overtime_rates`, `notice_scales`, `garnishment_scale`), registre légal (`legal_sources` avec statut), table `compliance_findings`, harnais `verify-payroll`. Les modules **s'appuient sur ces tables** au lieu d'en créer de parallèles.

### 2.2 Points d'extension

| Hook | Rôle | Déjà couvert par le cœur ? |
|---|---|---|
| `CustomFieldInjector` | Champs sectoriels sur Salarié et Contrat, validés à l'exécution | Non : à créer (JSONB + schéma de validation) |
| `ShiftPreCalculationHook` | Convertit présence en heures de travail effectif, détecte HS, nuit, dimanche, férié | Partiel (lot 5 : postes et rotations) |
| `SectorialPayrollRegistry` | Déclare rubriques sectorielles avec drapeaux fiscal et social | Partiel (rubriques existantes) |
| `PayrollAdjuster` | Ajouts au brut, retenues spécifiques, dans l'ordre d'un graphe de dépendances | Non |
| `ClientBillingHook` | Facturation au taux horaire, coefficient intérim, TVA | Non (module Finance du SI) |
| `ModuleLifecycleListener` | Activation/désactivation, compilation et mise en cache du manifeste | Non |

### 2.3 Données

- **Champs personnalisés** : colonne `extra jsonb` sur `employee` et `contract`, avec schéma JSON par module ; pas d'`ALTER TABLE` par client. Les 2 ou 3 champs interrogés souvent (par exemple numéro de carte professionnelle) obtiennent un index d'expression.
- **Règles et barèmes datés** : chaque ligne porte `valid_from` / `valid_to` (temps métier) et l'horodatage système de saisie. Les contraintes d'exclusion `gist` interdisent deux versions qui se chevauchent. Le recalcul rétroactif d'un bulletin utilise la règle valable à la date de l'événement.
- **Manifestes** : table `module_manifest(module_id, version, status, hash, compiled jsonb, activated_at)`. Un manifeste est signé (hash) à l'activation ; le bulletin garde l'identifiant et la version du module appliqué.
- **Audit** : journal en ajout seul, chaque ligne chaînée par hash à la précédente (modèle décrit dans le carnet pour les données RH sensibles).

### 2.4 Arithmétique

Montants en `numeric` côté base et en décimal exact côté code, jamais en flottant. Le FCFA n'a pas de sous-unité : l'arrondi (au franc, par ligne ou sur le total) est un **paramètre unique du cœur** — le classeur ne l'arrondit pas, décision D10 conservée.

---

## 3. Socle réglementaire sénégalais utilisé par les modules

| Paramètre | Valeur retenue | Source | Statut |
|---|---|---|---|
| Durée légale | 40 h par semaine | Code du travail 2026 (loi 2026-18, JO du 17/09/2026), art. 241 | ✔ |
| Heures supplémentaires | Heures au-delà de la durée légale **ou de la durée considérée comme équivalente** : majoration de salaire | Code du travail 2026, art. 244 | ✔ règle · ✖ taux (décret 70-184 non lu) |
| Taux HS appliqués aujourd'hui | 115 % / 140 % / 160 % / 200 % | Classeur de référence (analyse Excel) | ✔ (classeur) · ✖ (texte) |
| Travail de nuit | 22 h à 5 h ; modalités par arrêté | Code du travail 2026, art. 245 | ✔ · arrêté ✖ |
| Repos hebdomadaire | 24 h consécutives, en principe le dimanche ; dérogations par décret | Code du travail 2026, art. 246 | ✔ |
| Congés payés | 2 jours ouvrables par mois de service | Code du travail 2026, art. 249 | ✔ |
| Équivalences horaires par branche | Seuils sénégalais **non lus** (56/72 h = texte nigérien) | Décret 70-183 (JO 4091, 1970) à lire | ✖ |
| Prestations de service spécialisées (sécurité, nettoyage, maintenance) | Autorisées si le prestataire reste l'employeur et apporte un savoir-faire propre ; attestation de régularité sociale **avant la conclusion puis tous les 6 mois** ; marchandage interdit | Code du travail 2026, art. 291 | ✔ |
| Travail temporaire | Agrément de l'entreprise (art. 292) ; missions précises (remplacement, accroissement temporaire, tâches ponctuelles, travaux urgents) ; interdit pour un emploi durable ; sinon travailleur **réputé en CDI** chez l'utilisateur ; autres règles par décret | Code du travail 2026, art. 292-294 | ✔ |
| IFC / précarité intérim | 7 % des salaires bruts de la mission | Décret 2009-1412 (existence confirmée) ; taux = classeur (CDD) et étude précédente | ✖ |
| Déplacement | Indemnité en multiples du salaire horaire de base selon repas et nuitée ; mission ≤ 6 mois | CCNI, art. 61 (copie de 1982 lue) ; la CCNI récente est dans le projet | ✔ (à rapprocher de la CCNI récente) |
| IPRES régime général | 5,6 % salarié / 8,4 % employeur, plafond **432 000 F/mois** | Classeur de référence ; 4 sources secondaires concordantes (LinkedIn IPRES juin 2022, Mercans, MaCalculatrice, CLEISS pour la CSS) | ◐ — arrêtés de fixation non fournis (CSS 2026, art. 74) |
| IPRES complémentaire cadres | 2,4 % / 3,6 %, tranche jusqu'à **1 296 000 F/mois** | Idem | ◐ |
| CSS prestations familiales | 7 % employeur, plafond **63 000 F/mois** | CLEISS 2026, OCDE, classeur | ◐ |
| CSS accidents du travail | 1 %, 3 % ou 5 % selon le risque, employeur seul ; plafond 63 000 F (CLEISS, OCDE) | Classeur : 5 % | ◐ — une source dit « sans plafond » : à trancher |
| Répartition employeur/salarié | Part du salarié ≤ la moitié ; fixée par arrêté | CSS 2026 (loi 16/2026), art. 73 | ✔ règle · taux ✖ |
| CFCE | 3 % du brut, employeur, sans plafond | Classeur ; MaCalculatrice, Mercans | ◐ — une loi de 1982 donne 5 % pour les travailleurs étrangers : à contrôler au CGI 2025 |
| IR salaires | Abattement 30 % plafonné à 900 000 F/an ; barème 0 % jusqu'à 630 000, puis 20 / 30 / 35 / 37 / 40 % | Classeur ; sources secondaires | ◐ — certaines sources donnent un taux supérieur de 43 % : à vérifier au CGI 2025 (art. 173) |
| TRIMF | Barème forfaitaire de 900 à 36 000 F/an | Classeur | ◐ |
| BRS prestataires | 5 % du montant HT si la prestation est ≥ 25 000 F ; régime des art. 200 et suivants du CGI ; autres taux pour certaines professions depuis la LF 2025 (10 % pour des professions médicales non salariées) | Cabinet Deloitte (LF 2025) pour le taux et les articles ; seuil : source secondaire | ◐ |
| TVA | 18 % (taux normal) sur le montant total HT facturé | Sources secondaires | ◐ |
| Conservation des bulletins | 5 ans minimum | Carnet (Mali, Sénégal) | ◐ |
| Taux et plafonds sociaux 2026 | Registre légal RL-001 à 009 « à confirmer » | Arrêtés CSS non fournis | ✖ |

**Règle de produit** : seuls les paramètres ✔ ou ◐ sont pré-remplis, avec le statut affiché dans l'écran de conformité. Les paramètres ✖ restent vides ; la paie d'un salarié concerné émet une alerte « paramètre manquant » dans `compliance_findings` au lieu d'inventer une valeur.

---

## 4. Modules verticaux : contenu métier

Chaque module ne déclare **que** ce que le cœur ne sait pas faire : champs, plannings, rubriques, ajusteurs, contrôles. Les taux légaux restent dans le cœur.

### 4.1 Sécurité privée et gardiennage — `soma-mod-securite-gardiennage-sn`

- Champs : numéro de carte professionnelle (si exigé par la réglementation du secteur : à confirmer), autorisation de port d'arme, logé sur site (oui/non).
- Planning : vacations 12 h et 24 h ; repos après vacation ; seuil d'équivalence **par catégorie de poste**, saisi par le client ou chargé depuis le décret sénégalais une fois lu.
- Temps : présence → travail effectif par la politique d'équivalence ; au-delà du seuil, heures supplémentaires (art. 244).
- Rubriques : prime de risque, prime de nuit, prime d'entretien de tenue (exonérée ou non selon le texte applicable : drapeau saisi), panier de nuit selon la convention du client.
- Contrôle de conformité propre au secteur : **attestation de régularité sociale** (art. 291) à produire à chaque client avant contrat puis tous les 6 mois ; alerte à J-30.
- Cas à tester : gardien logé (présence continue, repos hebdomadaire), dérangements de nuit (règle d'un autre pays dans le carnet : ne pas reprendre sans texte sénégalais).

### 4.2 Restauration et hôtellerie — `soma-mod-horeca-sn`

- Horaires à coupure : amplitude, pause non payée entre deux services (règle à paramétrer).
- Avantages en nature nourriture et logement : évaluation selon l'arrêté sénégalais visé par le registre (arrêté 012914 déjà cité au ticket C26-32 : à lire), retenue sur net.
- Service et pourboires : traitement fiscal et social et incidence sur l'allocation de congés, à confirmer par texte.
- Seuils d'équivalence HORECA : ✖ (voir §1, ligne 1).

### 4.3 Transport et chauffeurs — `soma-mod-transport-sn`

- Temps : conduite effective, attente, chargement, disponibilité, avec qualification de chaque nature de temps.
- Rémunération au trajet ou au kilomètre : rubrique à quantité × tarif.
- Indemnités d'éloignement, de découché et de repas : multiples du taux horaire catégoriel (CCNI art. 61 et conventions de branche) ; la part au-delà du plafond de non-imposition est réintégrée à l'assiette (règle à confirmer au CGI).
- Primes sans accident et de conduite : rubriques fiscales et cotisables par défaut.

### 4.4 Nettoyage, voirie, BTP, industrie — `soma-mod-nettoyage-btp-sn`

- Horaires décalés, dimanche et fériés réguliers, postes continus.
- Primes de salissure, d'outillage, de hauteur, de risque : drapeaux `is_taxable` et `is_cotisable` saisis par rubrique.
- Lien avec le module HSQE déjà au SI : habilitations et dotations EPI conditionnent l'affectation (lot 4-5 de la feuille de route).
- Art. 291 applicable aussi au nettoyage : mêmes alertes d'attestation de régularité sociale que le gardiennage.

### 4.5 Services : intérim, professions libérales, SAV — `soma-mod-services-interim-sn`

Reprend le PDF « Archive complète de conception » en le corrigeant (manifeste en §5 et fichier JSON joint).

| Cas | Temps | Facturation client | Fiscal et social |
|---|---|---|---|
| Intérim (ETT) | Activité réelle, HS | `((salaire de base + charges patronales) × K) + IFC`, puis TVA 18 % sur le total HT | Égalité de rémunération avec l'utilisateur ; IFC (7 % ✖) ; **agrément** de l'ETT (art. 292) ; motif de mission contrôlé (art. 293) |
| Professions libérales (cabinets) | Heures facturables et non imputables | Taux horaire par grade + débours réels | Salariés : IR/cotisations ; prestataires externes : BRS au cœur |
| SAV, interventions | Trajet (travail effectif ou non : à qualifier) et temps sur site | Taux site + taux trajet + forfait km | Per diem selon CCNI art. 61 ; justificatif géolocalisé facultatif mais recommandé |
| Enseignement privé | Vacations CM / TD / TP, surveillance, copies | Tarif horaire par type ou forfait | Salarié sous subordination : cotisations ; vacataire indépendant : BRS (au cœur) |

Garde-fous propres à l'intérim, tirés du Code 2026 : (1) refuser une mission dont le motif n'est pas dans la liste de l'art. 293 ; (2) alerter quand une mission, enchaînée ou renouvelée, finit par couvrir un emploi durable de l'utilisateur (risque de requalification en CDI) ; (3) conserver l'attestation d'agrément ; (4) responsabilité solidaire en cas de collusion (art. 294) : journaliser les missions.

---

## 5. Manifeste v2

Fichiers joints (à placer dans `docs/modules/manifests/`) :

- `soma-mod-securite-gardiennage-sn.manifest.json`
- `soma-mod-services-interim-sn.manifest.json`

Structure commune :

| Bloc | Contenu |
|---|---|
| `module_id`, `version`, `status` (`draft`, `active`, `retired`), `jurisdiction` | Identité ; `status` interdit l'activation d'un brouillon en production |
| `custom_fields[]` | `field_key`, `target_entity`, `data_type`, `required`, `required_if`, `validation`, `default_value` |
| `parameters{}` | Chaque paramètre : `value`, `unit`, `source`, `legal_status` (`verified`, `secondary`, `to_provide`), `valid_from` |
| `planning_rules` | Fenêtres horaires, équivalence par catégorie, repos, durée maximale de vacation |
| `payroll_inputs[]` | Code, libellé, type, unité, `is_taxable`, `is_cotisable` (booléens **saisis par le client si le texte n'est pas lu**) |
| `calculation_rules[]` | `rule_id`, `trigger_event`, `depends_on[]` (ordre de calcul), `formula`, `effective_from`, `legal_status` |
| `compliance_checks[]` | Contrôles émis vers `compliance_findings` (attestation expirée, mission hors motif, paramètre manquant) |
| `tests[]` | Cas dorés : entrées, résultat attendu, source du cas |

Un manifeste dont un paramètre bloquant est `to_provide` ne peut pas passer en `active` pour un client sans que celui-ci **saisisse la valeur** ; la saisie est tracée.

---

## 6. Moteur de règles

### 6.1 Ordre de calcul

Graphe orienté acyclique : chaque règle déclare ce dont elle dépend ; le moteur trie, détecte les cycles à l'activation et calcule dans l'ordre. Ce modèle est celui décrit dans le carnet pour SOMA-RH (graphe de règles déclaratives : ajusteurs, retenues, primes) et correspond à la logique des constantes et rubriques de Sage.

Ordre standard : capture des temps → conversion équivalence/nuit/dimanche/férié → heures supplémentaires → rubriques de primes → brut → assiettes (IPRES, CSS, IR) → cotisations et impôts → retenues volontaires et plafond des deux tiers (CPC art. 381) → net → écritures.

### 6.2 Évaluation des formules

Recommandation (connaissance générale, **non recherchée dans cette session**, à valider en spike) : utiliser un langage d'expression existant, non Turing-complet et sans accès système — par exemple CEL (Common Expression Language) ou JSONLogic — plutôt qu'écrire un interpréteur. Exigences : fonctions autorisées en liste blanche (`max`, `min`, `round_fcfa`, `bareme(table, valeur)`), variables de paie déclarées, durée et mémoire bornées, résultat déterministe, arithmétique décimale. Un jeu de tests doit prouver qu'aucune formule ne peut lire un fichier, le réseau ou une autre société.

### 6.3 Cache

Compilation du manifeste à l'activation, stockage dans `module_manifest.compiled`, cache dans le processus. Mesurer d'abord : une paie de moins de 200 bulletins n'impose pas Redis.

---

## 7. Parcours temps → paie → comptabilité

Repris des pratiques décrites dans le carnet (Sage Paie et RH, formations et spécifications SIRH) et adaptés :

1. **Capture** : pointeuse, application mobile, feuille de temps ; la géolocalisation est une option de preuve.
2. **Transformation** : politiques horaires du module (équivalence, nuit, dimanche, férié).
3. **Éléments variables** : import ou saisie des primes, indemnités, acomptes déjà versés ; validation par workflow.
4. **Calcul et brouillard** : bulletins en brouillon, **journal de contrôle** avant clôture (équilibre débit/crédit, rubriques non imputées).
5. **Clôture** : verrouillage des bulletins, cumuls et compteurs de congés incrémentés. Seul l'administrateur valide et clôture ; le rôle `rh` peut calculer (décision du 30/10/2026).
6. **Passation comptable** : pièce d'OD de paie générée vers le module Finance (classe 6 et tiers classe 4).

Modèles de profils de paie : un **bulletin modèle par module et par catégorie** (par exemple « Gardien », « Chauffeur », « Intérimaire »), associé en masse aux fiches, comme dans Sage.

---

## 8. Gouvernance de la conformité

- **Registre légal** : chaque règle de module pointe vers `legal_sources` (texte, article, date d'entrée en vigueur, statut). Passage à « conforme » seulement avec le texte officiel et une revue juridique.
- **Cas dorés par module** : bulletins attendus signés par un comptable ; exécutés par `verify-payroll` avant toute publication d'une version de manifeste.
- **Versionnage** : un manifeste modifié crée une nouvelle version ; l'ancienne reste utilisable pour recalculer le passé.
- **Alerte de veille** : tout changement de loi de finances, d'arrêté CSS ou de décret ouvre une tâche de revue des paramètres touchés.
- **Séparation des tâches** : celui qui prépare une paie n'est pas celui qui l'approuve pour les montants sensibles (principe issu du carnet, à rapprocher des rôles existants).

---

## 9. Plan de livraison

| Lot | Contenu | Prérequis |
|---|---|---|
| M0 | Tables `module_manifest`, `extra jsonb`, validateur de schéma, écran d'activation, journal d'audit chaîné | Cœur actuel |
| M1 | Moteur de règles à graphe + langage d'expression (spike de sécurité d'abord) | M0 |
| M2 | Module Services/Intérim (le plus riche en garde-fous légaux : art. 291-294) | M1, lecture du décret 2009-1412 |
| M3 | Module Gardiennage (équivalences, nuit, attestation de régularité sociale) | Lecture du décret 70-183 et 70-184 |
| M4 | Modules Transport, HORECA, Nettoyage/BTP | Textes de branche, CCNI récente |
| M5 | Facturation client (taux horaire, coefficient K, TVA) via Finance | M2, module Finance |
| M6 | Multi-société et Redis, seulement si le besoin apparaît | Décision de la direction |

Chaque lot : une migration, un retour arrière, `verify-payroll` avant et après.

---

## 10. Points à trancher (décisions de Moussa)

1. **Équivalences** : fournir le décret sénégalais de dérogations (70-183) ou accepter de livrer les modules avec seuils saisis par le client.
2. **Plafond AT de la CSS** : 63 000 F (CLEISS, OCDE) ou sans plafond (une source secondaire) ? Le classeur applique 63 000 F.
3. **Barème IR** : maximum à 40 % (classeur) ou 43 % (autres sources) ? À lire au CGI 2025.
4. **CFCE** : 3 % pour tous ou 5 % pour les travailleurs étrangers ?
5. **IFC intérim** : 7 % maintenu à titre provisoire ?
6. **GPS** : option de preuve ou condition de saisie de certains per diem ?
7. **Redis / multi-société** : reporter à M6 (recommandé).
8. **Interprète des formules** : valider un langage existant par un spike avant de coder.

---

## Annexe A — Ce que dit le carnet NotebookLM « logiciel HR » (86 sources)

Questions posées le 6 novembre 2026 ; réponses du carnet résumées, avec les sources qu'il cite. À lire avec prudence : il cite des textes d'autres pays (Niger, Mali, Côte d'Ivoire, Burkina) que le Sénégal ne partage pas.

- **Fonctions sectorielles** : équivalences, vacations, coupures, paniers, déplacements, avantages en nature, nuit, intérim (égalité de traitement, IFC, coefficient K, TVA), enseignement (vacations, 1 h de surveillance = 1 h de cours, copies), santé. Sources citées : décret nigérien 2017-682, Code du travail malien, CCNI du Sénégal 2012-2024 (tome 3), convention ivoirienne de 1977, « Architecture Modulaire SaaS RH », « Étude d'Architecture Logicielle ».
- **Paramétrage sans code** : Sage Paie (codes mnémoniques, constantes de types calcul/tranche/valeur/cumul/test, bulletins modèles par catégorie, grilles conventionnelles) ; Workday, SAP SuccessFactors, Oracle HCM (métadonnées, champs flexibles, groupes de données législatives) ; Frappe HR (DocTypes JSON, formules).
- **Flux temps → paie** : capture, transformation, éléments variables, calcul, journal de contrôle, clôture, passation comptable (OD de paie au format SYSCOHADA).
- **Audit et conformité** : temporalité bi-axiale (`valid_from/to`, `system_from/to`) avec contraintes d'exclusion `gist`, journal d'audit chaîné par hash, séparation des tâches, chiffrement des données sensibles, conservation des bulletins 5 ans (Mali, Sénégal).

## Annexe B — Sources externes consultées (6 novembre 2026)

- CLEISS, « Les cotisations au Sénégal », 2026 : https://www.cleiss.fr/docs/cotisations/senegal.html
- OCDE, financement de la protection sociale au Sénégal : https://www.oecd.org/fr/publications/financement-de-la-protection-sociale-au-senegal_00d67508-fr/full-report/developper-les-regimes-contributifs_bc4ce1d3.html
- Vie-publique.sn, Code de la Sécurité sociale 2026 (loi 16/2026) : https://www.vie-publique.sn/dossiers/code-securite-sociale-2026-loi-16-2026-senegal
- NATLEX (OIT), décret 2009-1412 du 23/12/2009 : https://natlex.ilo.org/dyn/natlex2/r/natlex/fe/details?p3_isn=49603
- Deloitte Avocats, loi de finances 2025 (retenue à la source de 5 %, art. 200 et suivants) : https://blog.avocats.deloitte.fr/senegal-les-principales-mesures-importantes-de-la-loi-de-finances-pour-2025/
- MaCalculatrice, simulateurs fiscaux et sociaux Sénégal 2026 (secondaire) : https://macalculatriceenligne.com/afrique/calcul-css-senegal/
- Mercans, dossier paie Sénégal (secondaire) : https://dsr.mercans.com/payroll-dossiers/senegal/

Documents du projet utilisés : Code du travail 2026 (texte intégral), Code de la Sécurité sociale 2026 (texte intégral), CCNI (texte OCR), `soma-rh-analyse-paie-excel`, `soma-rh-arbitrages-paie`, `soma-rh-sources-legales-verification`, `soma-rh-code-travail-2026-specification`, `soma-rh-feuille-de-route`, `architecture-si-soma`.
