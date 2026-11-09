# Lance les tests SQL (tests/sql/*.sql) dans le conteneur Postgres, un fichier à la fois, et résume.
# Chaque test s'annule (rollback) ou ne fait que lire : la base n'est pas modifiée.
# Usage : .\scripts\test-sql.ps1            tous les tests
#         .\scripts\test-sql.ps1 audit_*     ceux dont le nom correspond au motif
# Le fichier est transmis par redirection (cmd), pas par un tube PowerShell : sinon les accents sont corrompus (D-009).
param([string]$Filter = '*')
$root = Split-Path $PSScriptRoot -Parent
$files = Get-ChildItem (Join-Path $root "tests\sql\$Filter.sql") | Sort-Object Name
if (-not $files) { Write-Error "Aucun test SQL ne correspond à « $Filter »."; exit 2 }

$failed = @()
foreach ($f in $files) {
  $out = cmd /c "docker exec -i soma-rh-local-postgres-1 psql -U soma -d soma_rh -v ON_ERROR_STOP=1 < `"$($f.FullName)`" 2>&1"
  if ($LASTEXITCODE -eq 0) { Write-Host ("OK     " + $f.Name) }
  else {
    $failed += $f.Name
    Write-Host ("ECHEC  " + $f.Name) -ForegroundColor Red
    $out | Where-Object { $_ -match 'ERROR|DETAIL|HINT|CONTEXT' } | Select-Object -First 4 | ForEach-Object { Write-Host ("         " + $_) -ForegroundColor DarkRed }
  }
}
Write-Host ""
Write-Host ("{0} test(s), {1} échec(s)" -f $files.Count, $failed.Count)
if ($failed.Count) { exit 1 }
