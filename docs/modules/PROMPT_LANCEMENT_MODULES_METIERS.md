# Prompt de lancement — Modules métiers SOMA-RH (à coller dans Claude Code, dossier `C:\IT-Mozaic\SOMA-RH-local`)

Utilisation : coller le bloc « Prompt » ci-dessous. Il lance **un lot à la fois** (M0 d'abord). Pour les lots suivants, remplacer « M0 » par le lot voulu (M1 à M7).

## Prompt

```
Tu travailles sur SOMA-RH (application RH et paie, Sénégal, interface en français). Lis d'abord, dans cet ordre :
1. CLAUDE.md (règles du projet, y compris migrations, PostgREST, RLS, design).
2. docs/modules/PROJET_MODULES_METIERS_MISE_EN_PLACE.md (le projet complet) et docs/modules/MODULES_METIER_VERTICAUX_SOMA_RH.md (spécification v2).
3. docs/modules/RESULTATS_RECHERCHE_TEXTES_A_FOURNIR.md (statuts légaux ✔ ◐ ✖) et les manifestes dans docs/modules/manifests/.
4. Pour comprendre le code existant, utilise `graphify query` avant de parcourir les fichiers : compute_salary_slip, payroll_inputs, shift_types, compliance_findings, SettingsPage, PayrollInputsPage, EmployeeFiche, SlipExplain.

Objectif : réaliser le lot M0 (ensuite, un seul lot par demande) du projet « Modules métiers » : des modules activables dans une page de paramètres « Métiers », qui ajoutent des champs complémentaires, des éléments de paie et des contrôles par métier, et calculent leur influence sur le salaire. Désactivés, ils ne doivent rien changer à l'application.

Règles impératives :
- Ne jamais inventer une valeur légale. Seuls les paramètres ✔ ou ◐ sont pré-remplis, avec leur statut et leur source. Les paramètres ✖ restent vides : le calcul émet une alerte « paramètre manquant » dans compliance_findings.
- Avant toute modification, lance `scripts/verify-payroll.ps1` et note l'empreinte. Après chaque migration touchant la paie, lance-le à nouveau : modules éteints, l'empreinte doit être identique. N'utilise `-Save` que sur une évolution voulue et après l'avoir signalée.
- Tout passe par une migration `db/migrations/AAAAMMJJHHMMSS_nom.sql` (horodatage après la dernière existante), appliquée sur la base locale via psql dans le conteneur soma-rh-local-postgres-1, suivie de `notify pgrst, 'reload schema'`, puis régénération de web/src/lib/database.types.ts. Fournis le retour arrière.
- Toute nouvelle table : RLS activée, politiques par rôle (has_role(array['rh'|'paie'])), index sur les clés étrangères. Montants en numeric ; arrondi à l'affichage seulement (fcfa() de web/src/lib/format.ts). Consulte la compétence supabase-postgres-best-practices.
- Interface : palette ink / paper / river / phosphate / signal, police Archivo, chiffres tabulaires ; composants dans web/src/components, pages dans web/src/pages ; compétences frontend-design, ui-ux-pro-max, vercel-react-best-practices. Textes en français. Accessibilité : navigation clavier, contraste AA.
- Reste en local (pas de service externe). Ne copie aucune donnée personnelle de salarié dans des fichiers suivis par Git.
- Ne modifie compute_salary_slip que de façon minimale et seulement au lot M3.

Livrables du lot demandé :
- M0 : migrations (module_manifest, module_activation, module_parameter_value, employee_module_data) avec RLS et index ; chargeur des manifestes JSON depuis docs/modules/manifests/ avec validation de schéma ; journal d'audit des activations ; tests SQL de RLS par rôle.
- (M1 à M7 : voir la section 8 du projet.)

Méthode : établis la liste de tâches, écris les tests avant le code, travaille par petits pas, puis vérifie : verify-payroll, build web (`npm run build` dans web/), lint, tests SQL. Termine par `graphify update .`.

Rapport final (court, en français) : ce qui est fait, les fichiers créés ou modifiés, le résultat de verify-payroll avant/après, les points ouverts à trancher. Ne fais pas de commit ni de push sans que je le demande. Arrête-toi à la fin du lot et attends ma validation avant de passer au suivant.
```

## Ordre de lancement conseillé

1. M0 puis M1 (socle et page Métiers) — aucun effet sur la paie.
2. M2 puis M3 (formulaires, moteur de règles, branchement dans la paie) — vérifier l'empreinte `verify-payroll`.
3. M4 (Services/Intérim), puis M5 (Gardiennage, Industrie et mines), M6 (planning, saisie rapide, mobile), M7 (modules restants).

## À fournir avant M3

Les cas dorés signés par le comptable, la confirmation de l'IFC intérim et du plafond AT, et si possible le PDF du JO n° 4091 du 09/03/1970 (pp. 257 à 260).
