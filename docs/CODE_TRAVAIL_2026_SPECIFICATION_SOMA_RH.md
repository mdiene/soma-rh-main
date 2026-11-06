# SOMA-RH — Spécification de conformité au Code du Travail (loi n° 2026-18 du 3 septembre 2026)

> **Version 1.0 — 5 novembre 2026 — à valider par le juriste et le comptable avant tout passage au statut « conforme »**
> Source analysée : *Journal officiel n° 7931 du 17 septembre 2026* (numéro spécial, pp. 1603-1673), loi n° 2026-18 du 03 septembre 2026 portant Code du Travail (462 articles, 15 titres).
> Cible : traduire le texte en règles de gestion, paramètres, champs de données et garde-fous pour SOMA-RH (base PostgreSQL locale, moteur `compute_salary_slip`, registre `docs/regles-de-paie/registre-legal.mdx`).
> Ce document n'est pas un avis juridique ; il met en forme le texte et signale ce qu'il ne contient pas.

---

## 0. Synthèse en deux minutes

### 0.1 Ce que le Code règle, et ce qu'il renvoie ailleurs

Le Code de 2026 fixe les **principes, les procédures et quelques chiffres durs**. Il renvoie la plupart des **barèmes** à des décrets, arrêtés ou conventions collectives (art. 78, 144, 151, 195, 244, 135, 216, 258, 303). Conséquence pratique : **le texte seul ne permet pas d'atteindre « 100 % de conformité »** ; il faut lui adjoindre les textes d'application qui restent en vigueur (art. 460-461) et la convention collective de SOMA.

