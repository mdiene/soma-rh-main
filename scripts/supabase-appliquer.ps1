<#
Applique UN fichier de migration sur le projet Supabase en ligne, dans une transaction (tout ou rien). Non destructif.
  .\scripts\supabase-appliquer.ps1 -Fichier db\migrations\20261213090000_connexion_telephone.sql
Le mot de passe de la base est saisi à l'écran (jamais écrit sur disque).
#>
param(
  [Parameter(Mandatory)][string]$Fichier,
  [string]$ProjectRef = 'mzhdwdpesbggxtjxxgab',
  [string]$DbHost = 'aws-1-eu-west-1.pooler.supabase.com',
  [int]$Port = 5432
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$f = (Resolve-Path (Join-Path $root $Fichier)).Path
$rel = $f.Substring($root.Length).TrimStart('\') -replace '\\', '/'
$sec = Read-Host "Mot de passe base Supabase ($ProjectRef)" -AsSecureString
$pw = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec))
docker run --rm -e "PGPASSWORD=$pw" -e "PGHOST=$DbHost" -e "PGPORT=$Port" -e "PGUSER=postgres.$ProjectRef" -e "PGDATABASE=postgres" -e "PGSSLMODE=require" `
  -v "${root}:/repo:ro" postgres:17 psql -v ON_ERROR_STOP=1 --single-transaction -f "/repo/$rel"
if ($LASTEXITCODE -ne 0) { throw "Echec (code $LASTEXITCODE) : rien n'a été appliqué." }
Write-Host "Migration appliquée : $Fichier" -ForegroundColor Green
