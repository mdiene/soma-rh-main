# Cree les comptes de simulation (un par role et par profil). L'inscription publique est fermee (D-016) et l'application
# n'a pas de fonction de creation de compte par l'administrateur : les comptes sont crees directement en base.
# Mots de passe jetables generes, ecrits uniquement dans tests/.env.qa-sim (hors Git), jamais affiches.
# -MotDePasseCommun : utilise un seul mot de passe jetable saisi au clavier pour tous les comptes (pratique pour la recette).
param([switch]$MotDePasseCommun)
$ErrorActionPreference = 'Stop'
$OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$root = Split-Path $PSScriptRoot -Parent
$ctn = 'soma-rh-local-postgres-1'; $api = 'soma-rh-local-api-1'

# cle -> roles
$accounts = [ordered]@{
  'admin' = @('admin'); 'admin2' = @('admin')
  'rh' = @('rh'); 'rh2' = @('rh')
  'paie' = @('paie'); 'paie2' = @('paie')
  'rhpaie' = @('rh','paie')
}
1..5 | ForEach-Object { $accounts["mgr-$_"] = @('manager') }
1..8 | ForEach-Object { $accounts["sal-$_"] = @('salarie') }

$common = $null
# Execution sans saisie : variable d'environnement SIM_COMMON_PASSWORD (mot de passe jetable, 8 caracteres minimum), jamais affichee.
if ($env:SIM_COMMON_PASSWORD) {
  if ($env:SIM_COMMON_PASSWORD.Length -lt 8) { throw 'SIM_COMMON_PASSWORD trop court.' }
  $common = $env:SIM_COMMON_PASSWORD
} elseif ($MotDePasseCommun) {
  $s = Read-Host 'Mot de passe jetable commun (8 caracteres minimum)' -AsSecureString
  $common = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($s))
  if ($common.Length -lt 8) { throw 'Mot de passe trop court.' }
}

$sql = New-Object System.Collections.Generic.List[string]
$env = @('# Genere par scripts/sim-create-users.ps1 - ne jamais commiter', 'SIM_API_URL=http://localhost:8000')
$sql.Add("delete from auth.users where email like 'sim-%@example.test';")
foreach ($k in $accounts.Keys) {
  $email = "sim-$k@example.test"
  if ($common) { $pwd = $common } else {
    $b = New-Object byte[] 18; [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($b)
    $pwd = 'Sim' + [Convert]::ToBase64String($b).Replace('/','x').Replace('+','y').Replace('=','z') + '!'
  }
  $hash = docker exec $api node -e "process.stdout.write(require('bcryptjs').hashSync(process.argv[1], 12))" $pwd
  if ($LASTEXITCODE -ne 0 -or -not $hash) { throw 'Hachage du mot de passe impossible (conteneur api demarre ?).' }
  $sql.Add("insert into auth.users (id, email, encrypted_password, email_confirmed_at) values (gen_random_uuid(), '$email', '$hash', now());")
  foreach ($r in $accounts[$k]) { $sql.Add("insert into public.user_roles (user_id, role) select id, '$r' from auth.users where email = '$email' on conflict do nothing;") }
  $env += "SIM_$(($k -replace '-','_').ToUpper())_EMAIL=$email"
  $env += "SIM_$(($k -replace '-','_').ToUpper())_PASSWORD=$pwd"
}
$tmp = Join-Path $env:TEMP 'sim-users.sql'
[IO.File]::WriteAllLines($tmp, $sql, [System.Text.UTF8Encoding]::new($false))
docker cp $tmp "${ctn}:/tmp/sim-users.sql"
docker exec $ctn psql -U soma -d soma_rh -v ON_ERROR_STOP=1 -q -f /tmp/sim-users.sql
if ($LASTEXITCODE -ne 0) { throw 'Creation des comptes echouee.' }
Remove-Item $tmp -Force
[IO.File]::WriteAllLines("$root\tests\.env.qa-sim", $env, [System.Text.UTF8Encoding]::new($false))
Write-Output "Comptes crees : $($accounts.Keys -join ', ') (identifiants dans tests\.env.qa-sim, hors Git)."
