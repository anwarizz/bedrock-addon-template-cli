param(
    [Parameter(Position=0)]
    [string]$Command,

    [Parameter(Position=1)]
    [string]$Extra,

    [Parameter(Position=2)]
    [string]$Extra2
)

$scriptDir = $PSScriptRoot
$configPath = Join-Path $scriptDir "config.json"
$templateRoot = Split-Path $scriptDir -Parent

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

if (-not (Test-Path $configPath)) {
    Write-Host "config.json not found. Run install.bat first on this device." -ForegroundColor Red
    exit
}

$config = Load-Config
$comMojang = $config.comMojangPath
$editorCommand = $config.editorCommand

# ---- Subcommand: cadon entity ----
if ($Command -eq "entity") {
    $currentDir = (Get-Location).Path
    $manifestPath = Join-Path $currentDir "manifest.json"

    if (-not (Test-Path $manifestPath)) {
        Write-Host "No manifest.json found in the current directory." -ForegroundColor Red
        Write-Host "Run 'cadon entity' from inside your project's RP or BP folder." -ForegroundColor Yellow
        exit
    }

    $manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json
    $packType = $null
    foreach ($module in $manifest.modules) {
        if ($module.type -eq "resources") { $packType = "RP" }
        if ($module.type -eq "data" -or $module.type -eq "script") { $packType = "BP" }
    }

    if ($null -eq $packType) {
        Write-Host "Could not determine pack type from manifest.json." -ForegroundColor Red
        exit
    }

    $folderName = Split-Path $currentDir -Leaf

    if ($packType -eq "RP") {
        if ($folderName -notmatch "^(.+) RP$") {
            Write-Host "Could not determine project name from folder: $folderName" -ForegroundColor Red
            exit
        }
    } else {
        if ($folderName -notmatch "^(.+) BP$") {
            Write-Host "Could not determine project name from folder: $folderName" -ForegroundColor Red
            exit
        }
    }
    $baseName = $Matches[1]

    $rpPath = Join-Path $comMojang "development_resource_packs\$baseName RP"
    $bpPath = Join-Path $comMojang "development_behavior_packs\$baseName BP"

    if (-not (Test-Path $rpPath) -or -not (Test-Path $bpPath)) {
        Write-Host "Could not locate both RP and BP folders for project '$baseName'." -ForegroundColor Red
        Write-Host "  RP: $rpPath" -ForegroundColor Yellow
        Write-Host "  BP: $bpPath" -ForegroundColor Yellow
        exit
    }

    Write-Host "Project detected: $baseName" -ForegroundColor Green

    $displayName = Read-Host "Enter display name (e.g. Baboon)"
    if ([string]::IsNullOrWhiteSpace($displayName)) {
        Write-Host "Display name cannot be empty." -ForegroundColor Red
        exit
    }

    $identifier = Read-Host "Enter identifier (e.g. myaddon:baboon)"
    if ($identifier -notmatch "^[a-z0-9_]+:[a-z0-9_]+$") {
        Write-Host "Identifier must be in the format namespace:name (lowercase letters, numbers, underscores only)." -ForegroundColor Red
        exit
    }

    $entityShortName = $identifier.Split(":")[1]

    $assetsDir = Join-Path $templateRoot "assets\entity"
    if (-not (Test-Path $assetsDir)) {
        Write-Host "Assets folder not found: $assetsDir" -ForegroundColor Red
        exit
    }

    function Replace-Placeholders($text) {
        $text = $text -replace '\{\{IDENTIFIER\}\}', $identifier
        $text = $text -replace '\{\{DISPLAY_NAME\}\}', $displayName
        $text = $text -replace '\{\{ENTITY_SHORT_NAME\}\}', $entityShortName
        return $text
    }

    function Copy-WithReplace($sourceFile, $destFile) {
        $content = Get-Content -Path $sourceFile -Raw
        $content = Replace-Placeholders $content
        Set-Content -Path $destFile -Value $content -NoNewline
    }

    Write-Host "Creating entity files..." -ForegroundColor Cyan

    $bpEntitiesDir = Join-Path $bpPath "entities"
    New-Item -ItemType Directory -Force -Path $bpEntitiesDir | Out-Null
    Copy-WithReplace (Join-Path $assetsDir "cadon.behavior.json") (Join-Path $bpEntitiesDir "$entityShortName.behavior.json")

    $rpEntityDir = Join-Path $rpPath "entity"
    New-Item -ItemType Directory -Force -Path $rpEntityDir | Out-Null
    Copy-WithReplace (Join-Path $assetsDir "cadon.entity.json") (Join-Path $rpEntityDir "$entityShortName.entity.json")

    $rpModelsDir = Join-Path $rpPath "models\entity"
    New-Item -ItemType Directory -Force -Path $rpModelsDir | Out-Null
    Copy-WithReplace (Join-Path $assetsDir "cadon.geo.json") (Join-Path $rpModelsDir "$entityShortName.geo.json")

    $rpTexturesDir = Join-Path $rpPath "textures\entity"
    New-Item -ItemType Directory -Force -Path $rpTexturesDir | Out-Null
    Copy-Item -Path (Join-Path $assetsDir "cadon.png") -Destination (Join-Path $rpTexturesDir "$entityShortName.png")

    # ---- en_US.lang: create if missing, merge (no overwrite) if it exists ----
    $rpTextsDir = Join-Path $rpPath "texts"
    New-Item -ItemType Directory -Force -Path $rpTextsDir | Out-Null
    $destLang = Join-Path $rpTextsDir "en_US.lang"

    $sourceLangContent = Get-Content -Path (Join-Path $assetsDir "en_US.lang") -Raw
    $sourceLangContent = Replace-Placeholders $sourceLangContent
    $newLines = $sourceLangContent -split "`r?`n" | Where-Object { $_.Trim() -ne "" }

    if (-not (Test-Path $destLang)) {
        Set-Content -Path $destLang -Value ($newLines -join "`r`n")
    } else {
        $existingLines = Get-Content -Path $destLang
        $existingKeys = $existingLines | ForEach-Object {
            if ($_ -match "^([^=]+)=") { $Matches[1] }
        }
        $linesToAdd = @()
        foreach ($line in $newLines) {
            if ($line -match "^([^=]+)=") {
                if ($existingKeys -notcontains $Matches[1]) {
                    $linesToAdd += $line
                }
            }
        }
        if ($linesToAdd.Count -gt 0) {
            Add-Content -Path $destLang -Value $linesToAdd
        }
    }

    # ---- sounds.json: create if missing, merge top-level keys (no overwrite) if it exists ----
    $destSounds = Join-Path $rpPath "sounds.json"
    $sourceSoundsContent = Get-Content -Path (Join-Path $assetsDir "sounds.json") -Raw
    $sourceSoundsContent = Replace-Placeholders $sourceSoundsContent
    $sourceSoundsObj = $sourceSoundsContent | ConvertFrom-Json

    if (-not (Test-Path $destSounds)) {
        Set-Content -Path $destSounds -Value $sourceSoundsContent
    } else {
        $existingSoundsObj = Get-Content -Path $destSounds -Raw | ConvertFrom-Json
        $existingHash = @{}
        $existingSoundsObj.PSObject.Properties | ForEach-Object { $existingHash[$_.Name] = $_.Value }

        $sourceSoundsObj.PSObject.Properties | ForEach-Object {
            if (-not $existingHash.ContainsKey($_.Name)) {
                $existingHash[$_.Name] = $_.Value
            }
        }

        $mergedJson = $existingHash | ConvertTo-Json -Depth 10
        Set-Content -Path $destSounds -Value $mergedJson
    }

    Write-Host ""
    Write-Host "Entity '$displayName' ($identifier) added to project '$baseName'." -ForegroundColor Green
    Write-Host "  $bpEntitiesDir\$entityShortName.behavior.json"
    Write-Host "  $rpEntityDir\$entityShortName.entity.json"
    Write-Host "  $rpModelsDir\$entityShortName.geo.json"
    Write-Host "  $rpTexturesDir\$entityShortName.png"
    Write-Host "  $destLang (merged)"
    Write-Host "  $destSounds (merged)"

    exit
}

