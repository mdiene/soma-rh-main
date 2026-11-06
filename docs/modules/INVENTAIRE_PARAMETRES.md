# Inventaire des paramètres des manifestes par statut légal

## Contexte
Cet inventaire recense l'ensemble des paramètres présents dans les manifestes de modules SOMA-RH, classés par statut légal :
- **verified** : La valeur est confirmée par référence légale documentée
- **to_provide** : La valeur doit être fournie par le client (non lue dans le décret)
- **secondary** : La valeur provient d'une source secondaire (guides pratiques, concordants)

## Paramètres "verified" (confirmés par référence légale)

### `weekly_legal_hours`
- **Valeur** : 40 heures/semaine
- **Unité** : hours_per_week
- **Source** : Code du travail 2026 (loi 2026-18), art. 241
- **Statut** : verified
- **Observations** : Heure légale par défaut pour le secteur privé sénégalais

### `night_window`
- **Valeur** : { start: "22:00", end: "05:00" }
- **Unité** : fenêtre horaire
- **Source** : Code du travail 2026, art. 245 (22 h – 5 h) ; décret 70-182 de 1970 existe, texte non lu ; modalités par arrêté (non fourni)
- **Statut** : verified
- **Observations** : Fenêtre nocturne définie par la loi, modalités d'application non détaillées

### `weekly_rest_hours`
- **Valeur** : 24 heures/semaine
- **Unité** : hours_per_week
- **Source** : Code du travail 2026, art. 246
- **Statut** : verified
- **Observations** : Repos hebdomadaire légal

### `overtime_rates_table`
- **Valeur** : "overtime_rates" (référence table cœur)
- **Unité** : référence table
- **Source** : Table du cœur ; classeur de référence : 115 / 140 / 160 / 200 %. Décret 70-184 (JO 4091 p. 259, non lu) : guides pratiques concordants +15 % (41e-48e h), +40 % (au-delà), +60 % nuit, +60 % repos/férié de jour, +100 % de nuit
- **Statut** : secondary
- **Observations** : Taux de majoration basés sur le décret, guides concordants bien que décret non lu

## Paramètres "to_provide" (non lus dans le décret, à saisir par le client)

### `equivalence_thresholds`
- **Valeur** : null (non saisi)
- **Unité** : hours_per_week_by_post_category
- **Source** : Décret 70-183 (JO n° 4091 du 09/03/1970, art. 4 : régime d'équivalence ; art. 11 modifié par le décret 2006-1262) : existence confirmée, seuils par catégorie non lus. Les valeurs 56 h et 72 h du document de départ proviennent d'un décret du Niger (2017-682) et ne s'appliquent pas
- **Statut** : to_provide
- **Observations** : Seuils d'équivalence par catégorie de poste non lus dans le décret sénégalais. Les valeurs du document initial proviennent d'un autre pays (Niger). **Champ critique à fournir par le client.**
- **Client input allowed** : true

### `max_shift_duration_hours`
- **Valeur** : null (non saisi)
- **Unité** : heures
- **Statut** : to_provide
- **Client input allowed** : true
- **Observations** : Durée maximale de shift à définir selon la convention applicable

## Paramètres "secondary" (sources secondaires)

### `equivalence_thresholds` (valeurs du document de départ - non applicables)
- **Valeur** : 56 h / 72 h (régime nigérian)
- **Source** : Document de départ (Niger 2017-682)
- **Statut** : to_provide (non applicable Sénégal)
- **Observations** : Les valeurs 56h et 72h du document initial proviennent d'un décret du Niger et ne s'appliquent pas au Sénégal. Doivent être remplacées par des valeurs sénégalaises ou laissées à null/to_provide.

## Paramètres spécificaux par module

### Module Sécurité privée / Gardiennage
- `equivalence_thresholds` : À fournir par le client (non lu dans décret Sénégal)
- `max_shift_duration_hours` : À fournir par le client
- `night_bonus_rate` : Taux saisi par le client (convention ou accord). Le 0,50 du document de départ n'a pas de source
- `parameters.equivalence_thresholds` : Bloque la règle GARD_EQUIVALENCE_CONVERSION (voir règles de calcul)

### Module Interim / Gardiennage
- Même structure que sécurité privée pour les paramètres non lus
- Paramètres communs au secteur du gardiennage

## Résumé de l'inventaire

| Paramètre | Statut | Action requise |
|-----------|--------|----------------|
| `weekly_legal_hours` | verified | Aucune |
| `night_window` | verified | Aucune |
| `weekly_rest_hours` | verified | Aucune |
| `overtime_rates_table` | secondary | Vérifier les taux avec la table cœur |
| `equivalence_thresholds` | to_provide | **Saisir par client** (valeurs sénégalaises) |
| `max_shift_duration_hours` | to_provide | **Saisir par client** |
| `night_bonus_rate` | to_provide | **Saisir par client** (taux convention) |
| `parameters.equivalence_thresholds` | to_provide | **Saisir par client** (bloque règle d'équivalence) |

## Points d'attention

1. **Équivalence thresholds** : C'est le paramètre critique. Sans seuil d'équivalence par catégorie de poste, la règle `GARD_EQUIVALENCE_CONVERSION` ne peut pas s'exécuter et la paie sera bloquée avec une alerte `GARD_MISSING_EQUIVALENCE` (sévérité : blocking).

2. **Taux de majoration** : Les taux de nuit, heures supplémentaires et repos/fériés proviennent principalement du décret 70-184, mais le décret n'a pas été lu en détail. Les valeurs 115/140/160/200% doivent être validées.

3. **Document de départ non applicable** : Les valeurs 56h et 72h du document initial proviennent du Niger et ne s'appliquent pas au Sénégal. Il faut soit saisir de nouvelles valeurs, soit laisser null/to_provide.

4. **Client input** : Les paramètres marqués `client_input_allowed: true` doivent être traités comme des champs de saisie obligatoire dans l'interface utilisateur.