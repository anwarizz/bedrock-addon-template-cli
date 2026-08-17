param(
    [Parameter(Position=0)]
    [string]$Command,

    [Parameter(Position=1)]
    [string]$Extra
)

$scriptDir = $PSScriptRoot
$configPath = Join-Path $scriptDir "config.json"

function Load-Config {
    if (Test-Path $configPath) {
        return Get-Content $configPath -Raw | ConvertFrom-Json
    }
    return $null
}

function Save-Config($config) {
    $config | ConvertTo-Json | Set-Content -Path $configPath
}

# ---- Subcommand: cadon code <path> ----
if ($Command -eq "code") {
    if ([string]::IsNullOrWhiteSpace($Extra)) {
        Write-Host "Usage: cadon code <path-or-command-to-editor>" -ForegroundColor Red
        Write-Host "Example: cadon code code" -ForegroundColor Yellow
        Write-Host "Example: cadon code `"C:\Program Files\Microsoft VS Code\Code.exe`"" -ForegroundColor Yellow
        exit
    }

    $config = Load-Config
    if ($null -eq $config) {
        Write-Host "config.json not found. Run install.bat first on this device." -ForegroundColor Red
        exit
    }

    $config | Add-Member -NotePropertyName "editorCommand" -NotePropertyValue $Extra -Force
    Save-Config $config

    Write-Host "Editor command set to: $Extra" -ForegroundColor Green
    exit
}

# ---- Default: create a new project ----
if (-not (Test-Path $configPath)) {
    Write-Host "config.json not found. Run install.bat first on this device." -ForegroundColor Red
    exit
}

$config = Load-Config
$comMojang = $config.comMojangPath
$editorCommand = $config.editorCommand

$templateRoot = Split-Path $scriptDir -Parent
$templateRP = Join-Path $templateRoot "RP"
$templateBP = Join-Path $templateRoot "BP"

$projectName = $Command
if ([string]::IsNullOrWhiteSpace($projectName)) {
    $projectName = Read-Host "Enter project name"
}

if ([string]::IsNullOrWhiteSpace($projectName)) {
    Write-Host "Project name cannot be empty." -ForegroundColor Red
    exit
}

$fullCopy = ($Extra -eq "*")

$safeName = $projectName -replace '[\\/:*?"<>|]', ''

$destRP = Join-Path $comMojang "development_resource_packs\$safeName RP"
$destBP = Join-Path $comMojang "development_behavior_packs\$safeName BP"

if ((Test-Path $destRP) -or (Test-Path $destBP)) {
    Write-Host "A project folder with this name already exists. Aborting." -ForegroundColor Red
    exit
}

function Copy-MinimalPack($templateFolder, $destFolder, $includeScripts) {
    New-Item -ItemType Directory -Force -Path $destFolder | Out-Null

    $manifestPath = Join-Path $templateFolder "manifest.json"
    if (Test-Path $manifestPath) {
        Copy-Item -Path $manifestPath -Destination $destFolder
    } else {
        Write-Host "  Warning: manifest.json not found in $templateFolder" -ForegroundColor Yellow
    }

    $iconPath = Join-Path $templateFolder "pack_icon.png"
    if (Test-Path $iconPath) {
        Copy-Item -Path $iconPath -Destination $destFolder
    }

    if ($includeScripts) {
        $scriptsPath = Join-Path $templateFolder "scripts"
        if (Test-Path $scriptsPath) {
            Copy-Item -Path $scriptsPath -Destination (Join-Path $destFolder "scripts") -Recurse
        }
    }
}

if ($fullCopy) {
    Write-Host "Copying full template (all folders)..." -ForegroundColor Cyan
    Copy-Item -Path $templateRP -Destination $destRP -Recurse
    Copy-Item -Path $templateBP -Destination $destBP -Recurse
} else {
    Write-Host "Copying minimal template (manifest, scripts, pack_icon only)..." -ForegroundColor Cyan
    Copy-MinimalPack $templateRP $destRP $false
    Copy-MinimalPack $templateBP $destBP $true
}

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

# ---- Create VS Code workspace file ----
$projectsDir = Join-Path $templateRoot "Projects"
New-Item -ItemType Directory -Force -Path $projectsDir | Out-Null

$workspacePath = Join-Path $projectsDir "$safeName.code-workspace"
$workspaceObject = @{
    folders = @(
        @{ path = $destRP },
        @{ path = $destBP }
    )
    settings = @{}
}
$workspaceContent = $workspaceObject | ConvertTo-Json -Depth 5
Set-Content -Path $workspacePath -Value $workspaceContent

Write-Host ""
Write-Host "Done! Project '$projectName' has been created:" -ForegroundColor Green
Write-Host "  RP: $destRP"
Write-Host "  BP: $destBP"
Write-Host "  Workspace: $workspacePath"
if (-not $fullCopy) {
    Write-Host "  (Minimal copy - use 'cadon $projectName *' next time for the full template)" -ForegroundColor DarkGray
}

# ---- Open in editor if configured ----
if (-not [string]::IsNullOrWhiteSpace($editorCommand)) {
    Write-Host "Opening workspace in editor..." -ForegroundColor Cyan
    try {
        Start-Process -FilePath $editorCommand -ArgumentList "`"$workspacePath`""
    } catch {
        Write-Host "Could not launch editor with command: $editorCommand" -ForegroundColor Red
        Write-Host "You can open the workspace manually: $workspacePath" -ForegroundColor Yellow
    }
}