# ---- Subcommand: cadon item ----
if ($Command -eq "item") {
    $currentDir = (Get-Location).Path
    $manifestPath = Join-Path $currentDir "manifest.json"

    if (-not (Test-Path $manifestPath)) {
        Write-Host "No manifest.json found in the current directory." -ForegroundColor Red
        Write-Host "Run 'cadon item' from inside your project's RP or BP folder." -ForegroundColor Yellow
        exit
    }

    $manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json
    $packType = $null
    foreach ($module in $manifest.modules) {
        if ($module.type -eq "resources") { $packType = "RP" }
        if ($module.type -eq "data" -or $module.type -eq "script") { $packType = "BP" }
    }

    if ($null -eq $packType) {
        Write-Host "Could not determine pack type from manifest.json." -ForegroundColor Red
        exit
    }

    $folderName = Split-Path $currentDir -Leaf

    if ($packType -eq "RP") {
        if ($folderName -notmatch "^(.+) RP$") {
            Write-Host "Could not determine project name from folder: $folderName" -ForegroundColor Red
            exit
        }
    } else {
        if ($folderName -notmatch "^(.+) BP$") {
            Write-Host "Could not determine project name from folder: $folderName" -ForegroundColor Red
            exit
        }
    }
    $baseName = $Matches[1]

    $rpPath = Join-Path $comMojang "development_resource_packs\$baseName RP"
    $bpPath = Join-Path $comMojang "development_behavior_packs\$baseName BP"

    if (-not (Test-Path $rpPath) -or -not (Test-Path $bpPath)) {
        Write-Host "Could not locate both RP and BP folders for project '$baseName'." -ForegroundColor Red
        exit
    }

    Write-Host "Project detected: $baseName" -ForegroundColor Green

    $displayName = Read-Host "Enter display name (e.g. Cool Ore)"
    if ([string]::IsNullOrWhiteSpace($displayName)) {
        Write-Host "Display name cannot be empty." -ForegroundColor Red
        exit
    }

    $identifier = Read-Host "Enter identifier (e.g. myaddon:cool_ore)"
    if ($identifier -notmatch "^[a-z0-9_]+:[a-z0-9_]+$") {
        Write-Host "Identifier must be in the format namespace:name (lowercase letters, numbers, underscores only)." -ForegroundColor Red
        exit
    }

    $itemShortName = $identifier.Split(":")[1]

    $assetsDir = Join-Path $templateRoot "assets\items"
    if (-not (Test-Path $assetsDir)) {
        Write-Host "Assets folder not found: $assetsDir" -ForegroundColor Red
        exit
    }

    function Replace-ItemPlaceholders($text) {
        $text = $text -replace '\{\{IDENTIFIER\}\}', $identifier
        $text = $text -replace '\{\{DISPLAY_NAME\}\}', $displayName
        $text = $text -replace '\{\{ITEM_SHORT_NAME\}\}', $itemShortName
        return $text
    }

    Write-Host "Creating item files..." -ForegroundColor Cyan

    # ---- cadon.item.json -> BP/items/<name>.json ----
    $bpItemsDir = Join-Path $bpPath "items"
    New-Item -ItemType Directory -Force -Path $bpItemsDir | Out-Null
    $itemJsonContent = Get-Content -Path (Join-Path $assetsDir "cadon.item.json") -Raw
    $itemJsonContent = Replace-ItemPlaceholders $itemJsonContent
    Set-Content -Path (Join-Path $bpItemsDir "$itemShortName.json") -Value $itemJsonContent -NoNewline

    # ---- cadon.png -> RP/textures/items/<name>.png ----
    $rpItemTexturesDir = Join-Path $rpPath "textures\items"
    New-Item -ItemType Directory -Force -Path $rpItemTexturesDir | Out-Null
    Copy-Item -Path (Join-Path $assetsDir "cadon.png") -Destination (Join-Path $rpItemTexturesDir "$itemShortName.png")

    # ---- en_US.lang: create if missing, merge (no overwrite) if it exists ----
    $rpTextsDir = Join-Path $rpPath "texts"
    New-Item -ItemType Directory -Force -Path $rpTextsDir | Out-Null
    $destLang = Join-Path $rpTextsDir "en_US.lang"

    $sourceLangContent = Get-Content -Path (Join-Path $assetsDir "en_US.lang") -Raw
    $sourceLangContent = Replace-ItemPlaceholders $sourceLangContent
    $newLines = $sourceLangContent -split "`r?`n" | Where-Object { $_.Trim() -ne "" }

    if (-not (Test-Path $destLang)) {
        Set-Content -Path $destLang -Value ($newLines -join "`r`n")
    } else {
        $existingLines = Get-Content -Path $destLang
        $existingKeys = $existingLines | ForEach-Object {
            if ($_ -match "^([^=]+)=") { $Matches[1] }
        }
        $linesToAdd = @()
        foreach ($line in $newLines) {
            if ($line -match "^([^=]+)=") {
                if ($existingKeys -notcontains $Matches[1]) {
                    $linesToAdd += $line
                }
            }
        }
        if ($linesToAdd.Count -gt 0) {
            Add-Content -Path $destLang -Value $linesToAdd
        }
    }

    # ---- item_texture.json: merge into texture_data, no overwrite of existing entries ----
    $rpTexturesRootDir = Join-Path $rpPath "textures"
    New-Item -ItemType Directory -Force -Path $rpTexturesRootDir | Out-Null
    $destTexture = Join-Path $rpTexturesRootDir "item_texture.json"
    $sourceTextureContent = Get-Content -Path (Join-Path $assetsDir "item_texture.json") -Raw
    $sourceTextureContent = Replace-ItemPlaceholders $sourceTextureContent
    $sourceTextureObj = $sourceTextureContent | ConvertFrom-Json

    if (-not (Test-Path $destTexture)) {
        Set-Content -Path $destTexture -Value $sourceTextureContent
    } else {
        $existingTextureObj = Get-Content -Path $destTexture -Raw | ConvertFrom-Json

        $existingDataHash = @{}
        $existingTextureObj.texture_data.PSObject.Properties | ForEach-Object {
            $existingDataHash[$_.Name] = $_.Value
        }

        $sourceTextureObj.texture_data.PSObject.Properties | ForEach-Object {
            if (-not $existingDataHash.ContainsKey($_.Name)) {
                $existingDataHash[$_.Name] = $_.Value
            }
        }

        $mergedObj = @{
            resource_pack_name = $existingTextureObj.resource_pack_name
            texture_name = $existingTextureObj.texture_name
            texture_data = $existingDataHash
        }

        $mergedJson = $mergedObj | ConvertTo-Json -Depth 10
        Set-Content -Path $destTexture -Value $mergedJson
    }

    Write-Host ""
    Write-Host "Item '$displayName' ($identifier) added to project '$baseName'." -ForegroundColor Green
    Write-Host "  $bpItemsDir\$itemShortName.json"
    Write-Host "  $rpItemTexturesDir\$itemShortName.png"
    Write-Host "  $destLang (merged)"
    Write-Host "  $destTexture (merged)"

    exit
}

