<#
Sauvegarde complète du projet Supabase « mozaic-admin » (ancienne base SOMA-RH) avant réinitialisation.
Produit dans backups\supabase-<date>\ :
  - full.dump          pg_dump format custom (schémas public, auth, storage, supabase_migrations, vault)
  - schema.sql         schéma seul (lisible)
  - data-public.sql    données du schéma public en INSERT (relisible, migrable)
  - csv\<table>.csv    chaque table du schéma public + auth.users (export de contrôle)
  - row-counts.csv     nombre de lignes par table (à comparer avec l'étape de migration)
  - SHA256SUMS.txt     empreintes des fichiers
Usage :  .\scripts\supabase-backup.ps1
Le mot de passe de la base est saisi à l'écran (Supabase > Project Settings > Database). Rien n'est écrit sur disque.
Si l'hôte direct est injoignable (IPv6), passer le pooler :
  .\scripts\supabase-backup.ps1 -DbHost aws-0-eu-west-1.pooler.supabase.com -DbUser postgres.mzhdwdpesbggxtjxxgab -Port 5432
#>
param(
  [string]$ProjectRef = 'mzhdwdpesbggxtjxxgab',
  [string]$DbHost = "db.$ProjectRef.supabase.co",
  [string]$DbUser = 'postgres',
  [int]$Port = 5432,
  [string]$Db = 'postgres'
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$out = Join-Path $root "backups\supabase-$stamp"
New-Item -ItemType Directory -Force -Path (Join-Path $out 'csv') | Out-Null

$sec = Read-Host "Mot de passe base Supabase ($ProjectRef)" -AsSecureString
$pwd = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec))
$env:PGPASSWORD_SB = $pwd

function Run-Pg([string]$cmd) {
  docker run --rm -e "PGPASSWORD=$env:PGPASSWORD_SB" -e "PGHOST=$DbHost" -e "PGPORT=$Port" -e "PGUSER=$DbUser" -e "PGDATABASE=$Db" -e "PGSSLMODE=require" -v "${out}:/out" postgres:17 bash -c $cmd
  if ($LASTEXITCODE -ne 0) { throw "Echec : $cmd" }
}

Write-Host "Connexion : $DbUser@$DbHost`:$Port/$Db"
Write-Host '1/5 pg_dump complet (format custom)...'
Run-Pg 'pg_dump -Fc --no-owner --schema=public --schema=auth --schema=storage --schema=supabase_migrations --schema=vault -f /out/full.dump'
Write-Host '2/5 schema seul...'
Run-Pg 'pg_dump --schema-only --no-owner --schema=public -f /out/schema.sql'
Write-Host '3/5 donnees public en INSERT...'
Run-Pg 'pg_dump --data-only --column-inserts --no-owner --schema=public -f /out/data-public.sql'
Write-Host '4/5 CSV par table + comptages...'
$script = @'
set -e
psql -At -c "select table_name from information_schema.tables where table_schema='public' and table_type='BASE TABLE' order by 1" > /tmp/tables.txt
echo "table,lignes" > /out/row-counts.csv
while read t; do
  psql -c "\copy (select * from public.\"$t\") to '/out/csv/$t.csv' csv header"
  n=$(psql -At -c "select count(*) from public.\"$t\"")
  echo "public.$t,$n" >> /out/row-counts.csv
done < /tmp/tables.txt
psql -c "\copy (select id,email,created_at,last_sign_in_at from auth.users) to '/out/csv/auth_users.csv' csv header"
echo "auth.users,$(psql -At -c 'select count(*) from auth.users')" >> /out/row-counts.csv
'@
$script = $script -replace "`r",""
[IO.File]::WriteAllText((Join-Path $out 'export.sh'), $script)
Run-Pg 'bash /out/export.sh'
Remove-Item (Join-Path $out 'export.sh')
Write-Host '5/5 empreintes...'
Get-ChildItem $out -Recurse -File | Get-FileHash -Algorithm SHA256 | ForEach-Object { "$($_.Hash)  $($_.Path.Replace($out,'.'))" } | Set-Content (Join-Path $out 'SHA256SUMS.txt')
Remove-Item Env:PGPASSWORD_SB
Write-Host "Sauvegarde terminee : $out"
Get-Content (Join-Path $out 'row-counts.csv')
