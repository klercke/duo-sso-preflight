$repoRawUrl = "https://raw.githubusercontent.com/klercke/duo-sso-preflight/main/"

$folderName = "duo-sso-prep"
$preflightScript = "duo-sso-preflight.ps1"

$downloadPath = "$PSScriptRoot\$folderName\$preflightScript"

New-Item -ItemType Directory -Path $folderName 

Invoke-WebRequest -Uri "$repoRawUrl/$preflightScript" -OutFile $downloadPath

Write-Output "Duo SSO Preflight downloaded to $downloadPath"
