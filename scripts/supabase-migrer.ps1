<#
Réinitialise le projet Supabase « mozaic-admin » avec le schéma SOMA-RH à jour, puis y migre les données de l'ancienne base.
  .\scripts\supabase-migrer.ps1 -Etape reset   -Sauvegarde backups\supabase-20261109-182227   (DESTRUCTIF : vide le schéma public)
  .\scripts\supabase-migrer.ps1 -Etape donnees -Sauvegarde backups\supabase-20261109-182227   (charge les données depuis les CSV de la sauvegarde)
Le pooler IPv4 est utilisé par défaut. Le mot de passe est saisi à l'écran.
#>
param(
  [Parameter(Mandatory)][ValidateSet('reset','donnees')][string]$Etape,
  [Parameter(Mandatory)][string]$Sauvegarde,
  [string]$ProjectRef = 'mzhdwdpesbggxtjxxgab',
  [string]$DbHost = 'aws-1-eu-west-1.pooler.supabase.com',
  [int]$Port = 5432,
  [string]$Base = 'postgres'
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$bk = (Resolve-Path (Join-Path $root $Sauvegarde)).Path
foreach ($f in 'full.dump','row-counts.csv','SHA256SUMS.txt') { if (-not (Test-Path (Join-Path $bk $f))) { throw "Sauvegarde incomplète : $f manquant" } }
if ($Etape -eq 'reset') {
  Write-Host "ATTENTION : le schéma public du projet $ProjectRef va être SUPPRIMÉ puis rechargé à vide." -ForegroundColor Red
  Write-Host "Sauvegarde vérifiée : $bk"
  $c = Read-Host "Tapez REINITIALISER $ProjectRef pour confirmer"
  if ($c -ne "REINITIALISER $ProjectRef") { throw 'Confirmation incorrecte, abandon.' }
}
$sec = Read-Host "Mot de passe base Supabase ($ProjectRef)" -AsSecureString
$env:PGPASSWORD_SB = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec))
$DbUser = "postgres.$ProjectRef"
Write-Host "Connexion : $DbUser@$DbHost`:$Port/$Base"
docker run --rm -e "PGPASSWORD=$env:PGPASSWORD_SB" -e "PGHOST=$DbHost" -e "PGPORT=$Port" -e "PGUSER=$DbUser" -e "PGDATABASE=$Base" -e "PGSSLMODE=require" `
  -v "${root}:/repo:ro" -v "${bk}:/bk:ro" postgres:17 bash /repo/scripts/supabase-load.sh $Etape
$code = $LASTEXITCODE
Remove-Item Env:PGPASSWORD_SB
if ($code -ne 0) { throw "Echec de l'étape $Etape (code $code). Rien d'autre n'est lancé." }
Write-Host "Etape $Etape terminée." -ForegroundColor Green
