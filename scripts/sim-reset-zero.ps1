# Remise a zero de la base de simulation (salaries, paie, comptes) en conservant le referentiel et le compte mdiene.
# Sauvegarde d'abord (scripts/local-backup.ps1). Restauration : scripts/local-restore.ps1.
param([switch]$SansSauvegarde, [string]$Confirmer = '')   # -Confirmer RESET-ZERO : execution sans saisie (Claude Code)
$ErrorActionPreference = 'Stop'
$OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$root = Split-Path $PSScriptRoot -Parent
$ctn = 'soma-rh-local-postgres-1'

$confirmation = $Confirmer
if (-not $confirmation) { $confirmation = Read-Host "Supprimer TOUS les salaries, la paie et les comptes sauf mdiene ? Taper RESET-ZERO pour continuer" }
if ($confirmation -cne 'RESET-ZERO') { throw 'Annule.' }
if (-not $SansSauvegarde) { & "$PSScriptRoot\local-backup.ps1" | Out-Host }

docker cp "$root\tests\fixtures\sim\reset-zero.sql" "${ctn}:/tmp/reset-zero.sql"
if ($LASTEXITCODE -ne 0) { throw 'Copie du script SQL impossible.' }
docker exec $ctn psql -U soma -d soma_rh -v ON_ERROR_STOP=1 -f /tmp/reset-zero.sql
if ($LASTEXITCODE -ne 0) { throw 'La remise a zero a echoue : rien n a ete supprime (transaction annulee).' }
docker exec $ctn psql -U soma -d soma_rh -c "notify pgrst, 'reload schema'" | Out-Null
docker compose restart api | Out-Null
Write-Output 'Remise a zero terminee. Compte mdiene conserve. Etape suivante : scripts\sim-create-users.ps1'