| Ce que le Code fixe (chiffres durs, paramétrables par défaut) | Ce qu'il renvoie à un autre texte (paramètre « à fournir ») |
|---|---|
| Durée légale 40 h/sem. (art. 241) ; travail de nuit 22 h-5 h (art. 245) ; repos 24 h (art. 246) | Taux des heures supplémentaires et contingent annuel (art. 244 : décret ou convention) |
| Congé : 2 jours ouvrables par mois de service effectif ; 6 jours obligatoires par an ; 1/12 des sommes perçues (art. 248-254) | Majoration du congé pour ancienneté (art. 249 : règlements ou convention) |
| Maternité : **18 semaines**, dont 12 après l'accouchement, +3 semaines possibles (art. 277) ; allaitement 1 h/jour pendant 20 mois (art. 280) | Barème et durée du préavis (art. 144 : décret ou convention) |
| Indemnité de fin de CDD : **7 %** de la rémunération brute totale (art. 167) | Barème de l'indemnité de licenciement et de retraite (art. 135, 151 : convention et règlements) |
| Essai : 6 mois maximum, renouvellement compris (art. 94) ; CDD : 2 ans, un seul renouvellement, 4 ans cumulés (art. 100) | SMIG/SMAG, catégories et minima (art. 195 : décrets et arrêtés) |
| Indemnité spéciale : **1 mois de salaire brut** (licenciement économique, cessation d'activité, plan social : art. 132, 156, 162) | Quotité cessible / retenues progressives (art. 216 : art. 381 du Code de procédure civile) |
| Chômage technique : allocation ≥ **50 %** de la moyenne brute des 2 derniers mois travaillés, durée ≤ 1 an (art. 123, 125) | Âge de retraite, pénibilité (art. 134 : décret) ; seuils des délégués du personnel, du comité et du service de santé (art. 60, 340-341 : décret) |
| Paiement du salaire mensuel au plus tard **8 jours** après la fin du mois (art. 199) ; prescription **5 ans** (art. 212) | Mentions du bulletin et du registre du personnel (art. 202-203, 365 : arrêtés) |

### 0.2 Les dix points qui demandent une action dans SOMA-RH

Classés par risque. Le détail, les références et les corrections proposées sont en §2 à §6 ; les tâches sont au §7.

| # | Constat (état vérifié dans le dépôt local le 5/11/2026) | Art. | Priorité |
|---|---|---|---|
| 1 | **Congé de maternité à 98 jours** (`leave_types.MATERNITE`, 14 semaines). Le Code donne **18 semaines = 126 jours**, extensible de 3 semaines (147 jours). | 277 | P0 |
| 2 | **Assiette des indemnités incomplète.** `severance_basis = average12` ne retient que base + sursalaire + prime d'ancienneté. L'art. 197 impose la moyenne sur 12 mois de **tous** les éléments variables (commissions, primes, avantages), hors remboursements de frais, pour le congé, le préavis, le licenciement et les dommages-intérêts. | 197 | P0 |
| 3 | **Indemnité de licenciement : coefficients en dur** (25/30/40 % ; retraite 25/30/45/50 %) dans `severance_coefficient`, sans lien avec la convention. Le Code renvoie au barème conventionnel. À rendre paramétrable par convention et à confirmer. | 135, 151 | P1 |
| 4 | **Indemnité spéciale de 1 mois** (licenciement économique, cessation d'activité, plan social) **absente** : les motifs de sortie du module Dev06 se limitent à 5 valeurs. | 132, 156, 162 | P0 |
| 5 | **Motifs de sortie trop pauvres** (`DEMISSION`, `LICENCIEMENT`, `RETRAITE`, `DECES`, `FIN DE CONTRAT`) : le droit distingue faute lourde, motif personnel, motif économique, rupture amiable, plan social, inaptitude, démission sans préavis, essai, force majeure. Chaque motif change les indemnités dues. | 126-166 | P0 |
| 6 | **Certificat de travail** : la fonction cite « art. L.55 » (ancien code, abrogé par l'art. 462). Contenu à limiter à ce que permet l'art. 140 ; ajout de la catégorie de la convention collective. | 140 | P1 |
| 7 | **Preuve du paiement** : la présomption de non-paiement est irréfragable sans pièce probante. Le suivi des paiements doit exiger la pièce selon le mode (émargement, reçu, chèque encaissé + avis de débit, attestation bancaire ou de monnaie électronique). | 205 | P0 |
| 8 | **Retenues sur net** (coopérative, caisse commune, frais médicaux, avances) : toute retenue hors liste légale est **nulle** et remboursable avec intérêts ; l'employeur qui détourne un prélèvement encourt 500 000 à 5 000 000 F et 3 mois à 1 an. Exiger une autorisation écrite et plafonner les avances. | 214-217, 452 | P0 |
| 9 | **Enfants à charge sans date de naissance** : le congé supplémentaire des mères (enfant < 14 ans) et le rang de licenciement économique (+1 an par enfant à charge, +1 an si marié) exigent des données individuelles. | 154, 249 | P1 |
| 10 | **CDD sans contrôle de durée ni de motif** : plafonds, renouvellement unique, motif objectif de prolongation, dépôt à l'inspection avant exécution, risque de requalification en CDI. | 97-103 | P0 |

### 0.3 Ce qui est déjà conforme

- **7 % de précarité** : `precarity_rate = 0.07` = art. 167 (taux). L'assiette et les exclusions sont à revoir (§2, règle C-CDD-4).
- **Durée légale 40 h/sem.** : `hourly_rate_divisor = 40 × 52 / 12` = art. 241.
- **Congé 2 jours ouvrables par mois** : `leave_types.CONGE_ANNUEL.days_per_month = 2` = art. 249 (plafond annuel `24` à lever, voir §4.3).
- **Provision de congé = brut ÷ 12** : cohérent avec l'art. 254 (1/12 des sommes perçues), sous réserve de l'assiette.
- **Modes de paiement** : `payment_mode` (`espèces`, `virement`, `chèque`, `mobile money`) = art. 198.
- **Interdiction de payer en alcool ou en nature** : aucune rubrique correspondante ; garde-fou à documenter.

### 0.4 Limites et précautions de lecture

1. **Extraction du texte.** Le PDF est un scan à deux colonnes. Le texte est exploitable mais l'ordre de lecture est parfois mêlé (par exemple arts. 97-105 et 119-121). Les règles ci-dessous ont été relues en recoupant les articles ; **à confronter au Journal officiel papier pour tout montant ou délai avant mise en production**.
2. **Textes d'application.** Les décrets, arrêtés et la convention collective en vigueur ne sont pas dans le fichier. Les valeurs concernées sont marquées **« héritée »** (valeur actuelle de SOMA-RH, non confirmée par le nouveau Code) ou **« à fournir »** (aucune valeur par défaut raisonnable).
3. **Cotisations et impôts hors Code du travail.** IPRES, CSS, IR, TRIMF, CFCE relèvent du Code de la sécurité sociale et du CGI ; ils restent à l'état « à confirmer » du registre (RL-001 à RL-009, RL-015, RL-016).
4. **Transition.** Le Code s'applique de plein droit aux contrats en cours et ne peut justifier une rupture (art. 459). Les avantages contractuels supérieurs sont maintenus (art. 459 al. 3). Les conventions collectives et règlements d'application antérieurs restent applicables s'ils ne sont pas contraires au nouveau Code (art. 460-461). **La loi n° 97-17 du 1er décembre 1997 est abrogée** (art. 462). Le texte ne contient pas de date d'entrée en vigueur autre que la promulgation du 3 septembre 2026 ; à confirmer avec le juriste.

---

## 1. Grille de lecture

Chaque règle suit la grille demandée : **(1)** cadrage juridique, **(2)** règle de gestion, **(3)** composante SaaS (paramètres, champs, valeurs par défaut, garde-fous).

| Marque | Signification |
|---|---|
| **[B]** | Garde-fou **bloquant** : l'enregistrement, la validation de paie ou la clôture est refusé tant que la condition n'est pas levée (avec motif écrit pour les rôles habilités). |
| **[A]** | Garde-fou **alerte** : visible dans la checklist de la période et le tableau de bord, n'empêche pas la validation. |
| **Défaut : Code** | Valeur écrite dans le Code de 2026 (article cité). |
| **Défaut : héritée** | Valeur actuelle de SOMA-RH conservée, non fixée par le Code (à confirmer par décret ou convention). |
| **À fournir** | Valeur absente du Code, aucune valeur par défaut raisonnable : le paramètre est créé vide et la fonctionnalité associée reste en alerte, pas en blocage. |
| **État** | ✔ conforme · ✘ écart constaté dans le dépôt · ? non vérifié dans le code · ➕ à créer |

Variables : `H` = 173,33 h (durée mensuelle de référence) ; `M12` = moyenne mensuelle sur les 12 derniers mois d'activité (art. 197) ; `TH` = taux horaire (base + sursalaire + honoraires + autre fixe) ÷ H.

---

## 2. Règles par thème

### 2.A Formation, nature et formalités des contrats (arts. 90-113, 176-183)

| ID | Art. | Règle de droit | Règle de gestion et paramètres | Garde-fous · État |
|---|---|---|---|---|
| CTR-01 | 90, 91, 104 | Pas d'engagement à vie ; le contrat d'équipe est interdit ; tout contrat qui n'est ni CDD, ni temporaire, ni apprentissage, ni stage, ni essai est **réputé CDI**. | Liste fermée des types de contrat (§4.1). Un contrat sans motif ou sans écrit exigé bascule en CDI. | **[B]** type de contrat hors liste. État : ✔ (liste actuelle `CDI, CDD, COD, STAGE, APPRENTISSAGE, PRESTATION`) ; ➕ `ESSAI`, `ALTERNANCE`. |
| CTR-02 | 93-96 | **Contrat d'engagement à l'essai** : écrit (à défaut = CDI), déposé à l'inspection avant exécution, **6 mois maximum renouvellement et prolongation compris**, peut cesser à tout moment sans préavis sauf clause contraire ; la poursuite sans nouveau contrat = CDI. | `probation_max_months = 6` (**Code**). Durée propre à la catégorie : `probation_months_by_category` (**à fournir**, art. 78 la renvoie à la convention). `probation_end = contract_start + durée`. | **[B]** durée cumulée > 6 mois. **[B]** essai sans référence de dépôt à l'inspection avant `contract_start`. **[A]** J-15 avant la fin. **[A]** salarié encore actif au lendemain de `probation_end` sans nouveau contrat (devient CDI : art. 95). État : ➕. |
| CTR-03 | 97, 98 | Un CDD ne peut pourvoir durablement un emploi **lié à l'activité normale et permanente** (sinon CDI). Interdit pour remplacer un poste supprimé par licenciement économique dans les **6 mois** (dérogation : 3 mois maximum, non renouvelable). | `cdd_motif` obligatoire (§4.1). `eco_layoff_cdd_ban_months = 6` (**Code**). | **[B]** CDD sans motif. **[B]** CDD sur un poste dont un titulaire est sorti pour `LICENCIEMENT_ECONOMIQUE` depuis moins de 6 mois, sauf durée ≤ 3 mois non renouvelable. **[A]** motif « activité permanente » déclaré. État : ➕. |
| CTR-04 | 99-103 | **CDD** écrit (à défaut = CDI) et déposé à l'inspection avant exécution ; **2 ans maximum** ; **un seul renouvellement ou une seule prolongation** ; durée cumulée avec le même employeur **≤ 4 ans** ; exception : ouvrage déterminé (peut dépasser, ni renouvellement ni prolongation). Prolongation par avenant déposé avant exécution, pour motif objectif (remplacement prolongé, surcroît temporaire, retard imprévu), **≤ durée initiale**. Renouvellement par accord écrit = nouveau CDD déposé. Poursuite après terme (hors art. 101 pts 1-7) = CDI de plein droit. | `cdd_max_months = 24`, `cdd_max_renewals = 1`, `cdd_cumul_max_months = 48` (**Code**). Calcul : `cdd_cumul_months = Σ durées des CDD successifs du même salarié` ; `prolongation ≤ durée initiale`. | **[B]** durée > 24 mois (hors ouvrage/exemption). **[B]** 2e renouvellement ou renouvellement + prolongation. **[B]** cumul > 48 mois. **[B]** prolongation sans motif objectif ou > durée initiale. **[B]** CDD/avenant sans dépôt avant `contract_start`. **[A]** J-30 et J-7 avant le terme. **[A]** salarié actif après `contract_end` sans avenant (CDI de plein droit). État : ✘ non contrôlé (colonnes `contract_start/end` seules). |
| CTR-05 | 101 | Exemptions de requalification : (1) occasionnel, (2) saisonnier, (3) docker, (4) complément d'effectif pour surcroît, (5) remplacement d'un travailleur en suspension légale (sauf suspensions 1, 16, 17, 18 de l'art. 114), (6) secteurs d'usage (liste par arrêté), (7) entreprise exonérée en zone économique spéciale ou agréée au Code des investissements : plusieurs CDD pendant **5 ans** à compter de l'agrément. | Table `cdd_motifs` : `code`, `exempt_art101`, `precarity_due`, `max_months_override`. Pour le motif 7 : `investment_agreement_date` et fenêtre de 5 ans. | **[A]** motif 6 sans arrêté de secteur référencé. **[B]** motif 5 sans salarié remplacé renseigné. État : ➕. |
| CTR-06 | 108-110 | Toute modification individuelle est **notifiée par écrit** ; la modification **substantielle** exige l'accord écrit ; accord de principe : effet après un délai égal au **préavis** ; refus du travailleur = licenciement (économique ou personnel) avec procédure ; refus de l'employeur = rupture imputable au travailleur. | Table `contract_amendments` (§4.2). | **[B]** baisse du salaire de base, du sursalaire ou d'une prime fixe sans avenant signé ou sans délai de préavis écoulé. **[A]** modification de catégorie ou de poste sans avenant. État : ➕. |
| CTR-07 | 111 | Changement de situation juridique de l'employeur (cession, fusion, mise en société) : **transfert automatique** des contrats avec reprise de l'ancienneté, de la rémunération, de la classification et des avantages acquis. | `seniority_start_date` distinct de `date_of_joining` ; événement `employer_change` dans l'historique. | **[B]** rupture motivée par le seul changement d'employeur. État : ➕. |
| CTR-08 | 112, 113 | **Détachement** (mise à disposition temporaire dans le groupe) : consentement écrit, réintégration dans un emploi de classification au moins équivalente, ancienneté conservée. **Transfert** : convention tripartite déposée à l'inspection avec la déclaration de l'art. 363. | Table `group_movements` (type `DETACHEMENT` ou `TRANSFERT`, société d'origine, société d'accueil, dates, consentement, convention déposée). Intérêt direct pour le groupe Kapital Mozaïc. | **[B]** détachement sans consentement écrit. **[B]** transfert sans convention déposée. État : ➕ (mono-société, décision D1). |
| CTR-09 | 105 | **Travailleur étranger** : contrat écrit **visé par le Directeur général du Travail et de la Sécurité sociale avant** l'exécution ; silence au-delà de **7 jours francs** = approbation ; refus = nullité et frais de retour à la charge de l'employeur. | Champs `is_foreign_national`, `work_visa_ref`, `work_visa_date`, `work_visa_status`. `visa_silence_days = 7` (**Code**). | **[B]** activation en paie d'un salarié étranger sans visa (ou 7 jours francs non écoulés après dépôt). État : ➕ (`nationality` existe). |
| CTR-10 | 3, 106, 281, 456 | **Jeune travailleur** : 16 ans accomplis, moins de 18 ans. Contrat signé par le **représentant légal** et **visé par l'inspecteur** avant exécution (sinon nul). Aucun enfant de moins de 16 ans, même apprenti ou stagiaire (13-15 ans : travaux légers par arrêté). Repos journalier ≥ **11 h** englobant la nuit ; pas de travail de nuit. | `min_working_age = 16`, `youth_max_age = 18`, `youth_daily_rest_hours = 11` (**Code**). Champs `legal_guardian_name`, `inspection_visa_ref`. | **[B]** embauche avant 16 ans. **[B]** salarié < 18 ans sans représentant légal et visa. **[B]** poste de nuit planifié pour un < 18 ans. **[A]** J-30 avant les 18 ans (fin du congé supplémentaire). État : ➕ (`date_of_birth` existe). |
| CTR-11 | 176, 182, 183 | **Apprentissage** : écrit et déposé (à défaut = CDI), durée limitée à la formation. **Stage** : réservé à un **diplômé n'ayant pas encore exercé** dans sa filière, écrit, déposé (à défaut = CDI), rémunération indiquée. **Alternance** : contrat distinct (décret). | Types `STAGE`, `APPRENTISSAGE`, `ALTERNANCE` ; `training_agreement_ref`, `deposit_ref`, `stage_first_job_confirmed`. Gratification : `stage_min_pay` (**à fournir**, décret). | **[B]** stage/apprentissage sans écrit ou sans dépôt. **[A]** stage renouvelé au-delà de la durée du décret (**à fournir**). État : ✔ types (`STAGE`, `APPRENTISSAGE`) ; ➕ dépôt et alternance. Le moteur n'applique ni IPRES, CSS, CFCE, IR à ces statuts (registre RL-019, D-008) : **la loi ne tranche pas**, voir §6. |

### 2.B Temps de travail (arts. 241-247, 270-273)

| ID | Art. | Règle de droit | Règle de gestion et paramètres | Garde-fous · État |
|---|---|---|---|---|
| TPS-01 | 241 | Durée légale : **40 h par semaine** (hors secteur public). Exploitations agricoles : **2 304 h par an**. Aménagement dans un cycle par arrêté ou accord collectif. | `weekly_legal_hours = 40` ; `H = weekly × 52 / 12 = 173,3333` ; `agri_annual_hours = 2304` (soit 192 h/mois, établissement agricole uniquement). Heures contractuelles par salarié : `weekly_hours` (défaut = 40). | **[A]** planning > durée légale sans HS saisies. État : ✔ (`hourly_rate_divisor` = 40×52/12). |
| TPS-02 | 242 | Horaires individualisés autorisés sur information préalable de l'inspecteur et des délégués ; reports d'heures d'une semaine à l'autre **sans HS** dans la limite d'un plafond fixé par arrêté. | `individual_schedule_carry_cap_hours` (**à fournir**). | **[A]** report > plafond ; **[A]** horaire individualisé sans information déposée. État : ➕. |
| TPS-03 | 243 | **Temps partiel** : horaire inférieur **d'au moins 1/5** à la durée légale (soit ≤ 32 h sur 40 h). Écrit ; avis préalable des délégués ; information de l'inspecteur. Rémunération **proportionnelle**, ancienneté comprise. | `part_time = (weekly_hours ≤ 0,8 × weekly_legal_hours)` ; `salaire_temps_partiel = salaire_temps_plein × weekly_hours ÷ weekly_legal_hours`. | **[B]** temps partiel sans contrat écrit référencé. **[A]** `weekly_hours` entre 32 et 40 h (réduction hors régime de temps partiel : à qualifier). État : ➕. |
| TPS-04 | 244, 78 | Heures au-delà de la durée légale = **heures supplémentaires**, avec majoration. **Taux, modalités, plafond et contingent annuel : convention, accord ou décret** (information de l'inspecteur et des délégués). | Table `overtime_rates(agreement_code, band, rate)` ; bandes SOMA-RH actuelles : `HS_15`, `HS_40`, `HS_60`, `HS_100` appliquées à **TH × 115 %, 140 %, 160 %, 200 %**. **Défaut : héritée** (non fixée par le Code). `overtime_annual_cap_hours` (**à fournir**). | **[A]** cumul annuel de HS > contingent (si renseigné). **[B]** HS saisies pour un salarié < 18 ans la nuit. **[A]** HS sans approbation préalable du manager. État : ✔ calcul ; ✘ taux non rattachés à la convention ; ✘ pas de contingent. |
| TPS-05 | 245, 274, 275 | **Travail de nuit : 22 h à 5 h.** Repos journalier ≥ 11 h pour femmes enceintes et jeunes, englobant la nuit. Affectation temporaire autorisée pour la salariée enceinte si le travail de nuit l'exige. | `night_start = 22:00`, `night_end = 05:00` (**Code**). Sert à qualifier les HS de nuit et à contrôler le planning des postes (module gardiens). | **[B]** poste de nuit pour un jeune. **[A]** poste de nuit pour une salariée enceinte déclarée. **[A]** repos entre deux postes < 11 h pour ces deux catégories. État : ➕ (planning par poste existant, lot 5). |
| TPS-06 | 246 | **Repos hebdomadaire ≥ 24 h consécutives**, en principe le dimanche ; dérogations (rotation, report) par décret. | `weekly_rest_hours = 24` (**Code**). Le planning par rotation des gardiens doit justifier une dérogation. | **[A]** 7 jours consécutifs sans repos de 24 h. État : ➕. |
| TPS-07 | 270-273 | **Télétravail** : même durée, mêmes droits et rémunération ; accord écrit individuel (avenant) ; imposable par l'employeur en cas de force majeure ou d'épidémie, avec information écrite ; accident sur le lieu de télétravail **présumé accident du travail** ; frais compensés selon décret. | Table `telework_agreements` (type `INDIVIDUEL` ou `EXCEPTIONNEL`, dates, référence écrite). `telework_expense_allowance` (**à fournir**). | **[B]** télétravail habituel sans avenant écrit. État : ➕. |

### 2.C Congés, absences et suspensions (arts. 114-126, 248-257, 274-283)

| ID | Art. | Règle de droit | Règle de gestion et paramètres | Garde-fous · État |
|---|---|---|---|---|
| CNG-01 | 248 | Droit de jouissance après une **période de référence de 12 mois** de service effectif. Report possible d'un commun accord, sans que le service effectif dépasse **2 ans**, **sous réserve d'un congé de 6 jours ouvrables à prendre chaque année**. | `leave_reference_months = 12`, `leave_deferral_max_years = 2`, `leave_mandatory_days = 6` (**Code**). | **[A]** solde > 2 périodes acquises. **[A]** les 6 jours obligatoires de l'année non pris à J-60 de la fin d'année. **[A]** demande de congé avant 12 mois d'ancienneté (hors les 6 jours). État : ➕. |
| CNG-02 | 249 | Acquisition : **2 jours ouvrables par mois** de service effectif ; **+1 jour par mois** pour le jeune travailleur ; **+1 jour par an et par enfant de moins de 14 ans** (mères de famille) ; majoration d'ancienneté selon règlements ou convention. Les suspensions de l'art. 114 comptent, **sauf** points 3 (mandat public), 11 (disponibilité) et 12. | `jours_acquis = 2 × mois_effectifs + 1 × mois_effectifs[jeune] + 1 × nb_enfants_<14ans[mère] + majoration_ancienneté`. Table `leave_policies(agreement_code, monthly_days, youth_bonus_monthly, mother_bonus_per_child, child_age_limit, seniority_bonus_table)`. **Défaut : Code** pour les trois premiers ; `seniority_bonus_table` **à fournir**. | **[A]** `max_days_per_year = 24` bloque les majorations : à supprimer ou calculer. État : ✔ 2 j/mois ; ✘ plafond annuel 24 ; ✘ pas de majoration jeune/mère/ancienneté ; ✘ pas de date de naissance des enfants. |
| CNG-03 | 251 | Non déductibles du congé : permissions pour **événements familiaux du propre foyer** (**10 jours ouvrables/an**) ; absences sans solde pour stage officiel ou congrès syndical (**15 jours ouvrables/an**) ; stages sportifs (**30 jours calendaires/an**, décret). | Types d'absence `PERMISSION` (cap 10), `ABS_STAGE_OU_CONGRES` (cap 15), `ABS_SPORT` (cap 30 j calendaires). | **[B]** dépassement du cap annuel. État : ✔ `PERMISSION` (10) ; ➕ les deux autres. |
| CNG-04 | 252, 256, 264, 266 | Congé librement pris dans le pays de son choix. Pour le **travailleur muté** : durée augmentée des **délais de route** ; les délais de transport ne comptent ni dans la période de référence ni dans le congé ; attente de transport = indemnité égale au salaire. | Champ `travel_days` sur la demande de congé ; type d'absence `ATTENTE_TRANSPORT` payé 100 %. | **[A]** délais de route absents pour un salarié muté (site de Matam). État : ➕. |
| CNG-05 | 253 | Congé obligatoire de 6 jours ouvrables : allocation versée **avant le départ** = salaire habituel sur l'horaire de l'établissement. | `alloc_6j = salaire_journalier_habituel × 6`. `daily_rate_divisor` (**à fournir** ; proposition à confirmer : 26 = 52 × 6 ÷ 12 jours ouvrables moyens). | **[A]** départ en congé sans allocation versée. État : ? |
| CNG-06 | 254, 197, 203 | **Allocation de congé = 1/12 des sommes perçues** pendant la période de référence, hors remboursements de frais et prestations en nature accessoires (**sauf indemnité de logement**). Retenues sur prestations en nature incluses. Elle est **diminuée** de l'allocation des 6 jours obligatoires déjà versée. Suspensions assimilées = rémunérées sur l'horaire de la catégorie. Le **bulletin doit détailler** les éléments du calcul. | `ALLOC_CONGE = (Σ_{12 mois} assiette_congé) ÷ 12 − alloc_6j_versée` ; `assiette_congé` = tous les gains bruts sauf composants marqués `is_expense_reimbursement`. Indicateur d'assiette sur chaque `salary_components`. | **[B]** bulletin de congé sans détail de l'assiette. État : ✔ principe (`leave_provision = brut ÷ 12`) ; ✘ assiette « tous éléments hors frais » non démontrée ; ✘ indicateur `is_expense_reimbursement` absent (liste des frais fixée par arrêté conjoint, art. 197). |
| CNG-07 | 255 | À la **rupture**, indemnité compensatrice (même base) pour congé non acquis ou non pris **sur les 2 dernières années** ; au-delà : dommages-intérêts. **Toute convention remplaçant le congé par une indemnité est nulle**, hors rupture. | `indemnité_congé = jours_non_pris × (allocation_congé ÷ jours_acquis_période)`. | **[B]** allocation de congé versée **sans départ effectif en congé** et hors sortie. **[A]** solde > 2 ans à la sortie (risque de dommages-intérêts). État : ? (`leave_paid_monthly` et `ALLOC_CONGE` saisie libre : usage à vérifier) ; ✔ solde de tout compte inclut les congés non pris (Dev06). |
| CNG-08 | 257 | Fermeture de l'établissement au-delà des congés annuels : indemnité par jour **≥ indemnité journalière de congé payé**. | Table `establishment_closures`. Faible priorité. | **[A]** fermeture > durée du congé légal sans indemnité. État : ➕. |
| CNG-09 | 296 | **Interdit de travailler (rémunéré) pendant le congé payé** : l'employeur qui y contrevient est réputé n'avoir pas accordé le congé. | Contrôle de cohérence présence/congé. | **[B]** présence ou HS saisies sur un jour de congé approuvé. État : ➕. |
| CNG-10 | 277 | **Maternité : 18 semaines consécutives (126 jours)**, dont **12 semaines après** l'accouchement ; **+3 semaines (21 jours)** en cas de maladie liée, complication, grossesse multiple ou santé de l'enfant. Accouchement **avant** la date présumée : le postnatal est prolongé d'autant de jours ; **après** : sans effet. Licenciement pendant la période **nul**. Travail interdit. Prestations selon la sécurité sociale. | `maternity_total_days = 126`, `maternity_postnatal_days = 84`, `maternity_extension_days = 21` (**Code**). `début = date_présumée − 42 j` ; `fin = date_accouchement + 84 j + max(0, date_présumée − date_accouchement)` ; `+21 j` si justificatif médical. `maternity_pay_mode` (maintien employeur ou prestation CSS) : **à fournir**. | **[B]** sortie ou licenciement pendant la période. **[B]** présence saisie pendant la période. **[A]** durée > 126 j sans justificatif médical. État : ✘ **`MATERNITE max_days_per_year = 98` (14 semaines) à corriger en 126/147**. |
| CNG-11 | 275, 276, 278-280 | Grossesse : **aucune discrimination** et **interdiction de rechercher l'information** ; absences pour examens obligatoires **payées**. Travaux dangereux : mutation **sans baisse de rémunération**, sinon suspension avec **salaire intégral** et ancienneté maintenue. **Allaitement : 1 h par jour pendant 20 mois**, rémunérée. Démission **sans préavis** possible pendant la grossesse et l'allaitement. | `nursing_months = 20`, `nursing_daily_hours = 1` (**Code**). L'état de grossesse n'est saisi **que sur déclaration de la salariée**, accès RH uniquement. | **[B]** champ de grossesse demandé ou rendu obligatoire à l'embauche. **[B]** baisse de rémunération lors d'une mutation pour grossesse. **[A]** fin d'allaitement = fin du congé de maternité + 20 mois. État : ➕. |
| CNG-12 | 114, 115 | **Maladie** : suspension limitée à **6 mois, prorogeable jusqu'à la rupture**. L'employeur verse une **allocation égale à la rémunération pendant une durée équivalente au préavis**, déduction faite des indemnités perçues pour le même motif ; stipulations conventionnelles plus favorables réservées. CDD : préavis de la convention ou de l'arrêté de branche. | `sick_pay_duration = durée_du_préavis(catégorie)` ; `sick_pay_rate = 100 %` (**Code** pour la durée ; taux au-delà : convention) ; `sick_pay_offset = true` (déduction des prestations IPM/CSS perçues). Justificatif médical obligatoire. | **[B]** maladie sans certificat médical joint. **[A]** à 80 % de la durée indemnisable. **[A]** suspension > 6 mois. État : ✔ taux (`sick_leave_rate` = 100 %) ; ? plafond de durée absent du moteur. |
| CNG-13 | 114, 117 | Liste de **18 cas de suspension**. Ne comptent **pas** dans l'ancienneté : fermeture pour départ militaire de l'employeur (1), service militaire (2), mandat public (3), **mise en disponibilité** (11). Détention provisoire à l'initiative de l'employeur clôturée par non-lieu, relaxe, acquittement ou désistement : **compte**. Disponibilité : sans salaire, ni avancement, ni ancienneté, ni retraite ; exceptionnelle, à l'appréciation de l'employeur. | `ancienneté_effective = date_fin − seniority_start_date − Σ jours des suspensions {1, 2, 3, 11}`. Table `contract_suspensions(employee_id, case_no 1-18, start, end, counts_for_seniority, counts_for_leave, pay_rule)`. | **[B]** ligne de paie sur une période de disponibilité. **[A]** suspension sans pièce (ordre, certificat). État : ✘ l'ancienneté est `DATEDIF(date d'entrée)` sans déduction (prime d'ancienneté, indemnités et congés concernés). |
| CNG-14 | 116, 369 | Fermeture provisoire **sanction** : travailleurs réputés au travail, salaire et avantages conservés **3 mois**. Arrêt de travaux ou fermeture décidé par l'inspecteur : salaire et avantages **maintenus** pendant l'arrêt. | Types d'absence `FERMETURE_SANCTION` (cap 3 mois) et `ARRET_INSPECTION`, payés 100 %. | **[A]** retenue d'absence appliquée sur ces motifs. État : ➕. |
| CNG-15 | 118-126 | **Chômage technique** (causes conjoncturelles, accident matériel, intempéries, pénurie, pandémie, guerre). Procédure : recherche de mesures alternatives avec les délégués (**PV**), accord (durée + allocation) transmis à l'inspecteur sous **3 jours ouvrables**, sinon autorisation de l'inspecteur (**15 jours francs**, silence = rejet ; recours hiérarchique **7 jours ouvrables** puis 15 jours francs). Durée ≤ **1 an renouvellement compris**. Irrégulier = **nul**. Allocation ≥ **50 % de la rémunération moyenne brute des 2 derniers mois travaillés**. Le travailleur en CDI peut démissionner sans préavis. | `ALLOC_CHOMAGE_TECH = max(montant_accord ; 0,50 × (brut_{n−1} + brut_{n−2}) ÷ 2)` sur « les deux derniers mois travaillés ». `tech_layoff_max_days = 365`, `tech_layoff_min_rate = 0,5` (**Code**). Table `technical_layoffs`. Traitement social et fiscal de l'allocation : **à confirmer**. | **[B]** allocation de chômage technique sans référence d'accord ou d'autorisation. **[B]** cumul > 365 jours. **[A]** délais de transmission du PV (3 jours ouvrables). État : ➕. |
| CNG-16 | 145 | Pendant le **préavis**, **2 jours ouvrés par semaine** de liberté pour chercher un emploi, **payés à plein salaire** ; l'inobservation dispense l'autre partie du préavis restant. | Type d'absence `RECHERCHE_EMPLOI`, payé 100 %, plafond 2 jours par semaine pendant le préavis. | **[A]** retenue d'absence sur ces jours. État : ➕. |
| CNG-17 | 178-181 | **Formation imposée** : salaire intégral, coût à la charge de l'employeur ; l'échec à un examen ne justifie pas un licenciement. **Dédit-formation** : durée minimale de service ≤ **4 ans**, remboursement **au prorata** de la période non travaillée. Congé de formation individuel : à la discrétion de l'employeur, aux frais du salarié. | Table `training_commitments(cost, min_service_months ≤ 48, start)` ; `remboursement = coût × (durée_min − durée_effectuée) ÷ durée_min`. Statut d'absence `FORMATION` payé 100 %. | **[B]** clause de dédit > 48 mois. **[B]** remboursement retenu sur salaire sans autorisation (voir RET-01). État : ➕ (module Dev09 formation à rapprocher). |

### 2.D Rémunération, paiement et bulletin (arts. 193-213)

| ID | Art. | Règle de droit | Règle de gestion et paramètres | Garde-fous · État |
|---|---|---|---|---|
| REM-01 | 9, 193 | **À travail égal ou de valeur égale, rémunération égale**, quels que soient l'origine, le sexe, l'âge, le statut. | Rapport « équité salariale » : écart de salaire par catégorie, grade, ancienneté et sexe. | **[A]** écart > seuil paramétrable (`pay_gap_alert_pct`, **à fournir**) à catégorie et ancienneté égales. État : ➕. |
| REM-02 | 194 | **Aucun salaire n'est dû en cas d'absence**, hors situations réglementaires, conventionnelles ou convenues. | `retenue_absence = (base + sursalaire + honoraires + autre fixe) ÷ H × heures_absence` (existant). | **[A]** absence retenue sur un motif légalement rémunéré (CNG-10 à CNG-17). État : ✔ formule ; ➕ contrôle du motif. |
| REM-03 | 195, 78 | **SMIG** fixé par décret ; **catégories et minima** par convention, à défaut par arrêté ; primes d'ancienneté et d'assiduité éventuellement par arrêté. | `smig_hourly` (registre RL-010 : **écart probable**, à confirmer) ; grille `employee_grades` datée par `effective_from`. | **[B]** salaire de base < minimum de la grille à date. **[A]** taux horaire < SMIG. État : ✔ grille ; ? contrôle automatique. |
| REM-04 | 197 | Commissions, primes, avantages divers ou indemnités représentatives (hors remboursement de frais) **entrent dans le calcul** de l'allocation de congé, de l'indemnité de préavis, de l'indemnité de licenciement et des dommages-intérêts ; montant retenu = **moyenne mensuelle des 12 derniers mois d'activité**. Liste des frais : **arrêté conjoint** Finances/Travail. | `M12 = (Σ_{12 derniers mois d'activité} éléments bruts hors frais) ÷ nb_mois_pris` (moins de 12 mois d'activité : moyenne sur les mois disponibles). Paramètre `average_basis_months = 12` (**Code**). | **[B]** indemnité de préavis, de licenciement ou de rupture amiable calculée sans `M12` complet. État : ✘ `severance_basis = average12` ne retient que base + sursalaire + prime d'ancienneté. |
| REM-05 | 198 | Paiement en monnaie légale par **espèces, chèque, virement ou moyen électronique**. **Interdit** : alcool ; paiement en nature (sauf logement, art. 260). Paie sur le lieu de travail pendant les heures de travail, **temps payé comme temps de travail**. Pas de paie dans un débit de boissons. | `payment_mode ∈ {espèces, virement, chèque, mobile money}`. | **[B]** composant de type « nature » hors logement. État : ✔ modes. |
| REM-06 | 199 | **Périodicité** : au plus **1 mois** (salaire mensuel), **15 jours** (horaire ou journalier). Paiement mensuel au plus tard **8 jours après la fin du mois** ; quinzaine : 4 jours ; semaine : 2 jours. Occasionnel : payé en fin de travail (≤ 6 jours ouvrables consécutifs). Commissions trimestrielles : dans les 3 mois suivant le trimestre. Travail aux pièces > 15 jours : acomptes ≥ **90 % du SMIG** par quinzaine. | `pay_deadline = dernier_jour_du_mois + 8` (**Code**). Règle interne SOMA : cible le **28** du mois, au plus tard le **5** du mois suivant (plus stricte que la loi). | **[A]** J-2 avant le 5 (interne). **[B]** paiement enregistré après `pay_deadline` : motif de retard obligatoire. État : ✔ suivi du paiement (lot 3) ; ➕ échéance légale. |
| REM-07 | 200, 201 | À la cessation du contrat : salaire, accessoires, primes et indemnités **payés dès la cessation du service**. Paiement **direct et personnel** (pas d'intermédiaire) ; à défaut en mains propres : virement sur le compte du travailleur, mandat ou moyen électronique **à son nom**. | `final_pay_due_date = relieving_date`. Champs `bank_account_holder`, `mobile_money_msisdn`, `mobile_money_holder`. | **[A]** sortie enregistrée et solde de tout compte non payé le jour de la sortie. **[B]** compte ou numéro mobile au nom d'un tiers. État : ✘ pas de contrôle du titulaire ; ✔ solde de tout compte (Dev06). |
| REM-08 | 202, 203 | **Bulletin de paie obligatoire** pour tout paiement, physique ou électronique, **établi, certifié et transmis au moment du paiement** ; physique : **émargé** (signature ou 2 témoins si illettré, **sans empreinte**) ; électronique : disponibilité, intégrité, confidentialité, protection des données. **Chaque élément est individualisé** avec sa cause exacte et son décompte ; sans individualisation, le paiement est présumé représenter le **salaire de base**. Mentions et conservation : **arrêté** (à fournir). | Table `payslip_deliveries(slip_id, channel, delivered_at, acknowledgement_type, witnesses)`. Chaque ligne du bulletin : libellé, base, quantité, taux, gain/retenue (existant dans `salary_slip_details`). | **[B]** paiement marqué « payé » sans bulletin validé. **[B]** montant forfaitaire sans libellé ni cause (rubriques « divers »). **[A]** bulletin non remis à J+1. État : ✔ lignes détaillées ; ✘ remise et accusé non tracés ; ✘ rubriques « divers » possibles. |
| REM-09 | 204 | La mention « **pour solde de tout compte** » souscrite par le travailleur n'est **pas opposable**. Accepter un bulletin sans réserve **ne vaut pas renonciation** ni compte arrêté. | Le modèle de solde de tout compte ne contient **aucune clause de renonciation ou de quittance générale** ; il peut contenir un simple accusé de réception des sommes. | **[B]** modèle de document comportant « pour solde de tout compte » ou une renonciation. État : ? à vérifier dans `solde_tout_compte`. |
| REM-10 | 205 | **Présomption irréfragable de non-paiement** si l'employeur ne produit pas : (a) le double du bulletin **émargé**, (b) un **reçu signé** (espèces), (c) la preuve d'un **chèque encaissé** + avis de débit, (d) l'**attestation** d'un établissement bancaire ou de monnaie électronique. | Table `payment_proofs(payment_id, proof_type ∈ {EMARGEMENT, RECU_ESPECES, CHEQUE_ENCAISSE+AVIS_DEBIT, ATTESTATION_BANQUE, ATTESTATION_MONNAIE_ELECTRONIQUE}, document_id, reference, date)`. Pièce exigée selon `payment_mode`. | **[B]** clôture d'un mois avec une ligne « payée » sans pièce. **[A]** pièce manquante à J+7. État : ✘ le suivi du paiement (lot 3) enregistre le statut, pas la pièce probante. |
| REM-11 | 212, 213 | Prescription **5 ans** des actions du salarié **et** de l'employeur ; **10 ans** si le serment déféré n'est pas prêté ou si le non-paiement est reconnu. | `payroll_retention_years = 5` (**Code**) ; **recommandé : 10** pour les bulletins et pièces de paiement. | **[B]** purge ou suppression d'un bulletin ou d'une pièce de moins de 5 ans. État : ➕ (politique de conservation à écrire). |

### 2.E Retenues sur salaire, avances et prêts (arts. 180, 214-217, 234, 452)

| ID | Art. | Règle de droit | Règle de gestion et paramètres | Garde-fous · État |
|---|---|---|---|---|
| RET-01 | 214 | **Seules** retenues permises : prélèvements obligatoires, **cotisation syndicale** (sur demande écrite du travailleur, reversée au syndicat qu'il désigne), remboursement du **logement** fourni (art. 260), **cession volontaire** de salaire régulière. Les cotisations de prévoyance sociale sont prélevées d'office. | Table de référence `deduction_types(code, legal_basis, needs_written_authorization, cap_rule)`. Types autorisés : `COTISATION_SOCIALE`, `IMPOT_OBLIGATOIRE`, `SYNDICAT`, `LOGEMENT`, `CESSION_VOLONTAIRE`, `SAISIE_ATTRIBUTION`. Table `deduction_authorizations(employee_id, deduction_type, signed_on, document_id, max_amount, end_date)`. | **[B]** retenue d'un type hors liste ou sans autorisation signée lorsqu'elle est exigée. État : ✘ les retenues sur net actuelles (avance Korité, avance caisse, avance financière, coopérative, frais médicaux, caisse commune) ne sont rattachées ni à un type légal ni à une autorisation. |
| RET-02 | 217, 216 | Toute stipulation (convention ou contrat) autorisant une autre retenue est **nulle de plein droit**. Les sommes retenues à tort **portent intérêt au taux légal** dès l'exigibilité et sont réclamables jusqu'à la prescription (suspendue pendant le contrat). | `legal_interest_rate` (taux légal : **à fournir**) pour l'estimation d'exposition. | **[A]** retenues sans autorisation : exposition = montant + intérêts depuis l'exigibilité. État : ➕. |
| RET-03 | 215 | Les **acomptes** sur travail accompli ne sont pas des avances. **Avances** plafonnées à **6 fois la quotité cessible** du salaire. Le remboursement d'un **prêt** ne peut être retenu **que par saisie-attribution ou cession volontaire** (art. 571-1 à 571-6 du Code de procédure civile). Autre compensation : **décision de justice**, sauf rupture imputable au travailleur. | `advance_cap = 6 × quotité_cessible(salaire)`. Marqueur `exit_imputable_to_employee` (démission, faute lourde) qui autorise la compensation au solde de tout compte. | **[B]** somme des avances ouvertes > `advance_cap`. **[B]** retenue de remboursement d'un prêt sans cession volontaire signée. **[A]** retenue au solde de tout compte hors sortie imputable au travailleur. État : ✘ module prêts et avances (lot L2) à confronter à ces règles. |
| RET-04 | 216 | **Quotité cessible** : fractions de salaire soumises à prélèvements **progressifs**, taux fixés par l'art. 381 du Code de procédure civile ; l'assiette est le **salaire brut global** (salaire, accessoires, allocation de congé, primes, indemnités, prestations, sommes dues pour la rupture, dommages-intérêts) ; la retenue ne peut excéder ces taux **à chaque paie**. | Table `garnishment_scale(from_amount, to_amount, rate)` : **à fournir** (le texte de l'art. 381 CPC n'est pas dans le JO analysé). | **[B]** total des retenues de ce chapitre > quotité cessible du mois. **[A]** barème non renseigné : les plafonds sont désactivés et signalés. État : ➕. |
| RET-05 | 234 | **Une seule sanction par faute. Les sanctions pécuniaires (amendes) sont interdites**, toute clause contraire est nulle. | Aucune rubrique de retenue à titre de sanction. La retenue d'absence (REM-02) reste une proratisation, pas une sanction. | **[B]** composant de retenue libellé « amende », « pénalité » ou « sanction ». **[A]** retenue pour retard supérieure au temps non travaillé. État : ✔ aucune rubrique de ce type. |
| RET-06 | 452 | Délit : l'employeur qui **retient ou utilise pour son intérêt** les prélèvements opérés sur les salaires (cotisations, impôts) encourt **500 000 à 5 000 000 F** et **3 mois à 1 an**. | Suivi du **reversement** des cotisations salariales, de l'IR, du TRIMF et de la BRS (statuts `à reverser`, `reversé`, preuve). Échéances : **à confirmer** (Code de la sécurité sociale, CGI). | **[A]** retenue opérée non reversée à l'échéance. État : ➕ (exports IPRES/DGID de Dev04 sans suivi du reversement). |

### 2.F Cessation du contrat de travail (arts. 126-175, 335-338)

| ID | Art. | Règle de droit | Règle de gestion et paramètres | Garde-fous · État |
|---|---|---|---|---|
| RUP-01 | 163, 164, 126, 278, 280 | **Démission** : acte volontaire, exprès, non équivoque, **jamais présumée**, notifiée par écrit (recommandée avec accusé ou remise contre accusé). **Sans préavis** : CDI en chômage technique, femme enceinte, mère pendant l'allaitement. | Motif `DEMISSION` (avec préavis) ou `DEMISSION_SANS_PREAVIS` (cas listés). Pièce : lettre de démission. | **[B]** `DEMISSION` sans lettre jointe. **[A]** départ pour « abandon de poste » traité comme démission (non permis). État : ✔ motif `DEMISSION` ; ✘ pièce et variante sans préavis. |
| RUP-02 | 142-147 | **Rupture unilatérale du CDI** effective à l'expiration du préavis, qui court de la **remise de la lettre**, sans condition. Sans préavis seulement pour **faute lourde**. Durée : **décret ou convention** (art. 144). Indemnité compensatrice = **rémunération et avantages de toute nature** (hors remboursements de frais) du délai de préavis ; **doublée** si la rupture intervient pendant le congé ; le congé ne s'impute pas sur le préavis sans accord écrit. Le licencié qui doit occuper un nouvel emploi peut partir sans indemnité. | `notice_scales(agreement_code, category, seniority_min_months, notice_months)` (**à fournir**). `date_fin_préavis = date_remise_lettre + durée`. `INDEMN_PREAVIS = durée_restante × (rémunération mensuelle habituelle + avantages + part variable M12)` ; `× 2` si `notification_during_leave`. | **[B]** sortie par licenciement ou démission sans `notice_months` ni date de remise de lettre. **[A]** préavis non exécuté sans indemnité calculée. État : ✘ **aucune gestion du préavis dans le schéma** (ni durée, ni indemnité compensatrice). |
| RUP-03 | 148-150, 137 | **Licenciement pour motif personnel** : cause **réelle et sérieuse**, notification écrite (recommandée avec accusé ou remise contre accusé) mentionnant **le ou les motifs, la date de prise d'effet, la durée du préavis** (sauf faute lourde). Irrégularité de forme seule : indemnité du tribunal **≤ 3 mois de salaire brut**. Preuve de la cause à la charge de l'employeur. | Pièces : demande d'explication ou convocation, procès-verbal d'entretien, lettre de licenciement (DIS-02). `provision_irregularité = 3 × salaire_brut_mensuel` (information). | **[B]** `LICENCIEMENT_PERSONNEL` sans lettre contenant motif, date d'effet et préavis. **[B]** sans demande d'explication ou entretien préalable (art. 236). État : ➕ (motif `LICENCIEMENT` unique). |
| RUP-04 | 152-157 | **Licenciement économique** (difficultés durables, mutations technologiques, réorganisation, cessation). Étapes : réunion avec les délégués pour **mesures alternatives** (réduction d'heures, roulement, chômage technique, formation, redéploiement, réduction des primes) avec PV ; PV communiqué à l'inspecteur sous **7 jours ouvrables**, qui dispose de **15 jours francs** pour ses bons offices ; **ordre des licenciements** (moindres aptitudes d'abord, puis ancienneté **majorée d'1 an si marié et d'1 an par enfant à charge**) ; liste et critères communiqués aux délégués, réunion **≥ 7 jours ouvrables** après ; liste et PV à l'inspecteur sous **7 jours ouvrables** ; lettre art. 149. Droits : préavis + **indemnité de licenciement** + **indemnité spéciale = 1 mois de salaire brut** ; **priorité d'embauche 2 ans** (avis par lettre avec accusé ; réponse sous **7 jours ouvrables**). | `ancienneté_majorée = ancienneté + (1 si marié) + (1 × nb_enfants_à_charge)`. `INDEMN_SPECIALE = 1 × salaire_brut_mensuel`. `rehire_priority_until = relieving_date + 24 mois`. Table `layoff_procedures(case_id, motif, steps[], pv_documents[], list_sent_on, list_meeting_on)`. | **[B]** lettre de licenciement économique avant la fin du délai de 15 jours francs ou sans PV. **[B]** `LICENCIEMENT_ECONOMIQUE` sans indemnité spéciale. **[A]** poste vacant dans la catégorie d'un salarié bénéficiant de la priorité d'embauche. État : ✘ indemnité spéciale et procédure absentes ; ✘ pas de date de naissance des enfants ni de statut « à charge ». |
| RUP-05 | 158-162 | **Cessation d'activité** : totale = cause réelle et sérieuse (sauf faute de l'employeur) ; partielle seulement si justifiée par une réorganisation interne ; liquidation judiciaire = licenciement ; lettre art. 149, préavis applicable, **indemnité spéciale de 1 mois + indemnité de licenciement**. Créances de salaire payées **dans les 10 jours** de l'ouverture de la liquidation (art. 208). | Motif `CESSATION_ACTIVITE` : mêmes calculs que RUP-04 sans ordre de licenciement. | **[B]** `CESSATION_ACTIVITE` sans indemnité spéciale. État : ➕. |
| RUP-06 | 127-129 | **Rupture amiable** : convention (identité, ancienneté, emploi et catégorie, indemnités, date d'effet), assistance possible, déposée en **4 exemplaires** à l'inspection. **Indemnité ≥ indemnité de licenciement** ; sous 12 mois d'ancienneté, calcul **en mois et en jours**. | `INDEMN_RUPTURE_AMIABLE = max(montant_convenu ; INDEMN_LICENCIEMENT_théorique)` ; en deçà de 12 mois : proratisation `ancienneté_mois + jours ÷ 30`. | **[B]** montant convenu < indemnité de licenciement théorique. **[B]** convention non déposée. État : ➕. |
| RUP-07 | 130-133 | **Plan social** : convention avec les délégués (motifs, nombre d'emplois, conditions, candidatures, critères de départage, suivi, date). Indemnités : **équivalent préavis + équivalent licenciement + indemnité spéciale (1 mois brut) + indemnité de plan social négociée**. Déposé en **4 exemplaires** ; régime fiscal du CGI. | Motif `PLAN_SOCIAL` ; `INDEMN_PLAN_SOCIAL = préavis + licenciement + 1 mois brut + montant_négocié`. | **[B]** plan sans dépôt. État : ➕. |
| RUP-08 | 151, 197, 156 | **Indemnité de licenciement** due **sauf faute lourde**, dès que la durée de service atteint la **période de référence du congé (12 mois)** ; **distincte** du préavis. Barème : **convention et règlements**. Assiette : moyenne 12 mois (art. 197). Les départs économiques antérieurs se cumulent après plusieurs embauches, **sous déduction des sommes déjà versées**. | `INDEMN_LICENC = Σ_{tranches}(taux × années_dans_la_tranche) × M12`. Table `severance_scales(agreement_code, kind ∈ {LICENCIEMENT, RETRAITE, DECES}, from_years, to_years, rate)`. **Défaut : héritée** (valeurs du moteur) : LICENCIEMENT 25 % jusqu'à 5 ans, 30 % de 5 à 10 ans, 40 % au-delà ; RETRAITE 25 % / 30 % / 45 % (10 à 20 ans) / 50 % (au-delà de 20 ans). Éligibilité : `ancienneté ≥ 12 mois`. | **[B]** versement d'une indemnité de licenciement pour une ancienneté < 12 mois (hors rupture amiable ou plan social). **[B]** versement en cas de faute lourde. État : ✘ `severance_coefficient` en dur, indifférent à la convention et **sans seuil de 12 mois** (il calcule une fraction dès le premier mois). |
| RUP-09 | 143, 151, 166, 172 | **Faute lourde** : rupture sans préavis, sans indemnité de licenciement ; rupture anticipée du CDD possible ; mise à pied conservatoire du délégué. Appréciée par le juge. | Indicateur `gross_misconduct` (avec procès-verbal). Prescription des faits : **2 mois** (DIS-02). | **[B]** faute lourde invoquée sans procédure disciplinaire complète. **[A]** faits connus depuis plus de 2 mois. État : ➕. |
| RUP-10 | 165-167 | **CDD** : cesse de plein droit au terme (la suspension ne le proroge pas). Rupture anticipée **uniquement** pour faute lourde, accord écrit ou force majeure, sinon dommages-intérêts. **Indemnité de fin de contrat = 7 % de la rémunération brute totale due pendant la durée du contrat**, hors remboursements de frais ; calculée sur **la durée totale de deux CDD successifs** ; **non due** dans les cas 1 à 7 de l'art. 101 ou si le travailleur **refuse un CDI** (même emploi ou similaire, salaire au moins égal). | `INDEMN_FIN_CDD = precarity_rate × Σ_{CDD successifs}(brut_dû − composants frais)` ; `precarity_rate = 7 %` (**Code**). Indicateurs `cdd_motif.precarity_due`, `refused_cdi_offer`. | **[B]** indemnité versée pour un motif exempté. **[B]** indemnité non versée en l'absence d'exemption ou de refus de CDI. **[A]** assiette hors HS et primes. État : ✔ taux 7 % ; ✘ assiette actuelle « base + sursalaire + prime d'ancienneté + Tabaski » (analyse du classeur) ; ✘ exemptions et refus de CDI. |
| RUP-11 | 134, 135 | **Retraite** : le contrat cesse (ni démission ni licenciement). Âge fixé par **décret** ; retraite anticipée possible **5 ans** avant ; poursuite par accord écrit jusqu'à **5 ans** après ; âge dérogatoire pour emplois pénibles (décret). Indemnité de départ : **convention et règlements**. | `retirement_age` (**à fournir**), `early_retirement_years = 5`, `retirement_extension_years = 5` (**Code**). Barème `severance_scales.kind = RETRAITE`. | **[A]** J-6 mois avant l'âge normal. **[A]** maintien au-delà de l'âge sans accord écrit. **[B]** maintien > âge + 5 ans. État : ✔ indemnité de retraite (coefficients hérités) ; ➕ alertes (`date_of_birth` disponible). |
| RUP-12 | 136 | **Décès** : contrat rompu ; salaires, indemnité compensatrice de congé et **indemnités acquises** vont aux héritiers ou ayants droit (justification de qualité) ; **indemnité de décès** si ≥ 1 an d'ancienneté (convention) ; certificat de travail remis aux héritiers. | `exit_reason = DECES` ; `INDEMN_DECES` selon `severance_scales.kind = DECES` (**à fournir**) ; table `heirs(employee_id, name, quality_proof_document)`. | **[B]** paiement au nom d'un tiers sans justificatif de qualité d'héritier (exception à REM-07). État : ✔ motif `DECES` ; ➕ bénéficiaires. |
| RUP-13 | 335-338, 283 | **Inaptitude non professionnelle** : suspension ; **contre-expertise** à la demande du travailleur sous **15 jours ouvrables** (à ses frais, 3e médecin en cas de désaccord) ; **reclassement** recherché avec les délégués (PV transmis à l'inspecteur sous **2 jours ouvrables**) ; à défaut, licenciement **sans préavis mais avec indemnité compensatrice de préavis**. Inaptitude professionnelle : Code de la sécurité sociale. Jeune ou handicapé inapte : rupture avec préavis et, éventuellement, indemnité de licenciement. | Motif `INAPTITUDE_NON_PRO` ou `INAPTITUDE_PRO`. Dossier `medical_inaptitude_cases` (dates, contre-expertise, PV de reclassement). | **[B]** licenciement pour inaptitude non professionnelle sans PV de recherche de reclassement. **[B]** sans indemnité compensatrice de préavis. État : ➕. |
| RUP-14 | 140 | **Certificat de travail** remis au départ définitif (remise contre accusé ou autre moyen datant la preuve ; tenu à disposition si le travailleur ne vient pas) ; il indique **exclusivement** : date d'entrée, date de sortie, **nature et dates des emplois successifs**, **catégorie de la convention collective**. Exempt de timbre ; aucun renseignement tendancieux. Astreinte et dommages-intérêts en cas de défaut. | Génération depuis l'historique d'emplois (`employee_events`) ; champs `certificate_delivered_on`, `certificate_delivery_proof`. | **[B]** mention du motif de départ, du salaire ou d'une appréciation. **[A]** certificat non remis à J+8 de la sortie. État : ✘ la fonction `certificat_travail` cite « art. L.55 » (abrogé) ; à compléter par la catégorie de convention et les emplois successifs ; remise non tracée. |
| RUP-15 | 138, 139, 150, 174, 175 | **Dommages-intérêts** fixés par le juge (usages, nature et ancienneté des services, âge, droits acquis), **distincts** du préavis et de l'indemnité de licenciement ; **renonciation anticipée interdite**. **Délégué du personnel** licencié irrégulièrement : réintégration + indemnité = salaire qui aurait été perçu ; refus de réintégrer après **15 jours** : indemnité de **12 mois** (< 5 ans), **20 mois** (5 à < 10 ans), **2 mois par année de présence, plafond 36 mois** (≥ 10 ans). | Fonction d'exposition `dp_non_reinstatement_exposure(ancienneté, salaire_brut)` ; tableau de provisions de risque contentieux (information, jamais payé automatiquement). | **[A]** exposition affichée avant toute sortie d'un salarié protégé. État : ➕. |
| RUP-16 | 60, 168-173 | **Délégué du personnel** (mandat **3 ans**, renouvelable) : licenciement soumis à **autorisation préalable de l'inspecteur** (15 jours francs, 30 si enquête technique ; silence = rejet) pour le **candidat** (de la remise des listes au scrutin), le **délégué en mandat** et l'**ancien délégué** jusqu'à **3 mois après** le scrutin ; sans autorisation : **nul** ; mise à pied conservatoire possible en cas de faute lourde (salaire dû si refus). Temps de délégation **rémunéré comme temps de travail** (durée fixée par décret). | Table `employee_representatives(employee_id, role ∈ {DP, DP_SUPPLEANT, CANDIDAT, SST}, start, end, protected_until)`. `delegate_hours_per_month` (**à fournir**). | **[B]** sortie d'un salarié protégé sans référence d'autorisation. **[A]** retenue d'absence sur heures de délégation. État : ➕. |
| RUP-17 | 114-18, 436-439, 451 | **Grève** licite : suspension du contrat (préavis de **30 jours calendaires** après conciliation partielle ou échec) ; grève ou lock-out **illicites** : l'employeur doit les **salaires des journées perdues** (lock-out) et le travailleur perd les indemnités de rupture et s'expose à des sanctions disciplinaires ; **réquisition** non respectée : **100 000 à 1 000 000 F** et licenciement sans préavis. | Type d'absence `GREVE` (retenue comme absence, art. 194) ; marqueur `strike_status ∈ {LICITE, ILLICITE}`. | **[A]** journées de lock-out illicite à payer. État : ➕. |

### 2.G Intéressement, participation, épargne, avantages sociaux (arts. 218-231)

| ID | Art. | Règle de droit | Règle de gestion et paramètres | Garde-fous · État |
|---|---|---|---|---|
| PAR-01 | 218, 219 | **Intéressement** facultatif, par **accord collectif** avec les délégués (montant, calcul, échéance) ; avantage fiscal du CGI si versé dans un plan d'épargne salariale. | Table `profit_sharing_agreements`. Composant `INTERESSEMENT` (gain). | **[B]** versement sans accord enregistré. État : ➕. |
| PAR-02 | 225-229 | **Participation aux bénéfices** par accord (règles de calcul, répartition, plafonnement). Bénéficiaires : **tous les travailleurs**, avec condition de présence **≤ 6 mois**. Répartition : uniforme, proportionnelle au salaire ou au temps de présence, ou multi-critères. **Versement ≤ 9 mois après la clôture de l'exercice** ; choix cash ou plan d'épargne (indisponibilité **5 ans** en PEE, **jusqu'à la retraite** en plan retraite). Dépôt à la DGID et à la DGTSS pour l'avantage fiscal. | `PART_i = Pool × poids_i ÷ Σ poids` avec `poids = 1` (uniforme), `salaire_période_i` ou `jours_présence_i`. `participation_min_months ≤ 6` (**Code**), `participation_pay_deadline = clôture_exercice + 9 mois` (**Code**). | **[B]** condition de présence > 6 mois. **[A]** J-30 avant l'échéance de 9 mois. État : ➕. |
| PAR-03 | 220-224 | **Plans d'épargne d'entreprise et de retraite** : accord collectif, abondement facultatif ; adhésion volontaire à un plan retraite avec **option de réversion**. | Table `savings_plans`. Faible priorité. | **[A]** plan sans accord déposé. État : ➕. |
| PAR-04 | 230, 231, 232 | **Avantages sociaux** facultatifs (vente de marchandises, cantine, tickets-repas, coopérative, installations, bons) : jamais obligatoires pour le travailleur, **prix justes, sans bénéfice**, affichés ; **alcool interdit** dans les cantines et lieux de travail. | Les adhésions (coopérative, caisse commune) passent par RET-01 (autorisation écrite et révocable). | **[B]** retenue de coopérative ou caisse commune sans adhésion volontaire signée. État : ✘ voir RET-01. |

### 2.H Discipline, règlement intérieur, harcèlement, discrimination (arts. 4-22, 232-240)

| ID | Art. | Règle de droit | Règle de gestion et paramètres | Garde-fous · État |
|---|---|---|---|---|
| DIS-01 | 232, 233 | **Règlement intérieur** limité à : organisation des espaces et outils (y compris données personnelles et TIC), discipline et droits de la défense, sécurité et santé (dont violence et harcèlement). **Toute autre clause, notamment sur la rémunération, est nulle.** Projet communiqué aux délégués, déposé à l'inspection ; seuil d'obligation par arrêté. | Table `internal_rules(version, adopted_on, deposit_ref, dp_opinion_ref)`. | **[A]** règlement sans dépôt. **[A]** mention d'une clause de rémunération dans le texte importé. État : ➕. |
| DIS-02 | 234-240 | **Procédure disciplinaire** : une seule sanction par faute ; **prescription 2 mois** à compter de la connaissance des faits (sinon sanction abusive) ; **demande d'explication écrite** (réponse ≥ **2 jours ouvrés**) ou **entretien préalable** (convocation précisant date, heure, lieu, faits, assistance ; **pas avant 5 jours ouvrables** après réception) ; PV signé le jour même ; **temps d'entretien payé** ; sanction notifiée par recommandée avec accusé ou remise contre accusé ; mise à pied comptée en **jours ouvrés**. | `sanction_deadline = date_connaissance + 2 mois`. `earliest_interview = réception_convocation + 5 jours ouvrables`. `min_reply_date = réception_demande + 2 jours ouvrés`. Table `disciplinary_cases(employee_id, facts_known_on, explanation_request_on, interview_on, pv_document, sanction_type, notified_on, suspension_days)`. | **[B]** sanction notifiée après `sanction_deadline`. **[B]** entretien avant `earliest_interview`. **[B]** sanction sans demande d'explication ni entretien. **[B]** deuxième sanction pour les mêmes faits. État : ➕. |
| DIS-03 | 17-21, 453, 454 | **Violence et harcèlement** interdits (y compris entre travailleurs, stagiaires, apprentis, candidats) ; employeur : **moyens raisonnables de prévention** ; **charge de la preuve** sur le défendeur ; aucune décision défavorable (embauche, rémunération, formation, affectation, classification, promotion, mutation, déplacement, sanction, **renouvellement, prolongation ou résiliation de contrat**) contre la personne qui refuse, dénonce ou témoigne. Peines : **200 000 à 5 000 000 F** et **1 mois à 1 an** (moral et représailles) ; harcèlement ou violence sexuelle/physique : Code pénal. | Table confidentielle `harassment_reports(reporter_id, accused_id, status, protected_until)` accessible RH/direction. `reporter_protection_months` (**à fournir**). | **[A]** toute décision défavorable (sanction, mutation, non-renouvellement, sortie) visant un salarié déclarant ou témoin : revue RH obligatoire avant validation. État : ➕. |
| DIS-04 | 4, 8-15, 456 | **Discrimination interdite** (race, couleur, âge, sexe, activité syndicale, religion, opinion politique, origine, handicap, **grossesse**, situation de famille, **état de santé**, **statut sérologique**, apparence, mandat électif) ; présomption en faveur de la victime ; actes **nuls** ; peines **500 000 à 10 000 000 F** et **3 mois à 1 an**. Distinctions admises : exigences professionnelles essentielles, protection du jeune, inaptitude constatée par voie médicale. | **Minimisation des données** : ne jamais saisir le statut sérologique, la grossesse (sauf déclaration volontaire, CNG-11) ni l'appartenance syndicale (sauf autorisation de retenue, RET-01) comme critères d'embauche ou de paie. | **[B]** champ sensible ajouté aux formulaires d'embauche ou de paie. **[A]** exports RH contenant des champs sensibles. État : ✔ (aucun champ de ce type dans `employees`) ; ➕ liste interdite à inscrire dans la politique de conformité. |

### 2.I Déplacement, mutation, transport, logement, sous-traitance (arts. 3, 258-267, 287-299)

| ID | Art. | Règle de droit | Règle de gestion et paramètres | Garde-fous · État |
|---|---|---|---|---|
| MOB-01 | 3, 258 | **Déplacement** : prestation hors du lieu habituel, **≤ 6 mois consécutifs** ; **indemnité de déplacement** dont taux et modalités sont fixés par convention ou accord. **Mutation** : changement de lieu **> 6 mois**. | `trip_allowance_rates(agreement_code, category, daily_rate)` (**à fournir**). `trip_threshold_months = 6` (**Code**). Distinction automatique déplacement/mutation selon la durée. | **[A]** déplacement > 6 mois non requalifié en mutation. État : ➕ (ordres de mission : feuille de route lot 5). |
| MOB-02 | 259-263, 266 | **Mutation** : délai préalable fixé par l'employeur, **jamais < 15 jours calendaires** (à compter de l'acceptation si elle est requise), sauf urgence ; **logement adéquat** pour le travailleur et sa famille (conditions et valeur maximale de remboursement par arrêté) ; **frais de transport** du travailleur, conjoint, enfants mineurs et bagages à la charge de l'employeur (exceptions listées, répartition au prorata en cas de rupture fautive) ; classe de passage et poids des bagages selon la convention ; attente du transport indemnisée au salaire. | Table `transfers(employee_id, from_site, to_site, notified_on, accepted_on, effective_on, urgency_reason, housing_provided, transport_costs)`. `transfer_min_notice_days = 15` (**Code**). `housing_deduction_cap` (**à fournir**, art. 260). | **[B]** `effective_on < notified_on/accepted_on + 15 jours` sans motif d'urgence. **[B]** retenue de logement > plafond. **[A]** mutation (site de Matam) sans prise en charge du transport renseignée. État : ➕. |
| MOB-03 | 265, 267 | Après cessation de service, le travailleur peut exiger les **titres de transport** dans les **2 ans** ; attestation du **décompte exact** de ses droits remise à la rupture. **Rapatriement du corps** à la charge de l'employeur en cas de décès d'un travailleur déplacé ou muté (demande écrite des héritiers). | Attestation `transport_entitlement_statement` produite à la sortie d'un salarié muté. | **[A]** sortie d'un salarié muté sans attestation. État : ➕. |
| MOB-04 | 287-291, 293 | **Sous-traitance** : l'entreprise principale exige l'**attestation de régularité sociale** (inspection) **avant le contrat et tous les 6 mois** ; elle est **substituée** au sous-traitant défaillant pour salaires, congés, cotisations et SST (chantiers hors locaux : salaires, congés, cotisations) ; **action directe** des travailleurs et des institutions de prévoyance ; chaîne de sous-traitance : chaque niveau. **Marchandage interdit** (prestation sur l'activité **principale et permanente**, prestataire sans savoir-faire propre ou n'étant pas l'employeur effectif). **Travail temporaire** : missions précises et temporaires seulement, sinon le travailleur est réputé lié par CDI à l'entreprise utilisatrice. | Table `subcontractor_compliance(supplier_id, certificate_ref, issued_on, expires_on = issued_on + 6 mois)`. | **[B]** nouveau contrat de sous-traitance ou de prestation sans attestation valide. **[A]** J-30 avant l'expiration de 6 mois. **[A]** prestataire affecté à l'activité principale et permanente. État : ➕ (la table `PRESTATION` actuelle ne traite que la BRS des prestataires individuels). |
| MOB-05 | 284-286 | **Travail dissimulé** : omettre la déclaration d'embauche (art. 363), les déclarations de salaires ou de cotisations auprès des institutions de prévoyance ; recourir sciemment à un travailleur dissimulé est aussi interdit. | Rapprochement mensuel effectif payé / déclaré. | **[B]** salarié payé sans `hire_declaration_ref`. **[A]** écart entre masse salariale validée et déclaration IPRES/CSS. État : ➕. |
| MOB-06 | 295-300 | **Non-concurrence** : le travailleur consacre son activité à l'entreprise sauf dérogation ; clause d'**interdiction post-contractuelle** nulle, sauf rupture imputable au travailleur et alors **≤ 6 mois**, **≤ 30 km**, avec **compensation financière convenue dès la conclusion**. **Cumul d'emplois** interdit pendant le congé payé (296) et pour un salarié à temps plein dans la même profession (297) ; durée maximale de travail à respecter tous employeurs confondus (298) ; dérogations art. 300. | Champs `non_compete_months ≤ 6`, `non_compete_radius_km ≤ 30`, `non_compete_compensation`. | **[B]** clause > 6 mois, > 30 km ou sans compensation. **[A]** déclaration de second emploi d'un salarié à temps plein. État : ➕. |

### 2.J Obligations déclaratives et registres de l'employeur (arts. 316-318, 362-365, 93-103)

| ID | Art. | Obligation | Échéance (Code) | Donnée à produire dans SOMA-RH | Garde-fou |
|---|---|---|---|---|---|
| OBL-01 | 363 | **Déclaration d'embauche** à l'inspection du travail ; **déclaration de départ** avec date de départ ; contenu et modalités : arrêté. Étranger : à la DGTSS avec la demande de visa. Sénégalais à l'étranger : déclaration préalable + autorisation (7 jours francs, silence = autorisation, art. 187). | Délai : **arrêté (à fournir)** | `hire_declaration_ref/date`, `departure_declaration_ref/date` | **[B]** paie d'un nouveau salarié sans déclaration d'embauche renseignée. |
| OBL-02 | 93, 99, 102, 103, 176, 183 | **Dépôt à l'inspection avant tout début d'exécution** : essai, CDD, renouvellement, avenant de prolongation, apprentissage, stage ; convention de rupture amiable et plan social (4 exemplaires). | Avant exécution | `deposit_ref/date` par contrat ou avenant | **[B]** voir CTR-02, CTR-04, CTR-11, RUP-06, RUP-07. |
| OBL-03 | 365 | **Registre du personnel** tenu à jour au lieu d'exploitation : identification, effectif, conditions d'emploi et rémunération ; **production immédiate** à l'inspecteur ; forme et contenu : arrêté ; exemptions possibles. Une mention mensongère sur la durée ou les conditions de travail est un **délit** (art. 452). | Permanent | Vue `v_registre_personnel` (exportable PDF/CSV, archivage daté) | **[A]** registre non régénéré après une entrée ou une sortie. |
| OBL-04 | 364 | **Document annuel sur la situation de la main-d'œuvre et la situation sociale** de l'établissement. | Annuel, modalités par décret (**à fournir**) | Vue annuelle effectifs, mouvements, rémunérations, accidents, formation (réutilise le pilotage RH, lot 6) | **[A]** non produit à la date fixée par décret. |
| OBL-05 | 362 | **Déclaration préalable** d'ouverture d'un établissement ou chantier ; mêmes règles pour fermeture, transfert, changement d'activité ou d'adresse. | Avant ouverture | Table `establishments(site, declared_on, ref)` (site de Matam, chantiers) | **[A]** site actif sans déclaration. |
| OBL-06 | 316, 335 | **Accident du travail / maladie professionnelle** : avis à l'inspecteur selon le Code de la sécurité sociale ; **immédiat par tout moyen d'urgence si mortel** ; entreprise utilisatrice, extérieure ou travailleur indépendant : l'entreprise où s'exécute l'intervention avise. | Selon CSS (**à confirmer**) | Table `work_accidents(employee_id, date, severity, declared_on, ref)` | **[A]** accident sans déclaration. |
| OBL-07 | 317, 318, 339-341 | **Registres SST**, **rapport annuel** transmis à l'inspecteur, **système de management SST**, **comité de sécurité et santé** et **service de santé au travail** (seuils et organisation : décrets). | Annuel (rapport) | Registres et rapport dans le module HSQE (hors périmètre SOMA-RH, décision D12) ; SOMA-RH conserve les références | **[A]** rapport annuel absent au 31 janvier de l'année suivante (**échéance à confirmer**). |
| OBL-08 | 60, 63 | **Délégués du personnel** : seuil d'institution, nombre, élections et crédit d'heures fixés par **décret** (**à fournir**). | Mandat 3 ans | `employee_representatives` (RUP-16) | **[A]** effectif au-dessus du seuil sans délégués élus. |
| OBL-09 | 373-376 | L'inspecteur peut prononcer des **amendes administratives** (nature et montants : **décret**, à fournir) ; PV d'infraction faisant foi ; violation grave de données personnelles : information de l'autorité de protection des données. | — | Journal des contrôles et mises en demeure (art. 367) | **[A]** mise en demeure sans réponse documentée. |

### 2.K Sanctions pénales, pour pondérer les alertes (arts. 448-458)

| Art. | Infraction (résumé) | Amende (F CFA) | Emprisonnement |
|---|---|---|---|
| 450 | Amende encourue **autant de fois qu'il y a d'infractions** (notamment autant de travailleurs concernés). | cumul | — |
| 451 | Violation d'un ordre de réquisition ; interruption de travail par un travailleur d'un emploi listé | 100 000 à 1 000 000 | — |
| 452 | Fraude contractuelle ; **mentions mensongères au registre du personnel** ; cumul irrégulier d'emplois (art. 296-298) ; **intermédiaire** dans le paiement des salaires ; **détournement des prélèvements sur salaires** ; paiement exigé pour un placement | 500 000 à 5 000 000 | 3 mois à 1 an (ou l'une des deux peines) |
| 454 | Harcèlement ou violence morale ; représailles contre un travailleur qui refuse ou témoigne | 200 000 à 5 000 000 | 1 mois à 1 an |
| 455 | Atteinte à la liberté syndicale ou à la désignation des délégués et membres du comité SST ; récidive sous 3 ans : emprisonnement toujours prononcé | 500 000 à 10 000 000 | 1 mois à 1 an |
| 456 | Discrimination ; infractions sur la grossesse ; enfant < 16 ans sans dérogation ; jeune travailleur de nuit ; jeune ou handicapé maintenu dans un emploi trop lourd ; travail forcé ; pires formes de travail des enfants | 500 000 à 10 000 000 | 3 mois à 1 an |
| 457 | Entrave à l'inspection du travail ; récidive : 1 000 000 à 20 000 000 et 6 mois à 1 an ; double récidive : emprisonnement prononcé | 1 000 000 à 10 000 000 | 3 mois à 1 an |
| 453, 458 | Harcèlement ou violence physique ou sexuelle ; outrages à l'inspecteur | Code pénal | Code pénal |

> **Usage dans SOMA-RH** : chaque garde-fou [B] porte `penalty_ref` (article et fourchette) pour afficher l'exposition ; l'exposition cumulée s'obtient en multipliant l'amende maximale par le nombre de salariés concernés (art. 450).

---

## 3. Modèle de données consolidé (ajouts à la base SOMA-RH)

Convention : `M` = obligatoire, `O` = optionnel, `C` = conditionnel. Les colonnes sont à ajouter par migrations `db/migrations/AAAAMMJJHHMMSS_nom.sql`, jamais en modifiant une migration existante.

### 3.1 Colonnes à ajouter aux tables existantes

| Table | Colonne | Type · format | Oblig. | Règle liée |
|---|---|---|---|---|
| `employees` | `date_of_birth` | date | M (≥ 16 ans, ≥ 18 ans pour travaux interdits) | CNG-11, RUP-11 |
| `employees` | `nationality`, `work_permit_ref` | text | C (étranger) | OBL-01 |
| `employees` | `hire_declaration_ref`, `hire_declaration_date` | text, date | M avant la 1re paie | OBL-01 |
| `employees` | `category_code`, `agreement_code` | text (réf. `agreements`) | M | RUP-02, RUP-08, RUP-14 |
| `employees` | `marital_status` | enum | M | RUP-04 (rang) |
| `employees` | `is_protected`, `protected_until` | bool, date | M | RUP-16 |
| `employees` | `non_compete_months`, `non_compete_radius_km`, `non_compete_compensation` | int, int, numeric | O | MOB-06 |
| `employees` | `exit_reason` (liste étendue §3.3) | enum | C à la sortie | RUP-01 à RUP-13 |
| `employees` | `notice_notified_on`, `notice_months`, `notice_waived` | date, numeric, bool | C | RUP-02 |
| `employees` | `certificate_delivered_on`, `certificate_delivery_proof` | date, text | C | RUP-14 |
| `employees` | `departure_declaration_ref/date` | text, date | C | OBL-01 |
| `contracts` (ou équivalent) | `contract_type`, `cdd_motif`, `start_date`, `end_date`, `renewal_count`, `cumulative_months`, `deposit_ref`, `deposit_date`, `precarity_due`, `refused_cdi_offer` | divers | M selon type | CTR-02 à CTR-11, RUP-10 |
| `payroll_settings` | tous les paramètres du §4 | numeric / int / bool | M | — |
| `leave_types` | `MATERNITE.annual_cap_days = 126` ; `max_extension_days = 21` ; plafond annuel de `CONGE_ANNUEL` levé | int | M | art. 277, 249 |
| `payslips` | `delivered_on`, `delivery_proof_document_id`, `payment_proof_type`, `payment_proof_document_id` | date, uuid, enum, uuid | M à la clôture | art. 205 |
| `deductions` (retenues sur net) | `deduction_type`, `authorization_id`, `is_garnishment` | enum, uuid, bool | M | RET-01 |

### 3.2 Nouvelles tables

| Table | Rôle | Colonnes clés |
|---|---|---|
| `dependants` | Enfants et conjoint (allocations, congés, rang de licenciement) | `employee_id`, `relation`, `birth_date` (M), `is_dependent`, `school_certificate_until` |
| `agreements` | Convention collective applicable | `code`, `label`, `valid_from`, `valid_to`, `source_document` |
| `notice_scales` | Barème du préavis | `agreement_code`, `category`, `seniority_min_months`, `notice_months`, `source` |
| `severance_scales` | Indemnités de licenciement, retraite, décès | `agreement_code`, `kind`, `from_years`, `to_years`, `rate`, `source` |
| `overtime_rates` | Taux des heures supplémentaires et assimilées | `agreement_code`, `band`, `multiplier`, `source` (art. 244) |
| `leave_policies` | Règles de congé par convention | `agreement_code`, `seniority_bonus_rule`, `source` (art. 249) |
| `garnishment_scale` | Quotité cessible par tranche | `from_amount`, `to_amount`, `rate`, `source` (art. 216) |
| `deduction_types` / `deduction_authorizations` | Retenues légales et autorisations | voir RET-01 |
| `payment_proofs` | Pièces probantes de paiement | `payslip_id`, `mode`, `proof_type`, `document_id`, `received_on` |
| `payslip_deliveries` | Remise du bulletin | `payslip_id`, `delivered_on`, `method` |
| `contract_amendments` | Avenants et changements substantiels | `contract_id`, `type`, `proposed_on`, `accepted_on`, `effective_on` |
| `contract_suspensions` | Suspensions (maladie, maternité, grève, chômage technique) | `employee_id`, `cause`, `from`, `to`, `paid_by`, `reference` |
| `technical_layoffs` | Chômage technique | `employee_id`, `from`, `to`, `allowance_rate ≥ 50 %`, `inspector_ref` |
| `disciplinary_cases` | Procédure disciplinaire | voir DIS-02 |
| `employee_representatives` | Délégués et candidats | voir RUP-16 |
| `transfers` | Mutations et déplacements | voir MOB-02 |
| `layoff_procedures` | Licenciement économique | voir RUP-04 |
| `medical_inaptitude_cases` | Inaptitude | voir RUP-13 |
| `heirs` | Héritiers en cas de décès | voir RUP-12 |
| `subcontractor_compliance` | Attestation de régularité sociale | voir MOB-04 |
| `internal_rules` | Règlement intérieur | voir DIS-01 |
| `work_accidents` | Accidents du travail | voir OBL-06 |
| `compliance_deadlines` | Échéancier générique (rappels) | `rule_id`, `employee_id`, `due_on`, `status`, `severity` |
| `compliance_findings` | Résultats des garde-fous | `rule_id`, `severity`, `entity`, `entity_id`, `detected_on`, `resolved_on`, `waiver_by`, `waiver_reason` |
| `legal_sources` | Traçabilité des valeurs | `param_key`, `source_type ∈ {CODE, HERITEE, A_FOURNIR}`, `article`, `document`, `valid_from` |

### 3.3 Listes de valeurs à étendre

- `employment_type` : `CDI`, `CDD_REMPLACEMENT`, `CDD_ACCROISSEMENT`, `CDD_SAISONNIER`, `CDD_OBJET_DEFINI`, `ESSAI`, `APPRENTISSAGE`, `STAGE`, `TEMPORAIRE`, `PRESTATION`.
- `exit_reason` : `DEMISSION`, `DEMISSION_SANS_PREAVIS`, `LICENCIEMENT_PERSONNEL`, `LICENCIEMENT_FAUTE_LOURDE`, `LICENCIEMENT_ECONOMIQUE`, `CESSATION_ACTIVITE`, `PLAN_SOCIAL`, `RUPTURE_AMIABLE`, `RETRAITE`, `DECES`, `INAPTITUDE_PRO`, `INAPTITUDE_NON_PRO`, `FIN_CDD`, `RUPTURE_ANTICIPEE_CDD`, `FIN_ESSAI`, `FORCE_MAJEURE`.
- `payment_proof_type` : `EMARGEMENT`, `RECU_SIGNE`, `CHEQUE_ENCAISSE_AVIS_DEBIT`, `ATTESTATION_BANCAIRE`, `ATTESTATION_MONNAIE_ELECTRONIQUE`.

---

## 4. Valeurs par défaut au premier démarrage (seed)

Légende de la source : **Code** = fixé par la loi 2026-18 ; **héritée** = valeur actuelle de SOMA-RH, non confirmée par le nouveau Code ; **à fournir** = aucun défaut raisonnable, la fonction concernée reste désactivée et signalée.

| Clé de paramètre | Valeur | Source | Article |
|---|---|---|---|
| `legal_weekly_hours` | 40 | Code | 241 |
| `hourly_rate_divisor` | 40 × 52 ÷ 12 | Code | 241 |
| `night_work_start` / `night_work_end` | 22:00 / 05:00 | Code | 245 |
| `weekly_rest_hours` | 24 | Code | 246 |
| `leave_days_per_month` | 2 (jours ouvrables) | Code | 249 |
| `leave_min_days_per_year` | 6 (obligatoires) | Code | 248-254 |
| `leave_provision_rate` | 1/12 des sommes perçues | Code | 254 |
| `maternity_total_weeks` | 18 (126 jours) | Code | 277 |
| `maternity_post_birth_weeks` | 12 | Code | 277 |
| `maternity_extension_weeks` | 3 | Code | 277 |
| `breastfeeding_hours_per_day` / `_months` | 1 / 20 | Code | 280 |
| `trial_max_months` | 6 (renouvellement compris) | Code | 94 |
| `cdd_max_months` / `cdd_renewals` / `cdd_cumulative_max_months` | 24 / 1 / 48 | Code | 100 |
| `precarity_rate` | 0,07 | Code | 167 |
| `special_indemnity_months` | 1 | Code | 132, 156, 162 |
| `rehire_priority_months` | 24 | Code | 157 |
| `technical_layoff_allowance_min_rate` | 0,50 | Code | 123 |
| `technical_layoff_max_months` | 12 | Code | 125 |
| `salary_payment_deadline_days` | 8 après fin du mois | Code | 199 |
| `payroll_retention_years` | 5 | Code | 212 |
| `disciplinary_prescription_months` | 2 | Code | 234 |
| `transfer_min_notice_days` | 15 | Code | 259 |
| `trip_threshold_months` | 6 | Code | 3, 258 |
| `non_compete_max_months` / `_max_km` | 6 / 30 | Code | 295 |
| `subcontractor_certificate_months` | 6 | Code | 287 |
| `participation_max_presence_months` / `_pay_deadline_months` | 6 / 9 | Code | 225-229 |
| `advance_cap_multiple` | 6 × quotité cessible | Code | 215 |
| `severance_scale` (licenciement) | 25 % / 30 % / 40 % | héritée | 151 (renvoi) |
| `severance_scale` (retraite) | 25 % / 30 % / 45 % / 50 % | héritée | 135 (renvoi) |
| `overtime_multipliers` | valeurs actuelles du moteur | héritée | 244 (renvoi) |
| `smig_hourly` / `smig_monthly` | — | à fournir | 195 |
| `notice_scales` | — | à fournir | 144 |
| `garnishment_scale` | — | à fournir | 216 → art. 381 CPC |
| `retirement_age` | — | à fournir | 134 |
| `trip_allowance_rates` | — | à fournir | 258 |
| `delegate_threshold` / `delegate_hours_per_month` | — | à fournir | 60, 63 |
| `seniority_leave_bonus` | — | à fournir | 249 |
| `hire_declaration_deadline_days` | — | à fournir | 363 |
| `legal_interest_rate` | — | à fournir | 216 |

> Règle de sûreté : une règle dont un paramètre est « à fournir » ne bloque pas la paie ; elle passe en alerte **[A] « paramètre manquant »** et s'affiche dans le tableau de bord de conformité jusqu'à saisie.

---

## 5. Conception des garde-fous

### 5.1 Niveaux et comportement

| Niveau | Effet | Dérogation |
|---|---|---|
| **[B] bloquant** | Empêche la validation de la paie, l'enregistrement du contrat ou de la sortie | Impossible sans correction ; seule une dérogation tracée du rôle `legal_admin` (motif écrit, historisée dans `compliance_findings`) lève le blocage |
| **[A] alerte** | Affiche l'avertissement, n'empêche rien, doit être acquittée avant clôture mensuelle | Acquittement par l'utilisateur avec commentaire |

### 5.2 Points de déclenchement

1. **Saisie** (formulaires React) : contrôle immédiat des formats, plafonds et dates (âge ≥ 16, essai ≤ 6 mois, CDD ≤ 24 mois).
2. **Enregistrement** (contraintes `CHECK` et triggers PostgreSQL) : garde-fous [B] structurels, pour qu'ils tiennent même hors interface.
3. **Calcul** (`compute_salary_slip`) : contrôles sur le net, quotité cessible, avances, indemnités, éligibilité (12 mois), droit au congé.
4. **Clôture mensuelle** : fonction `run_compliance_checks(period)` qui alimente `compliance_findings`.
5. **Échéancier quotidien** : tâche planifiée qui génère les alertes à échéance (J-30 de fin de CDD, 6 mois de sous-traitance, 8 jours de paiement, 2 mois de prescription disciplinaire).

### 5.3 Tests

- Un jeu de cas par règle dans `scripts/verify-payroll.ps1` (cas conforme, cas limite, cas bloquant).
- Statut du registre légal : une règle ne passe à « conforme » qu'avec un texte officiel cité (article ou décret), selon la règle déjà en vigueur dans `registre-legal.mdx`.
- Chaque valeur du §4 porte son entrée `legal_sources` : un changement de décret se traduit par une nouvelle ligne avec `valid_from`, sans modifier le code.

---

## 6. Correspondance avec le registre légal (`registre-legal.mdx`)

| RL | Sujet | Article du Code à citer | Action |
|---|---|---|---|
| RL-011 | Durée légale et heures supplémentaires | 241 (durée), 244 (taux : renvoi) | Source officielle trouvée pour la durée ; taux restent « à fournir » |
| RL-013 | Congé annuel | 249, 254 | Source officielle trouvée ; plafond `24` à lever |
| RL-012, RL-014, RL-017, RL-019 | Autres règles du Code du travail déjà inscrites | à rattacher article par article | Re-sourcer sur les articles de ce document ; ne passer « conforme » que si le chiffre est dans le Code |
| RL-001 à RL-009, RL-015, RL-016 | IPRES, CSS, IR, TRIMF, CFCE | hors Code du travail | Inchangés (Code de la sécurité sociale, CGI) |
| Nouveaux (RL-020 et suivants) | Maternité 126 jours, assiette art. 197, indemnité spéciale, retenues, preuve de paiement, CDD | 277, 197, 132/156/162, 214-217, 205, 97-103/167 | À créer au statut « à confirmer » puis « conforme » après revue juridique |

---

## 7. Backlog priorisé

### P0 : risque juridique ou erreur de paie

| Ticket | Intitulé | Règles | Effort |
|---|---|---|---|
| C26-01 | Passer la maternité à 126 jours (147 avec extension) et propager aux soldes et à la paie | art. 277 | S |
| C26-02 | Assiette art. 197 : moyenne 12 mois de tous les éléments variables (hors frais) pour congé, préavis, licenciement | art. 197 | M |
| C26-03 | Étendre la liste des motifs de sortie (16 valeurs, §3.3) et brancher chaque motif sur ses indemnités | RUP-01 à RUP-13 | L |
| C26-04 | Indemnité spéciale de 1 mois (économique, cessation, plan social) | RUP-04, 05, 07 | S |
| C26-05 | Éligibilité de l'indemnité de licenciement (≥ 12 mois, hors faute lourde) | RUP-08 | S |
| C26-06 | Preuve du paiement du salaire par mode (pièce obligatoire) | art. 205 | M |
| C26-07 | Retenues sur net : types légaux, autorisation écrite, plafond des avances à 6 × quotité cessible | RET-01 à RET-05 | M |
| C26-08 | Contrôles CDD : durée, renouvellement unique, 4 ans cumulés, motif, dépôt à l'inspection, assiette des 7 % | CTR, RUP-10 | M |
| C26-09 | Déclaration d'embauche obligatoire avant la 1re paie | OBL-01 | S |

### P1 : conformité structurelle

| Ticket | Intitulé | Effort |
|---|---|---|
| C26-10 | Tables `agreements`, `notice_scales`, `severance_scales`, `overtime_rates` : barèmes paramétrables par convention | M |
| C26-11 | Gestion du préavis (durée, date de remise de lettre, indemnité compensatrice, doublement pendant le congé) | M |
| C26-12 | Table `dependants` avec dates de naissance ; congés des mères, rang du licenciement économique | M |
| C26-13 | Certificat de travail conforme à l'art. 140 (suppression de la référence « art. L.55 », catégorie de convention, emplois successifs) | S |
| C26-14 | Procédure disciplinaire (`disciplinary_cases`) avec délais et prescription de 2 mois | M |
| C26-15 | Salariés protégés (`employee_representatives`) et blocage de sortie sans autorisation | S |
| C26-16 | Mutations et déplacements (préavis 15 jours, transport, logement) | M |
| C26-17 | Tableau de bord de conformité (`compliance_findings`, `compliance_deadlines`) | L |

### P2 : couverture complète

| Ticket | Intitulé | Effort |
|---|---|---|
| C26-18 | Participation, intéressement, épargne salariale | M |
| C26-19 | Sous-traitance : attestation de régularité tous les 6 mois | S |
| C26-20 | Registre du personnel, document annuel de main-d'œuvre, accidents du travail | M |
| C26-21 | Procédure de licenciement économique et plan social | L |
| C26-22 | Inaptitude, héritiers, rapatriement | M |
| C26-23 | Non-concurrence, cumul d'emplois | S |

---

## 8. Questions à trancher et documents à fournir

### 8.1 Questions pour le juriste ou la direction

1. Date d'entrée en vigueur : le texte ne donne que la promulgation du 3 septembre 2026. Les règles nouvelles (maternité, indemnité spéciale) s'appliquent-elles dès le 1er octobre 2026 ou à la date de publication ?
2. Quelle convention collective s'applique à SOMA (interprofessionnelle, branche ou d'entreprise) ?
3. Les barèmes hérités de licenciement et de retraite sont-ils ceux de la convention ? Il faut les confirmer par écrit.
4. Faut-il appliquer la majoration de la maternité (3 semaines) par défaut ou seulement sur certificat médical ?
5. Politique sur les avances (Korité, caisse) : quelles retenues sont autorisées par écrit aujourd'hui ?

### 8.2 Textes à fournir pour fermer les paramètres « à fournir »

- Décret sur la durée du préavis ou barème de la convention (art. 144).
- Décret fixant le SMIG et le SMAG, et arrêtés de classification (art. 195).
- Décret ou convention sur les taux des heures supplémentaires et le contingent (art. 244).
- Article 381 du Code de procédure civile : barème de la quotité cessible (art. 216).
- Décret sur l'âge de la retraite et les emplois pénibles (art. 134).
- Décrets sur les délégués du personnel, le comité de sécurité et santé, le service de santé au travail (art. 60, 340, 341).
- Arrêtés sur les mentions du bulletin de paie, du registre du personnel et de la déclaration d'embauche (art. 202, 203, 363, 365).
- Barème des indemnités de déplacement et plafond de remboursement du logement (art. 258, 260).
- Décret fixant les montants des amendes administratives (art. 373).

---

## 9. Index des articles cités

Définitions et principes : 3, 4, 8-22. Contrat de travail : 93-103, 114-125. Cessation du contrat : 126-175. Rémunération : 195-217. Participation et avantages : 218-232. Discipline : 232-240. Durée et repos : 241-247. Congés : 248-257. Mobilité et logement : 258-267. Maternité et protection : 277-283. Sous-traitance et emploi : 284-300. Santé et sécurité : 316-318, 335-341. Administration du travail : 362-377. Sanctions : 448-458. Dispositions finales : 459-462.


---

## 10. Mise à jour du 5 novembre 2026 : valeurs sourcées par les textes d'application fournis

> **Cette section remplace la version précédente du §10** (qui s'appuyait sur la CCNI de 1982 et sur des résumés de presse). Les textes fournis le 5/11/2026 ont été lus : décret SMIG du 16 janvier 2019 (JO du 1er juin 2019, p. 966), Code de procédure civile (art. 381), CCNI récente (50 p., lue par OCR), CGI janvier 2025. Détail et extraits dans `docs/sources-legales/EXTRAITS_TEXTES_APPLICATION.md`.
> Les 8 liens du document de départ n'ont pas pu être ouverts depuis l'environnement de travail ; seules les copies fournies en pièces jointes font foi ici.

### 10.1 Paramètres désormais sourcés

| Clé | Valeur | Texte · article | Statut |
|---|---|---|---|
| `smig_hourly` | 302,890 F (1/6/2018) ; 317,313 F (1/1/2019) ; **333,808 F à compter du 1/12/2019** | Décret du 16 janv. 2019, art. 1 (40 h/sem.) | Sourcé. **Aucune revalorisation postérieure n'est dans les pièces** (une source secondaire en cite une en 2023) : à confirmer |
| `smig_monthly` (calcul) | 333,808 × 40 × 52 ÷ 12 = **57 860 F** | Calcul | Le résumé fourni (333,807 F/h ; ~58 900 F/mois) est inexact |
| `smag_hourly` | **213,392 F** (depuis le 1/1/2018) | Décret, art. 2 | Sourcé |
| Éléments du décompte SMIG | Avantages en nature ayant le caractère de complément de salaire inclus ; majorations d'heures supplémentaires et remboursements de frais **exclus** | Décret, art. 3 | Règle de contrôle du minimum légal |
| Retenue de nourriture (ration) | Max. 2 × taux horaire agricole par jour ; 1 × pour le seul repas | Décret, art. 4 | Plafond de retenue |
| `overtime_multipliers` | **+15 %** pour les 8 premières heures supplémentaires ; **+40 %** au-delà ; **+60 %** heures de nuit ; **+60 %** jour de repos ou férié (jour) ; **+100 %** jour de repos ou férié (nuit) | CCNI art. 49 | Sourcé (la durée légale reste renvoyée à la loi : CCNI art. 24) |
| `notice_scales` | Ouvriers et employés **1 mois** ; agents de maîtrise et assimilés **2 mois** ; cadres et assimilés **3 mois** | CCNI art. 75 | Sourcé |
| Préavis : règles associées | 2 jours/semaine d'absence pour chercher un emploi (globalisables) ; indemnité compensatrice = rémunération et avantages du préavis restant ; **doublée** si notification < 15 jours ouvrables avant un départ en congé ou rupture pendant le congé ; notification par écrit, la preuve incombe à celui qui rompt | CCNI art. 74-77 | Sourcé |
| `severance_scale` licenciement | **25 %** (5 premières années), **30 %** (6e à 10e), **40 %** (au-delà), fractions d'année comptées ; base = salaire global mensuel moyen des 12 derniers mois, hors remboursement de frais ; due dès 12 mois de service ; non due en cas de faute lourde ; cumul après réembauches sous déduction des sommes versées | CCNI art. 80 | Sourcé. **Confirme les coefficients du moteur** |
| `severance_scale` retraite | **25 %** / **30 %** / **45 %** (11e à 20e année) / **50 %** (au-delà) | CCNI art. 84 | Sourcé. **Confirme les coefficients du moteur** ; l'écart signalé dans la version précédente (CCNI 1982 art. 31) est **annulé** |
| Décès | Salaires, allocation de congé et indemnités acquises aux héritiers ; si ≥ 1 an d'ancienneté, indemnité **égale à l'indemnité de licenciement** ; participation aux frais funéraires **≥ 1 mois de salaire de la catégorie** aux ayants droit en ligne directe ; rapatriement du corps si déplacé | CCNI art. 83 | Sourcé. **Frais funéraires absents du moteur** |
| `seniority_leave_bonus` | +1 jour ouvrable après 10 ans ; +2 après 15 ans ; +3 après 20 ans ; +7 après 25 ans | CCNI art. 70 | Sourcé |
| Congé supplémentaire des mères | 2 jours par enfant à charge si < 21 ans à la fin de la période de référence ; 2 jours par enfant mineur à charge à partir du 4e si > 21 ans | CCNI art. 70 | Sourcé (exige les dates de naissance des enfants) |
| Congé : règles associées | Congé 2 jours ouvrables par mois ; allocation = 1/12 des sommes perçues sur la période de référence ; départ avisé 15 jours à l'avance ; mention des dates sur le bulletin ; absences exceptionnelles non déductibles dans la limite de 15 jours/an | CCNI art. 70-72, 27 | Sourcé |
| `seniority_bonus` (prime d'ancienneté) | **2 %** du salaire minimum de la catégorie après 2 ans, **+1 % par année** supplémentaire, jusqu'à l'âge de la retraite | CCNI art. 52 | Sourcé. **À comparer à la règle du moteur** |
| Indemnité de panier | **3 × le SMIG** (horaire) pour ≥ 6 h de nuit ; aussi après 10 h ininterrompues ou 3 h au-delà de l'horaire | CCNI art. 53 | Sourcé (≈ 1 001 F avec le SMIG de 2019) |
| `trip_allowance_rates` | Catégories 1 à hors catégorie : **6 ×** (1 repas), **8 ×** (2 repas), **10 ×** (2 repas + couchage) le taux horaire de base ; maîtrise et techniciens : **5 ×**, 8 ×, 10 × ; cadres : frais réels ou forfait d'accord parties | CCNI art. 57 | Sourcé |
| Mutation | Au-delà de 6 mois : famille aux frais de l'employeur, logement, ou indemnité compensatrice convenue ; congé de détente (2 jours tous les 2 mois entre 75 et 200 km, 3 jours tous les 3 mois au-delà de 200 km) ; délais de route 1 ou 2 jours | CCNI art. 57 | Sourcé |
| Transport et bagages | 2e classe route/rail pour ouvriers, employés, maîtrise ; 1re classe pour cadres ; 200 kg (ménage) et 100 kg par enfant mineur | CCNI art. 58 | Sourcé |
| Logement fourni | Retenue autorisée selon la réglementation ; évacuation à l'expiration du préavis (≥ 1 mois), 8 jours si préavis non respecté, ≤ 1 mois si licenciement sans préavis | CCNI art. 59-61 | Sourcé. **Plafond de la retenue : toujours à fournir** (art. 260 du Code) |
| `delegate_threshold` | Délégués du personnel obligatoires dans tout établissement de **plus de 10 travailleurs** (regroupement des établissements dans un rayon de 10 km) | CCNI art. 14 | Sourcé |
| `delegate_hours_per_month` | **20 heures par mois**, imputées sur l'horaire | CCNI art. 14 | Sourcé |
| Maladie (suspension) | Pas de rupture avant **6 mois** (8 mois pour 7 à 15 ans d'ancienneté et 10 mois au-delà en cas de traitement long) ; formalités : avis sous 6 jours, certificat sous 1 semaine | CCNI art. 86 | Sourcé |
| Indemnité de maladie | < 1 an : plein salaire 1 mois + demi-salaire 3 mois ; 1 à 5 ans : 1 mois + 4 mois ; > 5 ans : 2 mois + 5 mois ; plafond par année civile | CCNI art. 87 | Sourcé. **À comparer à la règle du moteur** |
| Accident du travail | Complément pour garantir l'ancien salaire pendant la période de l'art. 87, déduction faite des indemnités journalières | CCNI art. 88 | Sourcé |
| Certificat de travail | Nom et adresse de l'employeur, dates d'entrée et de sortie, **emplois successifs avec catégories professionnelles et périodes** ; « libre de tout engagement » sur demande ; remise électronique possible avec preuve de réception | CCNI art. 85 | Sourcé |
| Mentions du bulletin | Prénom, nom, **catégorie professionnelle**, taux horaire ou mensuel, heures normales et supplémentaires, raison sociale, détail des retenues, et autres mentions légales | CCNI art. 48 | Sourcé (minimum conventionnel ; l'arrêté du Code reste à fournir) |
| Avantages en nature (impôt) | Logement par pièce principale : **33 500 F** (Dakar), **20 000 F** (chefs-lieux de régions), **13 500 F** (autres) ; gardien/jardinier 61 700 ; cuisinier 92 500 ; autres gens de maison 35 600 ; eau 10 500 ; électricité 30 200 ; téléphone 67 000 ; nourriture valeur réelle ; véhicule ≤ 11 CV 26 000, > 11 CV 77 500. Les retenues effectuées par l'employeur se déduisent du forfait ; une indemnité en argent est imposée intégralement | CGI art. 166 et arrêté n° 012914 du 31 juillet 2013 | Sourcé (base de l'IR, **pas** le plafond de retenue de l'art. 260) |

### 10.2 Quotité cessible : le barème du document de départ était faux

Le résumé fourni (« ≤ 20 k : 1/10 ; 20-40 k : 1/5 ; 40-80 k : 1/4 ; 80-150 k : 1/3 ; > 150 k : 1/2 ») **ne correspond pas** au texte. **CPC, art. 381** :

| Tranche mensuelle de l'assiette | Part saisissable |
|---|---|
| jusqu'à 20 000 F | 10 % |
| de 20 001 à 30 000 F | 20 % |
| de 30 001 à 100 000 F | 30 % |
| de 100 001 à 200 000 F | 40 % |
| au-delà de 200 000 F | 100 % |

- **Tranches progressives** : le taux s'applique à la part de l'assiette comprise dans chaque tranche (lecture usuelle ; à faire confirmer par le juriste).
- **Portion supplémentaire** (frais d'hôpital ou de clinique ; prêts pour logement principal), si la portion ci-dessus est insuffisante : mêmes taux jusqu'à 200 000 F, sans le palier de 100 %.
- **Assiette** : salaire brut global avec tous les accessoires, **déduction faite** des prélèvements légaux obligatoires retenus à la source, des indemnités représentatives de frais, des prestations et majorations pour charges de famille, et des indemnités déclarées insaisissables.
- **Plafond global** : le total des prélèvements ou retenues, **cessions volontaires comprises**, ne peut en aucun cas dépasser **les deux tiers** de l'assiette, même pour dettes alimentaires.
- Le titulaire d'un compte peut retirer chaque mois la portion insaisissable malgré l'opposition.

Exemples calculés : assiette 50 000 F → 10 000 F saisissables (plafond 2/3 : 33 333) ; 150 000 F → 45 000 F (plafond 100 000) ; 300 000 F → 165 000 F (plafond 200 000).

Impact : table `garnishment_scale` à alimenter avec ces 5 lignes (kind `PRINCIPAL`) et 4 lignes (kind `SUPPLEMENTAIRE`), plus le paramètre `deduction_global_cap = 2/3`. Le garde-fou RET-03/RET-04 devient opérationnel.

### 10.3 Ce qui reste à fournir

| Paramètre | Pourquoi |
|---|---|
| Âge normal de la retraite | La CCNI (art. 84) renvoie au régime d'affiliation (IPRES) ; texte à fournir |
| Plafond de la retenue de logement (art. 260 du Code) | Aucun montant dans les pièces |
| Arrêtés sur le bulletin, le registre du personnel et la déclaration d'embauche (art. 202, 203, 363, 365) | Seul le minimum de la CCNI art. 48 est connu |
| Durée légale et contingent d'heures supplémentaires | La CCNI renvoie à la loi ; le Code de 2026 fixe 40 h (art. 241) ; contingent à fournir |
| Décret fixant les amendes administratives (art. 373) | Le résumé fourni cite l'ancien Code (abrogé) |
| Décrets sur le comité de santé et sécurité et le service de santé (art. 340, 341) | La CCNI (art. 94) traite du CHST sans fixer les seuils légaux |
| Revalorisation éventuelle du SMIG après le 1/12/2019 | Pièces s'arrêtant à cette date |

### 10.4 Points de vigilance sur l'articulation

1. **Renvois à l'ancien Code.** La CCNI cite des articles de la loi 97-17 (L.106, L.108, L.148-L.153, L.156, L.159). Cette loi est abrogée (art. 462 du Code de 2026) ; la CCNI reste applicable si elle n'est pas contraire (art. 459-461). Chaque renvoi est à rapprocher de l'article correspondant du nouveau Code (congés : art. 248-254 ; mutation : art. 258-267).
2. **Comparer le moteur à la CCNI**, ticket C26-25 : prime d'ancienneté (art. 52), indemnité de maladie (art. 87), panier (art. 53), congé supplémentaire des mères (art. 70), frais funéraires (art. 83).
3. **Cas où la loi est plus favorable que la CCNI** : appliquer la plus favorable au travailleur (maternité : 18 semaines, art. 277 ; indemnité spéciale d'un mois en cas de licenciement économique).

### 10.5 Tickets ajoutés ou modifiés

| Ticket | Priorité | Intitulé |
|---|---|---|
| C26-24 | annulé | « Trancher l'indemnité de retraite » : sans objet, la CCNI art. 84 confirme 25/30/45/50 |
| C26-25 | P1 | Comparer le moteur à la CCNI (prime d'ancienneté, maladie, panier, congé des mères) |
| C26-26 | P0 | Charger `garnishment_scale` (CPC 381) et le plafond global des 2/3 dans les retenues |
| C26-27 | P1 | Charger `notice_scales` (1/2/3 mois) et `overtime_multipliers` (CCNI art. 49) |
| C26-28 | P1 | Ajouter la participation aux frais funéraires (≥ 1 mois) et l'indemnité de décès |
| C26-29 | P1 | Contrôle du minimum légal : SMIG 333,808 F/h, exclusions de l'art. 3 du décret |

---

## 11. Mise à jour du 5 novembre 2026 (soir) : nouveau Code de la Sécurité sociale, comité d'hygiène, retraite, amendes

Textes lus : **loi n° 2026-19 du 3 septembre 2026 portant Code de la Sécurité sociale** (JO n° 7932 du 18 septembre 2026, 46 p.), **décret n° 94-244 du 7 mars 1994** (comités d'hygiène et de sécurité du travail), **décret n° 2020-2072 du 28 octobre 2020** (art. L.69 al. 3 de l'ancien Code, scan lu par OCR et vérifié sur l'image), **décret n° 2006-1257 du 15 novembre 2006** (risques chimiques). Détail dans `docs/sources-legales/EXTRAITS_SECURITE_SOCIALE_ET_DECRETS.md`.

> Numérotation : dans le Journal officiel, le **Code du Travail est la loi n° 2026-18** (JO 7931) et le **Code de la Sécurité sociale la loi n° 2026-19** (JO 7932). Une page du site `vie-publique.sn` intitule « loi 2026-19 » le Code du Travail : **c'est probablement une erreur de libellé du site** ; cette spécification suit le Journal officiel.

### 11.1 Décret sur les amendes administratives (art. 373 du Code du Travail)

**Non fourni et introuvable.** L'art. 373 du Code du Travail et l'art. 309 du Code de la Sécurité sociale renvoient chacun à « un décret » qui fixe la nature des manquements, les montants et les modalités. Ni vos pièces jointes ni mes recherches ne montrent ce décret ; il n'est pas non plus cité comme pris. Le décret 94-244 renvoie, pour ses contraventions, au décret 62-017 du 22 janvier 1962 (échelle des peines de simple police), non fourni.

Conséquences pour SOMA-RH : `administrative_fine_scale` reste **« à fournir »** ; l'exposition financière se calcule avec les **sanctions pénales** (Code du Travail, art. 448-458, §2.K) et les **majorations de la Sécurité sociale** ci-dessous. Garde-fou : alerte « barème d'amende administrative non renseigné » sans blocage.

**Majorations et pénalités connues (CSS, art. 297-323)** :

| Règle | Valeur | Article |
|---|---|---|
| Retard de versement des cotisations | **10 % par mois ou fraction de mois**, plafonné à **50 % par an** des sommes dues ; remise gracieuse possible par le conseil d'administration (examen sous 3 mois) | 320 |
| Non-respect des mesures de prévention prescrites | Majoration de cotisations de **10 %** | 319 |
| Déclaration de rémunérations absente ou inexacte | **Taxation d'office** : déclaration antérieure majorée de **70 %** (ou salaire pratiqué dans la profession) ; contestation sous **15 jours francs** | 321-323 |
| Recouvrement | Mise en demeure : **30 jours francs** ; contrainte ; opposition sous **15 jours francs** avec caution de **la moitié** de la créance ; prescription **5 ans** ; privilège sur les meubles et hypothèque légale | 297-299, 306-307 |
| Amende pour entrave aux agents des institutions de prévoyance | **500 000 à 2 000 000 F** et 15 jours à 3 mois | 313 |
| Cumul d'amendes | Encourue **autant de fois qu'il y a d'infractions** (autant de travailleurs concernés) | 318 |
| Fraude ou fausse déclaration pour obtenir des prestations | Peines de l'escroquerie (Code pénal) et remboursement | 310 |

### 11.2 Règles de cotisation et de déclaration (CSS)

| ID | Art. | Règle | Paramètre / garde-fou |
|---|---|---|---|
| SS-01 | 73 | **Assiette** : toutes les sommes versées ou dues (salaires, gains, allocations de congé, indemnités, primes, gratifications, avantages en espèces et en nature) **sauf frais professionnels et remboursements de frais** ; avantages en nature évalués **comme en matière d'impôt** (CGI art. 166 et arrêté 012914, §10.1) ; **plafonds réglementaires** ; **plancher** : la rémunération n'est jamais inférieure au SMIG pour les personnes non rémunérées normalement | `social_ceilings` (arrêté, **à fournir**) ; **[A]** salaire déclaré < SMIG |
| SS-02 | 75 | Prestations familiales et accidents du travail : **employeur seul** (clause contraire nulle). Vieillesse, invalidité, survivants, soins médicaux : employeur et travailleur selon des pourcentages d'un arrêté ; **part du travailleur ≤ la moitié** ; précomptée à chaque paie, sans opposition possible | Contrôle : `part_salariale ≤ 50 %` de la cotisation vieillesse |
| SS-03 | 74 | Taux fixés par le conseil d'administration de chaque institution, dans les maxima d'un arrêté du ministre ; taux AT/MP selon le niveau de risque du secteur | Taux et plafonds : **à fournir** (restent « à confirmer » au registre RL-001 à RL-009) |
| SS-04 | 89-90 | **Immatriculation de l'employeur** ; **affiliation du travailleur dans les 2 mois** du premier embauchage | `hire_declaration_ref` + `affiliation_date` ; **[B]** affiliation > 2 mois après l'embauche |
| SS-05 | 91-93 | Déclaration nominative **mensuelle ou trimestrielle** ; versement **dans les 15 premiers jours de chaque mois si ≥ 20 salariés**, **de chaque trimestre si < 20** ; salarié de plusieurs employeurs : proportion et plafonds | `contribution_deadline` selon l'effectif ; **[A]** J-5 ; **[B]** clôture de paie sans déclaration générée |
| SS-06 | 91 (fin) | Cotisations **immédiatement exigibles** en cas de cessation d'activité ou de cessation complète d'emploi du travailleur ; à la charge du cessionnaire en cas de cession d'activité | **[A]** à la sortie d'un salarié : cotisations dues sans attendre l'échéance |
| SS-07 | 91 | Prélèvements du travailleur précomptés d'office, **sans cession volontaire** (cohérent avec RET-01) | Rubrique non décochable |
| SS-08 | 201-202 | Allocations de maternité : de la naissance au 2e anniversaire de l'enfant ; **indemnités journalières** pendant le congé de maternité du Code du Travail | Lien avec le congé de 18 semaines (art. 277 du Code) |
| SS-09 | 213-214 | **Âge d'ouverture de la pension fixé par décret** (non fourni) ; jouissance anticipée jusqu'à 5 ans avant (coefficient d'anticipation) ; report possible jusqu'à 5 ans ; **sans abattement** 5 ans avant pour inaptes, cessation avant le 1/7/2016 ou emplois pénibles ; points de bonification pour l'ajournement jusqu'à 5 ans après | `retirement_age` : voir §11.3 |
| SS-10 | 108-109 | Obligations de l'employeur en cas d'accident du travail et déclaration par la victime | À croiser avec OBL-06 |

### 11.3 Âge de la retraite

- Le Code de la Sécurité sociale (art. 213) fixe l'âge d'ouverture de la pension **par décret, non fourni**.
- Le **décret 2020-2072** (art. 1) permet de poursuivre le travail **au-delà de 60 ans et jusqu'à 65 ans** pour les **médecins, pharmaciens, chirurgiens-dentistes et docteurs vétérinaires**.
- **Incohérence dans la pièce** : son rapport de présentation écrit que l'âge d'admission à la retraite est « fixé à soixante-cinq (65) ans par le régime national » (vérifié sur l'image), alors que le dispositif parle de dépasser 60 ans. Le décret lui-même vise l'art. L.69 de la loi 97-17, **abrogée** par l'art. 462 du nouveau Code ; son maintien est à confirmer (art. 459-461).
- **Valeur proposée** : `retirement_age = 60` (défaut **héritée**, à confirmer), `retirement_age_extended = 65` pour les quatre professions de santé. Alertes RUP-11 inchangées.

### 11.4 Comité d'hygiène et de sécurité du travail (décret 94-244)

| Règle | Valeur | Article |
|---|---|---|
| Comité obligatoire | Établissements d'**au moins 50 salariés** (effectif calculé selon l'art. 3 du décret 67-1360) ; l'inspecteur peut l'imposer en dessous (mise en demeure ≥ 15 jours) | 1-2 |
| Composition | Chef d'établissement (président), responsable sécurité (secrétaire), médecin du travail, **3 travailleurs** cooptés ; mandat **3 ans** renouvelable | 3-4 |
| Réunions | **Au moins une par trimestre** ; après tout accident grave ; sur demande motivée de 2 membres ; ordre du jour transmis **3 jours** avant | 7 |
| Temps de réunion, de formation et d'enquête | **Temps de travail rémunéré** | 9 |
| Programme et rapport | **Programme annuel** de prévention en début d'année ; **rapport annuel** en fin d'année, **transmis à l'inspecteur** | 13-14 |
| Registre | Procès-verbaux et statistiques d'accidents tenus à disposition de l'inspecteur | 12 |

Rappel : les art. 340-341 du nouveau Code renvoient les seuils à un décret ; **ce décret de 1994 est le texte hérité applicable** tant qu'aucun décret nouveau n'est publié (art. 460-461). SOMA-RH : champs `chst_required` (effectif ≥ 50), `chst_meetings`, `chst_annual_report_sent_on` ; **[A]** réunion trimestrielle manquante ; **[A]** rapport annuel non transmis au 31 janvier (échéance à confirmer). Le suivi détaillé relève du module HSQE (décision D12). Le décret 2006-1257 (produits chimiques) relève aussi du module HSQE et ne génère aucune règle de paie.

### 11.5 Paramètres qui restent à fournir

| Paramètre | Statut |
|---|---|
| Décret sur les amendes administratives (Code du Travail art. 373 et CSS art. 309) | Non publié dans les pièces ; à rechercher auprès de la DGTSS ou du JO |
| Taux de cotisation, plafonds, répartition employeur/travailleur (arrêtés CSS) | Non fournis |
| Âge d'ouverture de la pension (décret, CSS art. 213) | Non fourni |
| Plafond de la retenue de logement (Code du Travail art. 260) | Non fourni |
| Arrêtés sur le bulletin, le registre, la déclaration d'embauche | Non fournis |
| Décret 67-1360 (délégués du personnel) et 62-017 (peines de simple police) | Cités par 94-244, non fournis |

### 11.6 Tickets ajoutés

| Ticket | Priorité | Intitulé |
|---|---|---|
| C26-30 | P0 | Échéancier cotisations : mensuel (≥ 20 salariés) ou trimestriel (< 20), alerte J-5, calcul de la majoration de retard (10 %/mois, plafond 50 %/an) |
| C26-31 | P0 | Affiliation sous 2 mois : champ `affiliation_date` et blocage de la paie sans déclaration d'embauche |
| C26-32 | P1 | Contrôle de l'assiette de cotisation : frais exclus, avantages en nature selon l'arrêté 012914, plancher SMIG |
| C26-33 | P1 | Cotisations exigibles à la sortie (art. 91) et alerte dans le solde de tout compte |
| C26-34 | P2 | Suivi du comité d'hygiène (≥ 50 salariés), alertes réunions et rapport annuel |
| C26-35 | P2 | `administrative_fine_scale` : table vide et alerte « paramètre manquant » en attendant le décret |

---

## 12. Mise à jour du 5 novembre 2026 (fin d'après-midi) : délégués du personnel

Textes lus (recueil « Le manuel du travailleur », pp. 449-460) : **décret n° 67-1360 du 9 décembre 1967** (désignation et mission des délégués du personnel) et **décret n° 83-680 du 29 juin 1983** (remplace son art. 10). Deux des fichiers reçus sont identiques entre eux, et le décret 2020-2072 reçu à nouveau est identique à celui déjà sauvegardé ; ils n'ont été archivés qu'une fois. Détail dans `docs/sources-legales/EXTRAITS_DELEGUES_DU_PERSONNEL.md`. **Ces décrets visent l'ancien Code (loi 61-34 puis 97-17) : leur maintien sous le Code de 2026 est à confirmer (art. 459-461) ; les art. 60 et 63 du nouveau Code renvoient à un décret pour les seuils.**

| ID | Art. | Règle (décret 67-1360 modifié) | Paramètre / garde-fou |
|---|---|---|---|
| DP-01 | 1 | Délégués obligatoires dans tout établissement de **plus de 10 travailleurs** ; établissements voisins (rayon de **10 km**) totalisés en un collège s'ils ont chacun 10 ou moins | `delegate_threshold = 11` ; confirme la CCNI art. 14 ; **[A]** effectif ≥ 11 sans délégués |
| DP-02 | 2 | Nombre de délégués (titulaires = suppléants) : **11 à 25 : 1** ; **26 à 50 : 2** ; **51 à 100 : 3** ; **101 à 250 : 5** ; **251 à 500 : 7** ; **501 à 1000 : 9**, plus 1 par tranche supplémentaire de 500 | Table `delegate_seats(from_headcount, to_headcount, seats)` ; **[A]** nombre élu différent du nombre prévu |
| DP-03 | 3 | **Effectif pris en compte** : travailleurs occupés habituellement, inscrits ou non au registre ; assimilés : apprentis, essai, horaires ou journaliers totalisant l'équivalent de **6 mois par an**, saisonniers revenant régulièrement (6 mois dans l'année), gérants ou représentants liés par contrat ; travailleur multi-établissements rattaché à celui où il consacre l'essentiel de son activité | Calcul d'effectif DP, distinct de l'effectif de paie |
| DP-04 | 4-9 | **Deux collèges** (ouvriers et employés ; ingénieurs, chefs de service, techniciens, maîtrise) ; **électeurs : 18 ans révolus et 6 mois d'ancienneté** ; **éligibles : 21 ans révolus, nationalité sénégalaise (ou convention d'égalité), français parlé, 12 mois d'ancienneté continue** ; exclus : ascendants, descendants, frères et alliés au même degré de l'employeur ; dérogations d'ancienneté par l'inspecteur | Champs `date_of_birth` (déjà requis), `seniority`, `nationality` pour calculer électeur et éligible |
| DP-05 | 10 (rédaction 83-680) | **Élection tous les 3 ans**, dans le mois qui précède l'expiration des fonctions | `representatives.end_date` ; **[A]** J-60 avant l'échéance ; **[A]** mandat expiré sans élection. Le recueil reproduit encore « chaque année » : c'est l'ancienne rédaction |
| DP-06 | 11 | Annonce aux syndicats avec copie à l'inspection ; avis affiché **15 jours** avant le scrutin ; listes déposées **4 jours** avant, affichées **3 jours** avant ; accord sur la date au plus tard **3 semaines** avant l'expiration | Échéancier `election_calendar` généré à partir de la date du scrutin |
| DP-07 | 13-17 | Scrutin de liste à deux tours, proportionnelle au quotient, plus forte moyenne ; second tour sous **15 jours** si moins de la moitié des inscrits ont voté | Information |
| DP-08 | 18 | Procès-verbal en **3 exemplaires** à l'inspecteur **sous huitaine** | **[A]** PV non déposé à J+8 |
| DP-09 | 19 | Temps de délégation : **au plus 15 heures par mois** « sauf convention contraire », **payé comme temps de travail**, utilisé pour les missions de délégué | **Règle applicable pour SOMA : 20 h/mois** (CCNI art. 14, plus favorable que le décret) ; `delegate_hours_per_month = 20` ; **[B]** retenue d'absence sur heures de délégation |
| DP-10 | 20-25 | Local et mobilier ; affichage ; réception **collective au moins une fois par mois** ; note écrite remise **2 jours** avant l'audience ; **registre spécial** : réponse de l'employeur **sous 6 jours** ; registre consultable un jour ouvrable par quinzaine et par l'inspecteur | `dp_requests(note_date, response_due = +6 jours, response_date)` ; **[A]** réponse non portée à J+6 |
| DP-11 | 26-27 | Révocation en cours de mandat par vote du collège ; perte d'éligibilité ; **élection complémentaire sans délai** en cas de siège vacant | **[A]** siège vacant sans élection complémentaire |
| DP-12 | 28 | Amende de simple police **2 000 à 18 000 F** (62-017), au maximum et 6 à 10 jours en cas de récidive | Montant symbolique : l'exposition réelle vient du Code de 2026, art. 455 (500 000 à 10 000 000 F) |

**Impacts sur les règles déjà écrites**

- RUP-16 (salariés protégés) : le « seuil à fournir » est comblé (plus de 10 travailleurs) ; le mandat de **3 ans** est confirmé ; les heures de délégation passent de « à fournir » à **20 h/mois (CCNI)**.
- OBL-08 : seuil et heures sourcés. Il reste à fournir le **décret 62-017** de 1962 (échelle des peines de simple police), cité par 67-1360 et 94-244.
- Le §11.5 est mis à jour : le décret 67-1360 n'est plus à fournir.

**Tickets** : C26-36 (P1) tables `delegate_seats` et `representatives` avec alertes d'échéance de mandat (J-60) ; C26-37 (P1) registre `dp_requests` avec délai de réponse de 6 jours ; C26-38 (P2) calcul d'effectif DP (art. 3) distinct de l'effectif de paie.

---

## 13. Mise à jour du 5 novembre 2026 (15 h) : ancien Code de 1997 et concordance avec la CCNI

Pièces reçues : **Code du Travail, loi n° 97-17 du 1er décembre 1997** (copie Droit-Afrique, 48 p., texte intégral), **CGI de juillet 2019** (387 p.), et deux doublons exacts (décret 2020-2072 ; JO 7932, texte identique à la copie déjà sauvegardée). Le CGI 2019 est **remplacé** par le CGI de janvier 2025 déjà sauvegardé (§10) ; il n'est conservé que pour l'historique. Détail : `docs/sources-legales/CONCORDANCE_ANCIEN_CODE_CCNI.md`.

**Statut.** La loi 97-17 est **abrogée** par l'art. 462 du Code de 2026. Elle reste utile pour une seule raison : la **CCNI et les décrets d'application la citent** (articles L.xxx). Tant que ces textes restent applicables (art. 459-461), chaque renvoi doit être lu avec l'article correspondant du nouveau Code.

### 13.1 Concordance des renvois de la CCNI

| Renvoi (CCNI) | Ancien Code (lu) | Contenu | Nouveau Code (famille d'articles) | Écart à noter |
|---|---|---|---|---|
| L.106 (art. 57, 60) | L.106 | Logement fourni au travailleur déplacé de sa résidence ; décret sur les cas, la **valeur maximale de remboursement** et les conditions | 259-263 (mutation et logement), 260 (valeur de remboursement par arrêté) | Le décret de valeur maximale n'est toujours pas fourni |
| L.107 (décret SMIG art. 4) | L.107 | Ravitaillement en vivres ; arrêté du ministre | à vérifier dans le Code de 2026 | Plafond de retenue de la ration : décret SMIG art. 4 (2 × ou 1 × le taux horaire agricole) |
| L.108 (art. 57) | L.108 | Indemnité de déplacement : taux fixés par la convention à défaut de texte | 3 et 258 (déplacement ≤ 6 mois) | Même principe ; taux de la CCNI art. 57 (6, 8, 10 fois le taux horaire) |
| L.148 (art. 70) | L.148 | Congé : **2 jours ouvrables par mois**, majoration d'ancienneté selon règlements ou convention ; **mères : 1 jour par enfant** (ancien Code) | 248-254 (2 jours par mois, 6 jours obligatoires) | **CCNI plus favorable : 2 jours par enfant** (art. 70). Appliquer la CCNI |
| L.149 (art. 70, 27) | L.149 | Permissions exceptionnelles non déductibles dans la limite de **10 jours** par an | 248-254 | **CCNI plus favorable : 15 jours** (art. 27 et 70). Appliquer la CCNI |
| L.150 (art. 69) | L.150 | Période de référence de **12 mois** ; congé de **6 jours ouvrables** obligatoire chaque année ; report d'accord parties sans dépasser 3 ans de service | 248-254 | Concorde avec `leave_min_days_per_year = 6` |
| L.153 (art. 72) | L.153 | Allocation de congé calculée sur l'horaire ; base **1/12 des sommes perçues** (CCNI) | 254 (1/12 des sommes perçues) ; 197 (moyenne 12 mois) | Concorde |
| L.156 (art. 58) | L.156 | Transport du travailleur, conjoint, enfants mineurs et bagages à la charge de l'employeur s'il est déplacé ; exceptions listées | 261-266 (transport) | CCNI art. 58 : classes de passage et bagages |
| L.159 (art. 58) | L.159 | Titres de transport exigibles dans les **2 ans** après la cessation ; attestation du **décompte exact** des droits remise à la rupture | 265 et 267 | Concorde avec MOB-03 |

### 13.2 Sanctions de l'ancien Code (information)

Le titre « Pénalités » du Code de 1997 (art. L.274 à L.288) prévoit des amendes de **200 000 à 500 000 F** (L.280, récidive : 400 000 à 1 000 000 F), de **250 000 à 1 000 000 F** (L.278) et de **500 000 à 1 000 000 F** avec 15 jours à 3 mois de prison (L.281). **Aucune amende de « 50 000 à 500 000 F »** n'y a été trouvée : le chiffre du document de départ (rubrique 9) est donc **non confirmé**. Pour SOMA-RH, seules comptent les sanctions du Code de 2026 (art. 448-458, §2.K) ; les amendes administratives de l'art. 373 attendent leur décret (§11.1).

### 13.3 Règles à retenir pour SOMA-RH

1. **Principe de faveur** : quand la CCNI, l'ancien Code ou un décret héritée donne un avantage supérieur au Code de 2026, SOMA-RH applique le plus favorable au travailleur (art. 459 al. 3 : maintien des avantages contractuels supérieurs). Paramètre `favourable_rule_source` sur chaque rubrique calculée.
2. **Table `legal_sources`** : ajouter pour chaque valeur le champ `legacy_ref` (ex. « L.148 ») et `new_code_ref` (ex. « art. 248 ») afin de suivre la bascule quand un décret remplacera un texte hérité.
3. **Congés** : mères, **2 jours par enfant** (CCNI) et non 1 (ancien Code) ; permissions exceptionnelles non déductibles jusqu'à **15 jours** par an.

**Ticket** : C26-39 (P2) renseigner `legacy_ref` et `new_code_ref` sur toutes les valeurs de `legal_sources`.
