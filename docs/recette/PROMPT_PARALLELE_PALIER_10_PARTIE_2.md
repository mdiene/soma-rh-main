# Prompt parallèle — palier 10, partie 2, sur base de test remise à zéro

> À coller dans une **seconde** instance de Claude Code, à la racine de `soma-rh-main`, sur une copie du dépôt (`git worktree add ../soma-rh-sim2 fix/rpr-09-prorata`) avec sa **propre base** : ne pas partager la base ni la passerelle (port 8000, limite de connexions par adresse) avec la première instance. Langue de travail : français. Lire d'abord `CLAUDE.md`, `docs/recette/PROMPT_REPRISE_2026-11-11.md` (sections 2 à 4) et `docs/recette/simulation-200/JOURNAL_PALIERS.md`.

## Contexte
La base actuelle (200 salariés) est une base de test : le propriétaire autorise sa remise à zéro et un rejeu complet avec Playwright, en tenant compte des fonctionnalités récentes (prorata D-56, recalcul d'une paie rouverte, approbation admin et paie, plafond de prêt 1/3 avec surcharge par salarié, matricule paramétrable, départements, connexion par téléphone). Aucune donnée personnelle réelle, aucun secret dans Git.

## Consignes
1. Sauvegarder (`scripts/local-backup.ps1`), puis remettre la base à zéro avec la procédure de `docs/LOCAL_SETUP.md` ; appliquer toutes les migrations (`scripts/check-migrations.sh` signale 4 préfixes en double antérieurs : ne pas les « corriger » sans accord), `notify pgrst, 'reload schema'`, régénérer les types si le schéma a changé.
2. Recréer les comptes de simulation (`scripts/sim-create-users.ps1`, fichier `tests/.env.qa-sim` hors Git).
3. Rejouer dans l'ordre `web/e2e/sim/10-croissance`, `11-octobre`, `12-reouverture`, `20-roles`, `31-rpr-mutating` (`npx playwright test -c playwright.sim.config.ts --workers=1`). Redémarrer la passerelle (`docker restart …-api-1`) avant chaque suite d'API : la limite par adresse est en mémoire.
4. Écrire puis jouer la **partie 2 du palier 10** : CDD et intérim (création, renouvellement, fin, prime de précarité) ; ordres de virement ; états IPRES/CSS et DGID ; journal comptable ; rapport de clôture ; paiements par lot (BLOQUÉ si non implémenté, voir `docs/recette/simulation-200/PROPOSITION_PAIEMENTS_INDIVIDUELS.md`) ; accès interdits par rôle (menu, URL, API). Mesurer les temps à 200 salariés.
5. Consigner chaque constat (VERT / ROUGE / ORANGE) dans `JOURNAL_PALIERS.md` et `resultats-playwright.jsonl`. Ne jamais exécuter `scripts/verify-payroll.ps1 -Save` : la référence est à réenregistrer par le propriétaire après le rejeu.
6. Branche dédiée issue de `fix/rpr-09-prorata`, un commit par étape. Pas de push ni de fusion sans accord.

## Fin de session
Compte rendu court : fait, reste, tests (échecs connus distingués des régressions), risques, décisions attendues.
