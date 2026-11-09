# Prompt — Navigation à double colonne (rail + volet), recherche rapide et mouvement

Version alignée sur l'existant du dépôt (09/11/2026). Elle remplace le prompt générique reçu : elle part de ce qui est déjà construit et ne le recrée pas.

## 0. Contexte à respecter (non négociable)

- **Pile réelle** : React 18, Vite, TypeScript, Tailwind, lucide-react, TanStack Query, React Router. Ni Shadcn ni Radix dans le projet : on n'en ajoute pas. **Seule dépendance nouvelle autorisée : `framer-motion`.**
- **Source unique du menu** : `web/src/lib/nav.ts` (`SPACES`, `visibleItems`, `matches`, `rolesFor`). On la **réutilise telle quelle** : mêmes six espaces, mêmes libellés, mêmes routes, mêmes rôles. Aucune seconde arborescence, aucun nouveau type `UserRole`.
- **Rôles réels** : `salarie`, `manager`, `rh`, `paie`, `admin` (`admin` passe partout via `can()`). Le menu n'est qu'un confort : la sécurité réelle reste le RLS en base.
- **À conserver** : épinglé « Tableau de bord » en tête et non retirable ; favoris (4 maximum, table `user_preferences`, `usePreferences`) ; badges dynamiques (`demandes`, `validations`, rafraîchis toutes les 2 minutes) ; mode réduit mémorisé (`localStorage` `nav-rail`) avec panneau flottant ; recherche rapide Ctrl+K / Cmd+K ; liste plate pour un utilisateur qui n'a qu'un espace (salarié) ; barre mobile avec tiroir.
- **Design** : palette `ink / paper / river / phosphate / signal` (`tailwind.config.js`), police Archivo, chiffres tabulaires. Français partout.
- **Accessibilité** (WCAG A/AA, `a11y.spec.ts`) : un seul `nav` nommé « Navigation principale » ; boutons de pôle avec `aria-expanded` ; `inert` sur ce qui est caché ; focus visible ; `prefers-reduced-motion` respecté (`MotionConfig reducedMotion="user"`).

## 1. Ce que l'on construit

### Colonne 1 — le rail (4,5 rem ≈ 72 px, toujours visible sur bureau)
- Logo SOMA-RH en haut ; juste dessous, **Tableau de bord** épinglé (icône seule, nom accessible).
- Une icône par espace autorisé (les six, filtrés par `visibleItems`), avec infobulle au survol **et** au focus clavier, badge cumulé des compteurs de l'espace, indicateur d'espace actif qui coulisse (`layoutId="activePillarIndicator"`).
- En bas : avatar (initiales de l'e-mail), rôles de l'utilisateur **en lecture seule**, déconnexion.
- **Écart assumé avec le prompt d'origine** : pas de « sélecteur de rôle » qui change de profil. Les droits viennent du serveur ; un sélecteur d'interface ferait croire à un changement de droits qui n'existe pas.
- Un utilisateur qui n'a qu'un seul espace n'a pas de rail : le volet affiche directement ses pages.

### Colonne 2 — le volet (13,75 rem ≈ 220 px, repliable)
- En-tête : nom de l'espace actif et déclencheur de la recherche (« Rechercher » + `Ctrl K`).
- Section « Favoris » (étoile au survol, comme aujourd'hui), puis « Pages de l'espace » avec badges (`default` = à traiter, `warning` = validations en attente).
- Bouton « Réduire le menu » / « Développer le menu » (noms accessibles inchangés).
- Replié : seul le rail reste ; un clic sur une icône ouvre le **panneau flottant** (`role="group"`, nom = libellé de l'espace) à côté du rail, Échap le ferme.

### Recherche rapide (existante, à enrichir)
- Conserver le composant `CommandPalette` : dialogue « Recherche rapide », champ en `combobox`, flèches / Entrée / Échap, recherche sans accents sur libellé + espace + mots-clés, entrées déjà filtrées par rôle.
- Ajouter : résultats **groupés par espace** avec titre de groupe, et rappel des touches (`↑↓` naviguer, `↵` ouvrir, `Esc` fermer) en pied de dialogue.

## 2. Mouvement (Framer Motion)

| Élément | Comportement |
|---|---|
| Changement d'espace (volet) | `AnimatePresence mode="wait"` : fondu + glissement `x: -8 → 0`, 150–200 ms |
| Repli / dépli du volet | largeur `0 ↔ 220 px`, courbe `[0.16, 1, 0.3, 1]`, `overflow-hidden` ; l'état replié est `inert` |
| Panneau flottant (mode réduit) | `scale 0.95 → 1` + `opacity 0 → 1`, ressort amorti |
| Recherche rapide | voile en fondu ; fenêtre `scale 0.96 → 1`, `y -10 → 0`, ressort amorti ; sortie animée (`AnimatePresence`) ; filtrage de liste avec `layout` |
| Boutons du rail | `whileHover scale 1.03`, `whileTap scale 0.97` |
| Indicateur actif | `layoutId="activePillarIndicator"` |

Contraintes : aucun mouvement ne retarde la navigation clavier ; avec « réduire les animations » activé dans le système, tout devient instantané.

## 3. Critères d'acceptation

1. `npm run check` et `npm run build` sans erreur.
2. `menu.spec.ts` et `a11y.spec.ts` verts (un fichier à la fois). Les tests décrivant l'ancien accordéon sont **réécrits** pour le rail + volet, pas supprimés.
3. Chaque rôle voit exactement les mêmes pages qu'avant (comparer à `nav.ts`) ; salarié : liste plate, aucun espace de gestion.
4. Aucune régression des favoris, des badges, de la mémorisation du mode réduit.
5. Ne modifier ni `nav.ts` ni les gardes de route ; si une page doit changer de place, c'est un autre travail.
6. Rapport court : fichiers touchés, ce qui a été vérifié, ce qui ne l'a pas été.
