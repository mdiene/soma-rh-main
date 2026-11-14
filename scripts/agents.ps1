<#
.SYNOPSIS
  Lance et reprend les agents nommés de SOMA-RH (Claude Code), chacun dans une session nommée.

.DESCRIPTION
  Nom de session = soma-<agent>-<lot>   (ex. soma-codage-rpr11)
  Les agents sont définis dans .claude/agents/soma-*.md.
  Le registre des sessions est tenu dans docs/agents/sessions.csv (date, session, agent, lot, branche).

.EXAMPLE
  .\scripts\agents.ps1 installer      # copie docs/agents/definitions/*.md vers .claude/agents/ (à refaire après chaque modification)
  .\scripts\agents.ps1 liste
  .\scripts\agents.ps1 lancer controle audit-1114 -Consigne "Lis docs/audit/PLAN_DE_TRAVAIL_AGENTS.md et ouvre les fiches d'ordre du lot P1"
  .\scripts\agents.ps1 lancer codage rpr11 -Fenetre        # nouvelle fenêtre, pour travailler en parallèle
  .\scripts\agents.ps1 reprendre codage rpr11
  .\scripts\agents.ps1 bifurquer codage rpr11              # repart de la session sans la modifier
  .\scripts\agents.ps1 tableau                             # vue « claude agents » (sessions en cours)
#>
param(
  [Parameter(Position = 0)]
  [ValidateSet('installer', 'liste', 'lancer', 'reprendre', 'bifurquer', 'tableau', 'aide')]
  [string]$Action = 'aide',

  [Parameter(Position = 1)]
  [ValidateSet('controle', 'codage', 'base', 'tests', 'design', 'securite', 'doc', 'recherche')]
  [string]$Agent,

  [Parameter(Position = 2)]
  [ValidatePattern('^[a-z0-9][a-z0-9-]{0,40}$')]
  [string]$Lot,

  [string]$Consigne = '',
  [switch]$Fenetre
)

$ErrorActionPreference = 'Stop'
$Racine = Split-Path -Parent $PSScriptRoot
Set-Location $Racine
$Registre = Join-Path $Racine 'docs/agents/sessions.csv'

$Sources = Join-Path $Racine 'docs/agents/definitions'
$Cible = Join-Path $Racine '.claude/agents'

function Install-Agents {
  if (-not (Test-Path $Sources)) { throw "Dossier introuvable : $Sources" }
  New-Item -ItemType Directory -Force -Path $Cible | Out-Null
  Get-ChildItem (Join-Path $Sources 'soma-*.md') | ForEach-Object {
    Copy-Item $_.FullName (Join-Path $Cible $_.Name) -Force
    Write-Host "installé : .claude/agents/$($_.Name)"
  }
}

function Assert-Agent { param($a)
  if (-not (Test-Path (Join-Path $Cible "soma-$a.md"))) {
    Write-Host "Agent soma-$a absent de .claude/agents : installation." -ForegroundColor Yellow
    Install-Agents
  }
}

function Get-NomSession { param($a, $l) "soma-$a-$l" }

function Test-Claude {
  if (-not (Get-Command claude -ErrorAction SilentlyContinue)) {
    throw "La commande 'claude' est introuvable. Installez Claude Code ou ouvrez un terminal où elle est disponible."
  }
}

function Test-OptionNom {
  # Les versions anciennes de Claude Code n'ont pas --name : on le détecte une fois.
  $aide = (& claude --help 2>&1 | Out-String)
  return ($aide -match '--name')
}

function Add-Registre { param($session, $a, $l)
  $branche = (& git branch --show-current 2>$null)
  if (-not (Test-Path $Registre)) {
    New-Item -ItemType Directory -Force -Path (Split-Path $Registre) | Out-Null
    'date;session;agent;lot;branche' | Set-Content -Path $Registre -Encoding UTF8
  }
  "$(Get-Date -Format 'yyyy-MM-dd HH:mm');$session;soma-$a;$l;$branche" | Add-Content -Path $Registre -Encoding UTF8
}

function Start-Commande { param([string[]]$ArgsClaude, [string]$Titre)
  if ($Fenetre) {
    $ligne = 'claude ' + (($ArgsClaude | ForEach-Object { "'" + ($_ -replace "'", "''") + "'" }) -join ' ')
    if (Get-Command wt -ErrorAction SilentlyContinue) {
      Start-Process wt -ArgumentList @('-w', '0', 'nt', '--title', $Titre, '-d', $Racine, 'powershell', '-NoExit', '-Command', $ligne)
    } else {
      Start-Process powershell -WorkingDirectory $Racine -ArgumentList @('-NoExit', '-Command', $ligne)
    }
    Write-Host "Session '$Titre' ouverte dans une nouvelle fenêtre."
  } else {
    & claude @ArgsClaude
  }
}

switch ($Action) {
  'aide' { Get-Help $PSCommandPath -Detailed; break }

  'installer' { Install-Agents; break }

  'liste' {
    Write-Host "`nAgents disponibles (.claude/agents) :" -ForegroundColor Cyan
    if (-not (Test-Path $Cible)) { Write-Warning "Agents non installés : lancez  .\scripts\agents.ps1 installer"; break }
    Get-ChildItem (Join-Path $Cible 'soma-*.md') | ForEach-Object {
      $desc = (Select-String -Path $_.FullName -Pattern '^description:\s*(.+)$' | Select-Object -First 1).Matches.Groups[1].Value
      '{0,-16} {1}' -f $_.BaseName, ($desc.Substring(0, [Math]::Min(110, $desc.Length)))
    }
    if (Test-Path $Registre) {
      Write-Host "`nSessions enregistrées (docs/agents/sessions.csv) :" -ForegroundColor Cyan
      Import-Csv $Registre -Delimiter ';' | Format-Table -AutoSize
    } else { Write-Host "`nAucune session enregistrée pour l'instant." }
    break
  }

  'tableau' { Test-Claude; & claude agents; break }

  'lancer' {
    if (-not $Agent -or -not $Lot) { throw "Usage : .\scripts\agents.ps1 lancer <agent> <lot> [-Consigne '...'] [-Fenetre]" }
    Test-Claude
    Assert-Agent $Agent
    $session = Get-NomSession $Agent $Lot
    $argsClaude = @('--agent', "soma-$Agent")
    if (Test-OptionNom) { $argsClaude += @('--name', $session) }
    else { Write-Warning "Votre Claude Code n'a pas l'option --name : tapez  /rename $session  dès l'ouverture de la session." }
    if ($Consigne) { $argsClaude += $Consigne }
    Add-Registre $session $Agent $Lot
    Start-Commande -ArgsClaude $argsClaude -Titre $session
    break
  }

  'reprendre' {
    if (-not $Agent -or -not $Lot) { throw "Usage : .\scripts\agents.ps1 reprendre <agent> <lot>" }
    Test-Claude
    Assert-Agent $Agent
    $session = Get-NomSession $Agent $Lot
    # --agent est repris : la session garde le rôle et les consignes de l'agent.
    Start-Commande -ArgsClaude @('--agent', "soma-$Agent", '--resume', $session) -Titre $session
    break
  }

  'bifurquer' {
    if (-not $Agent -or -not $Lot) { throw "Usage : .\scripts\agents.ps1 bifurquer <agent> <lot>" }
    Test-Claude
    Assert-Agent $Agent
    $session = Get-NomSession $Agent $Lot
    Start-Commande -ArgsClaude @('--agent', "soma-$Agent", '--resume', $session, '--fork-session') -Titre "$session-bis"
    break
  }
}
