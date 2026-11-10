<#
Met en ligne l'application web SOMA-RH sur Vercel, branchée sur Supabase (projet mozaic-admin).
Usage (depuis la racine du dépôt) :  .\scripts\vercel-deploy.ps1            # production
                                      .\scripts\vercel-deploy.ps1 -Apercu    # déploiement d'aperçu protégé
Prérequis : Node.js, un compte Vercel. La première exécution ouvre le navigateur pour la connexion (vercel login).
Les deux valeurs ci-dessous sont PUBLIQUES par conception (URL du projet et clé publishable) ; la clé service_role n'est jamais utilisée ici.
#>
param([switch]$Apercu, [string]$Projet = 'soma-rh')
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root
$apiUrl = 'https://mzhdwdpesbggxtjxxgab.supabase.co'
$apiKey = 'sb_publishable_lKM3REhk_3g-nP_LBII7Sw_jwirLd3Z'
$cible = if ($Apercu) { 'preview' } else { 'production' }

Write-Host '1/4 Connexion Vercel...'
$ErrorActionPreference = 'Continue'   # la banniere de la CLI sort sur stderr : ne pas la traiter comme une erreur
npx --yes vercel@latest whoami *> $null
$dejaConnecte = ($LASTEXITCODE -eq 0)
$ErrorActionPreference = 'Stop'
if (-not $dejaConnecte) { npx --yes vercel@latest login; if ($LASTEXITCODE -ne 0) { throw 'Connexion Vercel échouée' } }

Write-Host "2/4 Liaison du projet « $Projet »..."
npx --yes vercel@latest link --yes --project $Projet
if ($LASTEXITCODE -ne 0) { throw 'Liaison échouée' }

Write-Host "3/4 Variables d'environnement ($cible)..."
foreach ($v in @(@('VITE_API_URL', $apiUrl), @('VITE_API_PUBLIC_KEY', $apiKey), @('VITE_DOCUMENTS_MODE', 'supabase'))) {
  $v[1] | npx --yes vercel@latest env add $v[0] $cible --force
  if ($LASTEXITCODE -ne 0) { throw "Variable $($v[0]) non enregistrée" }
}

Write-Host "4/4 Déploiement ($cible)..."
if ($Apercu) { npx --yes vercel@latest deploy } else { npx --yes vercel@latest deploy --prod }
if ($LASTEXITCODE -ne 0) { throw 'Déploiement échoué' }
Write-Host 'Terminé. Ajoutez l''adresse obtenue dans Supabase > Authentication > URL Configuration (Site URL et Redirect URLs).' -ForegroundColor Green
