param(
    [string]$ProjectName
)

$scriptDir = $PSScriptRoot
$configPath = Join-Path $scriptDir "config.json"

if (-not (Test-Path $configPath)) {
    Write-Host "config.json not found. Run install.bat first on this device." -ForegroundColor Red
    exit
}

$config = Get-Content $configPath -Raw | ConvertFrom-Json
$comMojang = $config.comMojangPath

$templateRoot = Split-Path $scriptDir -Parent
$templateRP = Join-Path $templateRoot "RP"
$templateBP = Join-Path $templateRoot "BP"

if ([string]::IsNullOrWhiteSpace($ProjectName)) {
    $ProjectName = Read-Host "Enter project name"
}

$projectName = $ProjectName

if ([string]::IsNullOrWhiteSpace($projectName)) {
    Write-Host "Project name cannot be empty." -ForegroundColor Red
    exit
}

$safeName = $projectName -replace '[\\/:*?"<>|]', ''

$destRP = Join-Path $comMojang "development_resource_packs\$safeName RP"
$destBP = Join-Path $comMojang "development_behavior_packs\$safeName BP"

if ((Test-Path $destRP) -or (Test-Path $destBP)) {
    Write-Host "A project folder with this name already exists. Aborting." -ForegroundColor Red
    exit
}

Write-Host "Copying template..." -ForegroundColor Cyan
Copy-Item -Path $templateRP -Destination $destRP -Recurse
Copy-Item -Path $templateBP -Destination $destBP -Recurse

$rpHeaderUuid = [guid]::NewGuid().ToString()
$rpModuleUuid = [guid]::NewGuid().ToString()
$bpHeaderUuid = [guid]::NewGuid().ToString()
$bpModuleUuid = [guid]::NewGuid().ToString()
$bpScriptModuleUuid = [guid]::NewGuid().ToString()

function Update-Manifest($path) {
    $content = Get-Content -Path $path -Raw
    $content = $content -replace '\{\{PROJECT_NAME\}\}', $projectName
    $content = $content -replace '\{\{RP_HEADER_UUID\}\}', $rpHeaderUuid
    $content = $content -replace '\{\{RP_MODULE_UUID\}\}', $rpModuleUuid
    $content = $content -replace '\{\{BP_HEADER_UUID\}\}', $bpHeaderUuid
    $content = $content -replace '\{\{BP_MODULE_UUID\}\}', $bpModuleUuid
    $content = $content -replace '\{\{BP_SCRIPT_MODULE_UUID\}\}', $bpScriptModuleUuid
    Set-Content -Path $path -Value $content -NoNewline
}

Write-Host "Updating manifest & UUIDs..." -ForegroundColor Cyan
Update-Manifest (Join-Path $destRP "manifest.json")
Update-Manifest (Join-Path $destBP "manifest.json")

Write-Host ""
Write-Host "Done! Project '$projectName' has been created:" -ForegroundColor Green
Write-Host "  RP: $destRP"
Write-Host "  BP: $destBP"