if ($Command -eq "apikey") {
    if ([string]::IsNullOrWhiteSpace($Extra)) {
        Write-Host "Usage: cadon apikey <your-cfcore-api-key>" -ForegroundColor Red
        Write-Host "Get a free key at: https://console.curseforge.com" -ForegroundColor Yellow
        exit
    }

    $config = Load-Config
    if ($null -eq $config) {
        Write-Host "config.json not found. Run install.bat first on this device." -ForegroundColor Red
        exit
    }

    $config | Add-Member -NotePropertyName "curseforgeApiKey" -NotePropertyValue $Extra -Force
    Save-Config $config

    Write-Host "CurseForge API key saved." -ForegroundColor Green
    exit
}

if ($Command -eq "projectid") {
    $modId = $Extra
    $fileId = $Extra2  

    if ([string]::IsNullOrWhiteSpace($modId) -or [string]::IsNullOrWhiteSpace($fileId)) {
        Write-Host "Usage: cadon projectid <modId> <fileId>" -ForegroundColor Red
        Write-Host "Find these on the CurseForge project page, under 'About Project'." -ForegroundColor Yellow
        exit
    }

    $cfApiKey = $config.curseforgeApiKey
    if ([string]::IsNullOrWhiteSpace($cfApiKey)) {
        Write-Host "No CurseForge API key configured." -ForegroundColor Red
        Write-Host "Run: cadon apikey <your-key>" -ForegroundColor Yellow
        exit
    }

    $cfHeaders = @{
        "Accept" = "application/json"
        "x-api-key" = $cfApiKey
    }

    Write-Host "Requesting direct download URL for mod $modId, file $fileId..." -ForegroundColor Cyan

    try {
        $downloadUrlResponse = Invoke-RestMethod -Uri "https://api.curseforge.com/v1/mods/$modId/files/$fileId/download-url" -Headers $cfHeaders -ErrorAction Stop
    } catch {
        Write-Host "Failed to get download URL from CurseForge API." -ForegroundColor Red
        Write-Host $_.Exception.Message -ForegroundColor Yellow
        exit
    }

    $directDownloadUrl = $downloadUrlResponse.data

    if ([string]::IsNullOrWhiteSpace($directDownloadUrl)) {
        Write-Host "CurseForge API did not return a valid download URL." -ForegroundColor Red
        exit
    }

    
    Write-Host "Downloading addon..." -ForegroundColor Cyan

    $tempDir = Join-Path $env:TEMP "cadon_update_$(Get-Random)"
    New-Item -ItemType Directory -Force -Path $tempDir | Out-Null
    $downloadedFile = Join-Path $tempDir "addon.mcaddon"

    try {
        Invoke-WebRequest -Uri $directDownloadUrl -OutFile $downloadedFile -ErrorAction Stop
    } catch {
        Write-Host "Failed to download the file from CDN." -ForegroundColor Red
        Write-Host $_.Exception.Message -ForegroundColor Yellow
        Remove-Item -Recurse -Force $tempDir -ErrorAction SilentlyContinue
        exit
    }

    $zipFile = Join-Path $tempDir "addon.zip"
    Copy-Item -Path $downloadedFile -Destination $zipFile

    $extractDir = Join-Path $tempDir "extracted"
    Expand-Archive -Path $zipFile -DestinationPath $extractDir -Force

    $manifestFiles = Get-ChildItem -Path $extractDir -Filter "manifest.json" -Recurse

    if ($manifestFiles.Count -eq 0) {
        Write-Host "No manifest.json found in the downloaded file." -ForegroundColor Red
        Remove-Item -Recurse -Force $tempDir -ErrorAction SilentlyContinue
        exit
    }

    $foundRP = $null
    $foundBP = $null

    foreach ($manifestFile in $manifestFiles) {
        $manifest = Get-Content $manifestFile.FullName -Raw | ConvertFrom-Json
        $packFolder = $manifestFile.Directory.FullName

        foreach ($module in $manifest.modules) {
            if ($module.type -eq "resources") { $foundRP = $packFolder }
            if ($module.type -eq "data" -or $module.type -eq "script") { $foundBP = $packFolder }
        }
    }

    if ($null -eq $foundRP -or $null -eq $foundBP) {
        Write-Host "Could not find both a Resource Pack and a Behavior Pack inside the downloaded addon." -ForegroundColor Red
        Remove-Item -Recurse -Force $tempDir -ErrorAction SilentlyContinue
        exit
    }

    $rpManifest = Get-Content (Join-Path $foundRP "manifest.json") -Raw | ConvertFrom-Json
    $projectDisplayName = $rpManifest.header.name -replace " RP$", ""
    $safeName = $projectDisplayName -replace '[\\/:*?"<>|]', ''

    $destRP = Join-Path $comMojang "development_resource_packs\$safeName RP"
    $destBP = Join-Path $comMojang "development_behavior_packs\$safeName BP"

    Write-Host "Updating project: $projectDisplayName" -ForegroundColor Green

    if (Test-Path $destRP) { Remove-Item -Recurse -Force $destRP }
    if (Test-Path $destBP) { Remove-Item -Recurse -Force $destBP }

    Copy-Item -Path $foundRP -Destination $destRP -Recurse
    Copy-Item -Path $foundBP -Destination $destBP -Recurse

    Remove-Item -Recurse -Force $tempDir -ErrorAction SilentlyContinue

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
    Set-Content -Path $workspacePath -Value ($workspaceObject | ConvertTo-Json -Depth 5)

    Write-Host ""
    Write-Host "Done! Project '$projectDisplayName' has been updated from the published version." -ForegroundColor Green
    Write-Host "  RP: $destRP"
    Write-Host "  BP: $destBP"

    if (-not [string]::IsNullOrWhiteSpace($editorCommand)) {
        Write-Host "Opening workspace in editor..." -ForegroundColor Cyan
        try {
            Start-Process -FilePath $editorCommand -ArgumentList "`"$workspacePath`""
        } catch {
            Write-Host "Could not launch editor with command: $editorCommand" -ForegroundColor Red
        }
    }

    exit
}

# ---- Default: create a new project ----
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

if (-not [string]::IsNullOrWhiteSpace($editorCommand)) {
    Write-Host "Opening workspace in editor..." -ForegroundColor Cyan
    try {
        Start-Process -FilePath $editorCommand -ArgumentList "`"$workspacePath`""
    } catch {
        Write-Host "Could not launch editor with command: $editorCommand" -ForegroundColor Red
        Write-Host "You can open the workspace manually: $workspacePath" -ForegroundColor Yellow
    }
}