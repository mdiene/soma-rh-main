# SOMA-RH — Cadrage du codage : conformité au Code du Travail 2026

Date : 5 novembre 2026. Complète `CODE_TRAVAIL_2026_SPECIFICATION_SOMA_RH.md` (spécification) et `docs/sources-legales/`.
Objet : ce qui est déjà en base, ce qu'il reste à coder, dans quel ordre, avec quels tests.

## 1. Livré : trois migrations (testées sur une base temporaire)

| Migration | Contenu | Tickets |
|---|---|---|
| `20261109090000_c26_referentiels_legaux` | `legal_sources` ; `garnishment_scale` (5 tranches principales, 4 supplémentaires) ; `quotite_cessible()` ; `plafond_retenues()` ; `payroll_settings.deduction_global_cap` (2/3) ; `notice_scales` (1/2/3 mois) ; `overtime_rates` (15/40/60/60/100 %) ; `severance_scales` | C26-26, 27, 10, 39 |
| `20261109100000_c26_maternite_sorties` | Maternité 126 jours + `leave_types.extension_days` = 21 ; `exit_reasons` (16 motifs + 2 anciens codes) ; l'ancien contrôle de `employees.exit_reason` devient une clé étrangère ; `payroll_settings.severance_min_months` = 12 | C26-01, 03, 04, 05 |
| `20261109110000_c26_conformite` | `employees.hire_declaration_ref`, `hire_declared_on`, `affiliation_date` ; vue `v_conformite_embauche` ; `echeance_cotisations()` ; `majoration_retard_cotisations()` ; `delegate_seats` ; `employee_representatives` ; `compliance_findings` | C26-09, 15, 17, 30, 31, 35, 36-38 |

Chaque migration a son retour dans `db/rollback/`. Toutes les nouvelles tables ont RLS, politiques par rôle et index sur les clés étrangères ; les montants sont en `numeric`.

**Tests passés** (base PostgreSQL temporaire avec le schéma réel `core_hr`, `payroll_schema`, `security_rls`, `reference_data`) :
- application des trois fichiers sans erreur ; retour puis réapplication sans erreur ;
- quotité cessible : 50 000 → 10 000 ; 150 000 → 45 000 ; 300 000 → 165 000 (tranche supplémentaire : 65 000) ; plafond 2/3 : 33 333,33 / 100 000 / 200 000 ;
- maternité 126 / 21 ; un salarié sorti avec l'ancien motif « FIN DE CONTRAT » reste valide ; un motif inconnu est refusé ;
- majoration de retard : 5 jours après l'échéance → 10 % ; 3 mois → 30 % ; 8 mois → 50 % (plafond) ; échéance : 15 du mois (≥ 20 salariés) ou du trimestre suivant (< 20) ;
- RLS actif sur les 9 nouvelles tables ; aucune clé étrangère sans index.

**Non testé** : l'application sur votre base locale réelle (Docker absent de l'environnement d'écriture), et `scripts/verify-payroll.ps1` — le moteur `compute_salary_slip` n'a pas été modifié, mais lancez-le après application pour le confirmer.

## 2. À faire par vous, dans l'ordre

```
docker exec -i soma-rh-local-postgres-1 psql -U soma -d soma_rh -v ON_ERROR_STOP=1 < db/migrations/20261109090000_c26_referentiels_legaux.sql
docker exec -i soma-rh-local-postgres-1 psql -U soma -d soma_rh -v ON_ERROR_STOP=1 < db/migrations/20261109100000_c26_maternite_sorties.sql
docker exec -i soma-rh-local-postgres-1 psql -U soma -d soma_rh -v ON_ERROR_STOP=1 < db/migrations/20261109110000_c26_conformite.sql
scripts/verify-payroll.ps1        # doit rester identique (moteur non modifié)
```
Puis régénérer `web/src/lib/database.types.ts` et lancer `graphify update .`. Les migrations finissent par `notify pgrst, 'reload schema'`.

## 3. Ce que ces migrations ne font pas (volontairement)

