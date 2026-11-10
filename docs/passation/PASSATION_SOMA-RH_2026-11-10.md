# Dossier de passation — SOMA-RH (au 10/11/2026)

À donner au nouveau projet Claude avec les fichiers listés en §10. Aucun mot de passe ni clé secrète dans ce document.

## 1. Le projet en deux lignes
SOMA-RH : application RH et paie de la Société Minière Africaine (Sénégal), interface et données en français. Propriétaire : Moussa Diene (Dakar). Elle sert aussi de socle à des modules métier verticaux (intérim, sécurité-gardiennage…) et s'inscrit dans le SI SOMA.

## 2. Où est quoi
| Élément | Emplacement |
|---|---|
| Dépôt de travail actif | `C:\IT-Mozaic\soma-rh-main` (GitHub `mdiene/soma-rh-main`, branche `main`, dernier commit `b0ec873`, **non poussé** : faire `git push`) |
| Ancien dossier de simulation | `C:\IT-Mozaic\SOMA-RH-local` (même code, base locale simulée à 200 salariés ; sauvegardes Supabase dans `backups\supabase-20261109-182227`) |
| Site en ligne | https://soma-rh.vercel.app (projet Vercel `soma-rh`, compte du propriétaire) |
| Base en ligne | Supabase `mozaic-admin`, ref `mzhdwdpesbggxtjxxgab`, région eu-west-1 (pooler `aws-1-eu-west-1.pooler.supabase.com:5432`, utilisateur `postgres.mzhdwdpesbggxtjxxgab` ; l'hôte direct est IPv6 seulement) |
| Autre projet Supabase | `Livraison_soma` (ref `ndzjirmrfdeheuljjvxb`) : livraisons, hors RH, tables vides |

## 3. Architecture
- `web/` : React 18, Vite, TypeScript, Tailwind, TanStack Query/Table. Pages `web/src/pages`, composants `web/src/components`. Palette `ink/paper/river/phosphate/signal`, police Archivo.
- `db/` : `migrations/` (134), `baseline/` (instantané du schéma `schema_local.sql` + `reference_data.sql`, **les migrations ne se rejouent plus à vide**, voir H48), `rollback/`, tests SQL dans `tests/sql/` (52). Moteur de paie en PL/pgSQL (`compute_salary_slip`).
- **Deux déploiements, même code** :
  - Local : Docker (`docker-compose.yml`), PostgreSQL 17 + PostgREST + passerelle `api/server.mjs` (port 8000 ; authentification `/auth/v1`, documents sur disque, limite 30 connexions / 15 min / IP, verrouillage D-58). Conteneurs `soma-rh-local-postgres-1`, `-api-1`, `-postgrest-1`, base `soma_rh`.
  - En ligne : Supabase (Auth, PostgREST, Storage bucket privé `employee-documents`) + Vercel (front seul, `vercel.json`, `.vercelignore` en liste blanche). Variables Vercel : `VITE_API_URL`, `VITE_API_PUBLIC_KEY` (clé publishable), `VITE_DOCUMENTS_MODE=supabase`.
- Rôles : `admin`, `rh`, `paie`, `manager`, `salarie` (`has_role`, `can()`). RLS partout.
- Workflow de paie : Brouillon → Calculée → En revue → Approuvée → Validée → Payée → Clôturée (+ Réouverte, Annulée). Périodes clôturées immuables. D-43 : approbation avant validation, dérogation admin avec motif. D-64 : garde de période (mois précédent Validée/Payée/Clôturée accepté).
- Création d'un salarié = fiche (RH) → déclaration d'embauche (référence + date) → structure salariale (paie ou admin seulement).

## 4. État des environnements
- **Supabase** : schéma complet rechargé (89 tables, 2 fonctions documents, bucket `employee-documents`). Données migrées depuis l'ancienne base : 27 employés, 12 rôles, 118 présences, 86 variables, 27 affectations, 26 soldes de congés, journal d'audit (1 194 lignes ; reprise de 36 lignes en collision d'identifiant possible en relançant l'étape « donnees »). Le planning des gardiens (`shift_assignments`, `work_posts`, `shift_types`) a été retiré du produit : 1 037 affectations de test **non migrées** (dans la sauvegarde).
- **Vercel** : déployé en production le 10/11/2026. La première version a été envoyée avec l'ancien `.vercelignore` : refaire `.\scripts\vercel-deploy.ps1` avec la liste blanche (maintenant versionnée) et supprimer l'ancien déploiement si souhaité.
- **Base locale** (`SOMA-RH-local`) : conservée **simulée** (décision du propriétaire) : 200 salariés, 11 conventions, 9 périodes de paie clôturées (janvier à septembre 2026), comptes `sim-*` (admin, rh, paie, rhpaie, manager, salarié). Ne jamais mettre à jour la référence de `scripts/verify-payroll.ps1` avec ces chiffres ; sauvegarde d'origine : `backups\soma-rh-20261109-141842.dump` (restauration par `scripts\local-restore.ps1`).

## 5. Campagne de simulation 10 → 200 salariés (terminée)
Résultats : `docs/recette/simulation-200/` (`RAPPORT_VERT_ROUGE.md`, `DOSSIER_DE_REPRISE.md` = 15 fiches RPR, `JOURNAL_PALIERS.md`, `resultats-playwright.jsonl`). Le calcul est conforme (HS, absence, prime, retenue, paniers vérifiés au franc) ; les écarts sont des défauts de parcours, d'alignement écran/base et de sécurité. Playwright : `npx playwright test -c playwright.sim.config.ts` depuis `web/` (14 tests verts, 5 min ; specs idempotentes dans `web/e2e/sim/`). Prompt de la campagne : `docs/recette/PROMPT_SIMULATION_200_SALARIES.md` (v2.2).

## 6. Décisions du propriétaire (ne pas rediscuter)
1. **Prorata D-56** : entrée ou sortie en cours de mois payée au prorata des jours travaillés (base ouvrables par défaut, paramétrable).
2. **Approbation de la paie** : administrateur et détenteur du rôle paie (pas le rôle rh) ; séparation des tâches maintenue.
3. **Plafond de retenue sur prêt** : variable de configuration, 1/3 par défaut, modifiable par salarié (admin, rh, paie) ; le net ne devient jamais négatif (D-30).
4. **Paiements individuels** : en attente ; proposition = règlement par lot (virement, chèque, espèces) dans `docs/recette/simulation-200/PROPOSITION_PAIEMENTS_INDIVIDUELS.md`.
5. Planning des gardiens : retiré de la version de base, futur module métier.
6. Connexion par téléphone : validation par l'**administrateur** dans l'interface (SMS plus tard), compte limité au rôle salarié.
7. Documents des salariés en ligne : Supabase Storage.

## 7. Travaux à lancer (prompts prêts)
| Prompt | Fichier | Statut |
|---|---|---|
| Correctifs RPR-01 à RPR-15 + décisions 1 à 3 | `docs/recette/simulation-200/PROMPT_CORRECTIFS_RPR.md` | à lancer dans Claude Code |
| Connexion des salariés par téléphone (validation admin) | `docs/PROMPT_CONNEXION_TELEPHONE_SALARIES.md` (voir aussi `docs/CONNEXION_TELEPHONE_SALARIES.md`) | à lancer dans Claude Code |
| Palier 10 de simulation : sorties, CDD, prêts, congés, heures supplémentaires | à écrire (explorer les écrans avant les sélecteurs) | à faire |
| Base documentaire utilisateurs (guide par rôle, calendrier de paie, glossaire, FAQ, index UC ↔ page ↔ test) | `docs/guide-utilisateur/` (39 captures déjà prises) | à faire |

## 8. Points de vigilance et dette connue
- **Sécurité (à faire maintenant)** : réinitialiser le mot de passe de la base Supabase (il est apparu dans une conversation) ; ne pas réutiliser le mot de passe commun des comptes `sim-*` ailleurs ; ajouter `https://soma-rh.vercel.app` dans Supabase > Authentication > URL Configuration ; activer la protection contre les mots de passe compromis ; vérifier les 120 fonctions `security definer` exposées (conçues avec `has_role`) et l'extension `btree_gist` dans `public`.
- **Prioritaires du dossier de reprise** : RPR-01 calcul sans structure silencieux, RPR-02 approbation écran/base alignée, RPR-03 verrouillage de connexion par adresse (un poste bloque toute l'entreprise 30 min).
- **En ligne ≠ local** : l'authentification Supabase remplace celle de la passerelle (pas de verrouillage D-58 ni de limite maison) ; les comptes `sim-*` n'existent pas en ligne.
- **Git** : 12 scripts apparaissent modifiés à cause des fins de ligne Windows (aucun changement de contenu) ; des fichiers `stale-*` laissés dans `.git` sont à supprimer ; `git push` à faire.
- Autres : D-58 (verrou par compte + adresse), D-50/51, D-54 à D-61, migration `20261104180000_maj_compute_salary_slip.sql` (risque de troncature à vérifier), cocher D-30/D-53 dans BATTERIE/TACHES/RESULTATS une fois validés.

## 9. Commandes utiles
```
# Local
docker compose up -d ; cd web ; npm run dev            # http://localhost:5173
cd web ; npm run check ; npm run build
node --test ../tests/unit/*.test.mjs ; scripts/test-sql.ps1 ; scripts/verify-payroll.ps1
npx playwright test e2e/menu.spec.ts e2e/a11y.spec.ts
# Migrations locales : docker cp + psql -f, puis  notify pgrst, 'reload schema'
# Supabase (depuis la racine du dépôt)
.\scripts\supabase-backup.ps1 -DbHost aws-1-eu-west-1.pooler.supabase.com -DbUser postgres.mzhdwdpesbggxtjxxgab
.\scripts\supabase-migrer.ps1 -Etape reset|donnees -Sauvegarde <dossier de sauvegarde>
# Vercel
.\scripts\vercel-deploy.ps1            # production ; -Apercu pour un aperçu
```
Pièges : `supabase-backup.ps1` et `supabase-migrer.ps1` ne font pas la même chose ; les migrations postérieures à la coupure `20261119090000_c26_jo4091_plancher_legal` sont rejouées par-dessus la baseline ; les tests e2e se connectent une fois par rôle (limite 30 connexions / 15 min).

## 10. Fichiers à donner au nouveau projet Claude
Déjà regroupés dans l'archive `SOMA-RH_passation_2026-11-10.zip` : ce dossier, `CLAUDE.md`, `README.md`, `docs/LOCAL_SETUP.md`, `docs/ARCHITECTURE_CIBLE_SOMA_RH.md`, `docs/REGISTRE_RISQUES_DECISIONS_SOMA_RH.md`, `docs/ARBITRAGES_PAIE.md`, `docs/FEUILLE_DE_ROUTE_V3_SOMA_RH.md`, `docs/TACHES_ET_RECOMMANDATIONS_RECETTE.md`, `docs/recette/` (simulation-200 complet), les trois prompts, `docs/CONNEXION_TELEPHONE_SALARIES.md`, `vercel.json`, `.vercelignore`, les scripts Supabase/Vercel, les modèles `.env`. Les textes juridiques (Code du travail 2026, Code de la sécurité sociale 2026, CCNI, extraits JO) et les documents du projet existant « Mozaic delivery rebuild » sont déjà dans le projet Claude actuel : à recopier dans le nouveau projet (voir la liste dans l'onglet Fichiers du projet).
**Jamais** : sauvegardes de base (`backups/`), `db/seed/`, `tests/.env.qa*`, fichiers `.env` réels, clés `service_role`.
