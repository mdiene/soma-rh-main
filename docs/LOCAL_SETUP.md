# SOMA-RH — installation locale

## Prérequis

- Windows PowerShell ;
- Docker Desktop démarré ;
- Node.js et npm ;
- au moins 4 Go disponibles pour les conteneurs et la base.

## Installation initiale

```powershell
Copy-Item .env.docker.example .env
docker compose up -d postgres postgrest api pgadmin
Set-Location web
npm install
npm run build
Set-Location ..
Copy-Item web/.env.example web/.env.local
```

Le fichier `.env` contient des valeurs locales et ne doit pas être commité. En environnement partagé, remplacer `JWT_SECRET` par une valeur aléatoire longue.

## Services

| Service | Adresse |
|---|---|
| Application | http://localhost:5173 |
| API locale | http://localhost:8000 |
| PostgREST | http://localhost:3001 |
| PostgreSQL | localhost:5432 |
| pgAdmin | http://localhost:5051 |

Dans pgAdmin lancé dans Docker, utiliser `postgres` comme hôte, `soma_rh` comme base, `soma` comme utilisateur et la valeur de `POSTGRES_PASSWORD`.

## Contrôle de santé

```powershell
.\scripts\local-health.ps1
```

## Sauvegarde et restauration

Les sauvegardes peuvent contenir des données personnelles et sont exclues de Git.

```powershell
.\scripts\local-backup.ps1
.\scripts\local-restore.ps1 -BackupFile .\backups\soma-rh-AAAAMMJJ-HHmmss.dump
```

La restauration remplace les données de `soma_rh` et demande une confirmation explicite.

## Arrêt et remise à zéro

```powershell
# Arrêt sans supprimer les données
.\scripts\local-reset.ps1

# Suppression complète des volumes après confirmation
.\scripts\local-reset.ps1 -Volumes
```

Le reset complet recrée les services et réapplique les migrations présentes dans l'image PostgreSQL. Il ne recharge pas de données personnelles distantes.

## Contrôles de gouvernance de la paie

```powershell
# Non-régression du moteur (référence locale dans backups/, hors Git)
.\scripts\verify-payroll.ps1          # contrôle ; -Save après une évolution voulue
# Export du journal d'audit hors base + vérification de la chaîne SHA-256
.\scripts\export-audit.ps1
# Tests SQL (annulés à la fin) : attendu « OK audit_chain » et « OK payroll_separation »
Get-Content tests\sql\audit_chain.sql | docker exec -i soma-rh-local-postgres-1 env PGPASSWORD=$env:POSTGRES_PASSWORD psql -U soma -d soma_rh -v ON_ERROR_STOP=1
```

## Régénérer les types web (`web/src/lib/database.types.ts`)

Après toute migration qui crée ou modifie une table, une vue ou une fonction :

```
# 1. Générer vers un dossier temporaire (mot de passe : POSTGRES_PASSWORD du .env)
npx -y supabase@latest gen types typescript --schema public --db-url "postgresql://soma:<mot_de_passe>@localhost:5432/soma_rh?sslmode=disable" > <tmp>/database.types.ts
# 2. Formater comme le fichier du dépôt (sans point-virgule, 80 colonnes)
echo '{"semi": false, "printWidth": 80}' > <tmp>/.oxfmtrc.json ; (cd <tmp> && npx -y oxfmt@latest database.types.ts)
# 3. Rétablir l'en-tête `__InternalSupabase { PostgrestVersion: "14.17" }` juste après « export type Database = { »
# 4. Copier vers web/src/lib/ puis, dans web/ : npx tsc -b ; npm run lint ; npm run build
```
Écart connu avec l'ancien générateur : les arguments facultatifs de RPC sont typés `?: string` (et non `?: string | null`) ; `web/src/lib/api.ts` passe donc `reason ?? undefined` (aucune retouche manuelle du fichier généré).

## Passerelle derrière un proxy (`TRUST_PROXY`)

Le verrou de connexion et les limites par adresse reposent sur l'adresse du client. Derrière un proxy ou un répartiteur de charge, la passerelle ne voit que l'adresse du proxy : tous les utilisateurs partageraient alors la même limite (120 requêtes sensibles par 15 minutes).

- Définir `TRUST_PROXY=1` dans l'environnement de la passerelle : elle lit alors l'entrée de **droite** de `X-Forwarded-For` (celle que le proxy a vue).
- Conditions : **exactement un** proxy devant la passerelle, et la passerelle **non joignable directement** depuis Internet. Sinon l'en-tête est falsifiable et toutes les limites par adresse tombent. Avec deux proxys ou plus, l'entrée de droite est celle du proxy intermédiaire : ne pas activer sans adapter le code.
- Sans cette variable (cas local, Docker sans proxy), l'en-tête est ignoré.
- Le verrou de connexion est stocké en base (table `login_attempts`, migration `20261215100000`) : il survit au redémarrage de la passerelle. Si la base répond mal, la passerelle se replie sur la mémoire et le journal le signale.