1. **`sortie_salarie` accepte toujours les 5 anciens motifs.** La table `exit_reasons` est prête ; la fonction doit la lire (lot B).
2. **`severance_coefficient` reste codée en dur.** `severance_scales` est un miroir ; le branchement est le ticket C26-25 (comparaison avec la CCNI).
3. **Aucun blocage de paie.** Les écarts d'embauche et d'affiliation sont listés par la vue, pas bloqués.
4. **Maternité : date d'application.** Le passage à 126 jours est appliqué dès maintenant ; si le juriste retient une autre date d'entrée en vigueur (art. 459), il faut dater la règle.
5. **Motifs « à confirmer »** (rupture amiable, inaptitudes, force majeure, démission sans préavis) : droits laissés à zéro, avec une note.
6. **Majoration de retard** : le plafond de 50 % est annuel ; la fonction suppose un retard de moins d'un an.

## 4. Ordre de développement proposé

| Lot | Contenu | Touche le moteur ? | Test de sortie |
|---|---|---|---|
| A | Appliquer les 3 migrations, types, ajout au registre légal (§6) | Non | `verify-payroll` identique |
| B | `sortie_salarie` lit `exit_reasons` ; indemnité spéciale d'un mois (C26-04) ; éligibilité à 12 mois (C26-05) ; décès : indemnité + 1 mois (C26-28) | Oui | `verify-payroll -Save` après revue des écarts, cas par motif |
| C | Retenues : plafond 2/3 et quotité cessible dans le calcul du net (C26-07, 26) ; interaction avec le plafond de prêt déjà codé (D30/D53) | Oui | cas 50 000 / 150 000 / 300 000 + retenues volontaires |
| D | Embauche et affiliation : saisie dans la fiche salarié, alerte puis blocage [B] à la 1re paie (C26-09, 31) | Non (contrôle de validation) | salarié sans référence : validation refusée |
| E | Écran de conformité : lecture de `compliance_findings`, dérogation avec motif (C26-17) | Non | RLS : seul RH déroge |
| F | Échéancier cotisations : alerte J-5, majoration (C26-30) | Non | cas de §1 |
| G | Heures supplémentaires et préavis depuis `overtime_rates` / `notice_scales` (C26-27, 11) | Oui | cas par tranche |

Règle pour les lots B, C et G : ils modifient `compute_salary_slip` ou `sortie_salarie`. Une migration par lot, retour fourni, `verify-payroll` avant et après, `-Save` seulement après vérification que chaque écart est voulu.

## 5. Paramètres encore « à fournir » (aucune valeur inventée)

| Manque | Conséquence |
|---|---|
| Décret sur les amendes administratives (CT art. 373 ; CSS art. 309) | Barème vide ; alerte « paramètre manquant » (C26-35) |
| Arrêtés sur taux et plafonds de cotisation | Registre RL-001 à 009 reste « à confirmer » |
| Décret sur l'âge d'ouverture de la pension (CSS art. 213) | 60 ans par défaut (héritée), 65 pour les quatre professions de santé |
| Plafond de la retenue de logement (CT art. 260) | Contrôle désactivé |
| Arrêtés bulletin, registre, déclaration d'embauche | Délai de déclaration d'embauche non codé |
| Décret 62-017 (peines de simple police) | Sans effet sur la paie |

## 6. Registre légal (`docs/regles-de-paie/registre-legal.mdx`)

Ajouter, au statut « à confirmer » : maternité (art. 277), assiette de l'art. 197, indemnité spéciale, retenues (art. 216 et CPC 381), preuve de paiement (art. 205), CDD, cotisations (CSS art. 91-93, 320). Passer en « conforme » seulement avec le texte officiel et une revue juridique ; `legal_sources.status` suit la même règle.

## 7. Questions pour le juriste (inchangées, à trancher avant les lots B et C)

1. Date d'application des règles nouvelles (maternité, indemnité spéciale).
2. Convention collective applicable à SOMA (CCNI ou convention de branche).
3. Lecture progressive des tranches de l'art. 381 du CPC.
4. Majoration de maternité de 3 semaines : par défaut ou sur certificat médical.
5. Retenues autorisées par écrit aujourd'hui (avances, caisse).
