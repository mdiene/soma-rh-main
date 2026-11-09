# Rejeu Playwright de la simulation 10 → 200 salariés

Prérequis : application sur http://localhost:5173, base locale, comptes `sim-*` créés (`scripts/sim-create-users.ps1`, fichier `tests/.env.qa-sim`).

```
cd web
npx playwright test -c playwright.sim.config.ts            # tout
npx playwright test -c playwright.sim.config.ts 10-croissance   # paliers 5 à 9
```

Sorties : captures dans `docs/guide-utilisateur/captures-sim/`, matrice dans `docs/recette/simulation-200/resultats-playwright.jsonl`, rapport HTML `web/playwright-report-sim`.
Les paliers 1 à 4 (jusqu'à 75 salariés, avril 2026) ont été joués au navigateur intégré. Chaque palier ne crée que les salariés manquants.
Les sélecteurs des pages congés, prêts et sorties restent à écrire après exploration au navigateur.
