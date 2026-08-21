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

# ---- Subcommand: cadon item [chestplate|helmet|leggings|boots] ----
if ($Command -eq "item") {
    $ARMOR_TYPES = @("chestplate", "helmet", "leggings", "boots")
    $armorType = $null

    if (-not [string]::IsNullOrWhiteSpace($Extra)) {
        if ($ARMOR_TYPES -contains $Extra) {
            $armorType = $Extra
        } else {
            Write-Host "Unknown item type: $Extra" -ForegroundColor Red
            Write-Host "Valid types: chestplate, helmet, leggings, boots (or leave empty for a plain item)" -ForegroundColor Yellow
            exit
        }
    }

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

    $itemLabel = if ($armorType) { $armorType } else { "item" }
    $displayName = Read-Host "Enter display name (e.g. Magic Wand)"
    if ([string]::IsNullOrWhiteSpace($displayName)) {
        Write-Host "Display name cannot be empty." -ForegroundColor Red
        exit
    }

    $identifier = Read-Host "Enter identifier (e.g. myaddon:magic_wand)"
    if ($identifier -notmatch "^[a-z0-9_]+:[a-z0-9_]+$") {
        Write-Host "Identifier must be in the format namespace:name (lowercase letters, numbers, underscores only)." -ForegroundColor Red
        exit
    }

    $itemShortName = $identifier.Split(":")[1]

    $assetsSubfolder = if ($armorType) { $armorType } else { "items" }
    $assetsDir = Join-Path $templateRoot "assets\$assetsSubfolder"
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

    Write-Host "Creating $itemLabel files..." -ForegroundColor Cyan

    # ---- cadon.item.json -> BP/items/<name>.json ----
    $bpItemsDir = Join-Path $bpPath "items"
    New-Item -ItemType Directory -Force -Path $bpItemsDir | Out-Null
    $itemJsonContent = Get-Content -Path (Join-Path $assetsDir "cadon.item.json") -Raw
    $itemJsonContent = Replace-ItemPlaceholders $itemJsonContent
    Set-Content -Path (Join-Path $bpItemsDir "$itemShortName.json") -Value $itemJsonContent -NoNewline

    # ---- Icon texture: RP/textures/items ----
    $rpItemTexturesDir = Join-Path $rpPath "textures\items"
    New-Item -ItemType Directory -Force -Path $rpItemTexturesDir | Out-Null

    if ($armorType) {
        # armor pakai cadon_icon.png sebagai sumber icon
        Copy-Item -Path (Join-Path $assetsDir "cadon_icon.png") -Destination (Join-Path $rpItemTexturesDir "$itemShortName.png")
    } else {
        Copy-Item -Path (Join-Path $assetsDir "cadon.png") -Destination (Join-Path $rpItemTexturesDir "$itemShortName.png")
    }

    # ---- Attachable-only files (chestplate/helmet/leggings/boots) ----
    if ($armorType) {
        # cadon.attachable.json -> RP/attachables
        $rpAttachablesDir = Join-Path $rpPath "attachables"
        New-Item -ItemType Directory -Force -Path $rpAttachablesDir | Out-Null
        $attachableContent = Get-Content -Path (Join-Path $assetsDir "cadon.attachable.json") -Raw
        $attachableContent = Replace-ItemPlaceholders $attachableContent
        Set-Content -Path (Join-Path $rpAttachablesDir "$itemShortName.json") -Value $attachableContent -NoNewline

        # cadon.geo.json -> RP/models/entity/attachable
        $rpAttachableGeoDir = Join-Path $rpPath "models\entity\attachable"
        New-Item -ItemType Directory -Force -Path $rpAttachableGeoDir | Out-Null
        $geoContent = Get-Content -Path (Join-Path $assetsDir "cadon.geo.json") -Raw
        $geoContent = Replace-ItemPlaceholders $geoContent
        Set-Content -Path (Join-Path $rpAttachableGeoDir "$itemShortName.geo.json") -Value $geoContent -NoNewline

        # cadon.png -> RP/textures/entity/attachable (worn/equipped texture)
        $rpAttachableTexturesDir = Join-Path $rpPath "textures\entity\attachable"
        New-Item -ItemType Directory -Force -Path $rpAttachableTexturesDir | Out-Null
        Copy-Item -Path (Join-Path $assetsDir "cadon.png") -Destination (Join-Path $rpAttachableTexturesDir "$itemShortName.png")
    }

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
    Write-Host "$itemLabel '$displayName' ($identifier) added to project '$baseName'." -ForegroundColor Green
    Write-Host "  $bpItemsDir\$itemShortName.json"
    if ($armorType) {
        Write-Host "  $rpAttachablesDir\$itemShortName.json"
        Write-Host "  $rpAttachableGeoDir\$itemShortName.geo.json"
        Write-Host "  $rpAttachableTexturesDir\$itemShortName.png"
    }
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

# ---- Subcommand: cadon publish ----
if ($Command -eq "publish") {
    $currentDir = (Get-Location).Path
    $manifestPath = Join-Path $currentDir "manifest.json"

    if (-not (Test-Path $manifestPath)) {
        Write-Host "No manifest.json found in the current directory." -ForegroundColor Red
        Write-Host "Run 'cadon publish' from inside your project's RP or BP folder." -ForegroundColor Yellow
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

    # ---- Get or ask for publish output path (saved to config) ----
    $publishPath = $config.publishPath
    if ([string]::IsNullOrWhiteSpace($publishPath) -or -not (Test-Path $publishPath)) {
        $publishPath = Read-Host "Enter the folder where published addons should be saved (e.g. D:\Projects-Publish)"
        if ([string]::IsNullOrWhiteSpace($publishPath)) {
            Write-Host "Publish folder cannot be empty." -ForegroundColor Red
            exit
        }
        New-Item -ItemType Directory -Force -Path $publishPath | Out-Null

        $config | Add-Member -NotePropertyName "publishPath" -NotePropertyValue $publishPath -Force
        Save-Config $config
        Write-Host "Publish folder saved for future use. You can change it anytime in publishPath inside config.json" -ForegroundColor Green
    }

    # ---- Ask for version ----
    $version = Read-Host "Enter version (e.g. 1.0.0)"
    if ([string]::IsNullOrWhiteSpace($version)) {
        Write-Host "Version cannot be empty." -ForegroundColor Red
        exit
    }
    $safeVersion = $version -replace '[\\/:*?"<>|]', ''

    $safeBaseName = $baseName -replace '[\\/:*?"<>|]', ''
    $projectPublishRoot = Join-Path $publishPath "Minecraft - $safeBaseName"
    $versionFolder = Join-Path $projectPublishRoot $safeVersion

    if (Test-Path $versionFolder) {
        Write-Host "This version already exists at:" -ForegroundColor Yellow
        Write-Host "  $versionFolder" -ForegroundColor Yellow
        $confirm = Read-Host "Overwrite? (y/n)"
        if ($confirm -ne "y") {
            Write-Host "Publish canceled." -ForegroundColor Red
            exit
        }
        Remove-Item -Recurse -Force $versionFolder
    }

    New-Item -ItemType Directory -Force -Path $versionFolder | Out-Null

    Write-Host "Copying RP and BP..." -ForegroundColor Cyan
    $publishRP = Join-Path $versionFolder "$safeBaseName RP"
    $publishBP = Join-Path $versionFolder "$safeBaseName BP"
    Copy-Item -Path $rpPath -Destination $publishRP -Recurse
    Copy-Item -Path $bpPath -Destination $publishBP -Recurse

    Write-Host "Building .mcaddon..." -ForegroundColor Cyan

    $stagingDir = Join-Path $env:TEMP "cadon_publish_$(Get-Random)"
    New-Item -ItemType Directory -Force -Path $stagingDir | Out-Null
    Copy-Item -Path $publishRP -Destination (Join-Path $stagingDir "$safeBaseName RP") -Recurse
    Copy-Item -Path $publishBP -Destination (Join-Path $stagingDir "$safeBaseName BP") -Recurse

    $zipPath = Join-Path $versionFolder "$safeBaseName-$safeVersion.zip"
    Compress-Archive -Path "$stagingDir\*" -DestinationPath $zipPath -Force

    $mcaddonPath = Join-Path $versionFolder "$safeBaseName-$safeVersion.mcaddon"
    Rename-Item -Path $zipPath -NewName (Split-Path $mcaddonPath -Leaf)

    Remove-Item -Recurse -Force $stagingDir -ErrorAction SilentlyContinue

    Write-Host ""
    Write-Host "Done! Project '$baseName' version $version has been published:" -ForegroundColor Green
    Write-Host "  $versionFolder"
    Write-Host "    - $safeBaseName RP\"
    Write-Host "    - $safeBaseName BP\"
    Write-Host "    - $safeBaseName-$safeVersion.mcaddon"

    exit
}

# ---- Subcommand: cadon uninstall ----
if ($Command -eq "uninstall") {
    $installRoot = Split-Path $scriptDir -Parent

    Write-Host "This will completely remove Cadon:" -ForegroundColor Yellow
    Write-Host "  $installRoot" -ForegroundColor Yellow
    Write-Host "And remove it from your PATH." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Note: this only removes the Cadon tool itself." -ForegroundColor DarkGray
    Write-Host "Projects already created in com.mojang and your Projects folder will NOT be touched." -ForegroundColor DarkGray
    Write-Host ""

    $confirm = Read-Host "Are you sure you want to uninstall Cadon? (y/n)"
    if ($confirm -ne "y") {
        Write-Host "Uninstall canceled." -ForegroundColor Red
        exit
    }

    # Remove from PATH first, while we still can
    $currentPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $newPath = ($currentPath -split ";" | Where-Object { $_ -ne $scriptDir }) -join ";"
    [Environment]::SetEnvironmentVariable("Path", $newPath, "User")
    Write-Host "Removed from PATH." -ForegroundColor Green

    # Spawn a separate process to delete the install folder after this script exits
    $deleteCommand = "Start-Sleep -Seconds 2; Remove-Item -Recurse -Force '$installRoot'"
    Start-Process -FilePath "powershell" -ArgumentList "-WindowStyle Hidden -Command `"$deleteCommand`"" -WindowStyle Hidden

    Write-Host ""
    Write-Host "Cadon has been uninstalled." -ForegroundColor Green
    Write-Host "The install folder will be removed in a moment." -ForegroundColor DarkGray
    Write-Host "Close and reopen Command Prompt to complete the removal from PATH." -ForegroundColor Yellow

    exit
}

# ---- Subcommand: cadon project list ----
if ($Command -eq "project" -and $Extra -eq "list") {
    $rpRoot = Join-Path $comMojang "development_resource_packs"
    $bpRoot = Join-Path $comMojang "development_behavior_packs"

    $rpFolders = @()
    if (Test-Path $rpRoot) {
        $rpFolders = Get-ChildItem -Path $rpRoot -Directory | Where-Object { $_.Name -match "^(.+) RP$" } | ForEach-Object { $Matches[1] }
    }

    $bpFolders = @()
    if (Test-Path $bpRoot) {
        $bpFolders = Get-ChildItem -Path $bpRoot -Directory | Where-Object { $_.Name -match "^(.+) BP$" } | ForEach-Object { $Matches[1] }
    }

    $allProjectNames = ($rpFolders + $bpFolders) | Select-Object -Unique | Sort-Object

    if ($allProjectNames.Count -eq 0) {
        Write-Host "No projects found." -ForegroundColor Yellow
        exit
    }

    Write-Host ""
    Write-Host "Projects in com.mojang:" -ForegroundColor Cyan
    Write-Host ""

    foreach ($name in $allProjectNames) {
        $hasRP = $rpFolders -contains $name
        $hasBP = $bpFolders -contains $name

        $status = ""
        if ($hasRP -and $hasBP) {
            $status = ""
        } elseif ($hasRP -and -not $hasBP) {
            $status = "missing BP"
        } elseif (-not $hasRP -and $hasBP) {
            $status = "missing RP"
        }

        if ($hasRP -and $hasBP) {
            Write-Host "  - $name" -ForegroundColor White
        } else {
            Write-Host "  - $name " -ForegroundColor White -NoNewline
            Write-Host "($status)" -ForegroundColor Red
        }
    }

    Write-Host ""
    Write-Host "Total: $($allProjectNames.Count) project(s)" -ForegroundColor DarkGray

    exit
}

# ---- Subcommand: cadon delete <project_name> ----
if ($Command -eq "delete") {
    if ([string]::IsNullOrWhiteSpace($Extra)) {
        Write-Host "Usage: cadon delete <project_name>" -ForegroundColor Red
        exit
    }

    $targetName = $Extra
    $destRP = Join-Path $comMojang "development_resource_packs\$targetName RP"
    $destBP = Join-Path $comMojang "development_behavior_packs\$targetName BP"

    $rpExists = Test-Path $destRP
    $bpExists = Test-Path $destBP

    if (-not $rpExists -and -not $bpExists) {
        Write-Host "No project named '$targetName' was found." -ForegroundColor Red
        exit
    }

    Write-Host "This will permanently delete:" -ForegroundColor Yellow
    if ($rpExists) { Write-Host "  $destRP" -ForegroundColor Yellow }
    if ($bpExists) { Write-Host "  $destBP" -ForegroundColor Yellow }
    Write-Host ""

    $confirm = Read-Host "Are you sure? (y/n)"
    if ($confirm -ne "y") {
        Write-Host "Delete canceled." -ForegroundColor Red
        exit
    }

    if ($rpExists) {
        Remove-Item -Recurse -Force $destRP
        Write-Host "Removed RP." -ForegroundColor Green
    }
    if ($bpExists) {
        Remove-Item -Recurse -Force $destBP
        Write-Host "Removed BP." -ForegroundColor Green
    }

    $safeName = $targetName -replace '[\\/:*?"<>|]', ''
    $workspacePath = Join-Path $templateRoot "Projects\$safeName.code-workspace"
    if (Test-Path $workspacePath) {
        Remove-Item -Force $workspacePath
        Write-Host "Removed workspace file." -ForegroundColor Green
    }

    Write-Host ""
    Write-Host "Project '$targetName' has been deleted." -ForegroundColor Green

    exit
}

# ---- Subcommand: cadon help ----
if ($Command -eq "help") {
    Write-Host ""
    Write-Host "=== Cadon - Bedrock Addon Simplistic ===" -ForegroundColor Cyan
    Write-Host ""

    Write-Host "PROJECT CREATION" -ForegroundColor Yellow
    Write-Host "  cadon <project_name>" -ForegroundColor White
    Write-Host "      Create a new project (minimal copy: manifest, scripts, pack_icon only)." -ForegroundColor DarkGray
    Write-Host "      Example: cadon MyAddon" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  cadon <project_name> *" -ForegroundColor White
    Write-Host "      Create a new project with the full template (all folders)." -ForegroundColor DarkGray
    Write-Host "      Example: cadon MyAddon *" -ForegroundColor DarkGray
    Write-Host ""

    Write-Host "PROJECT MANAGEMENT" -ForegroundColor Yellow
    Write-Host "  cadon project list" -ForegroundColor White
    Write-Host "      List all projects currently in com.mojang." -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  cadon delete <project_name>" -ForegroundColor White
    Write-Host "      Permanently delete a project's RP and BP." -ForegroundColor DarkGray
    Write-Host "      Example: cadon delete MyAddon" -ForegroundColor DarkGray
    Write-Host ""

    Write-Host "ADDING CONTENT (run inside a project's RP or BP folder)" -ForegroundColor Yellow
    Write-Host "  cadon entity" -ForegroundColor White
    Write-Host "      Add a new entity to the current project. Asks for display name and identifier." -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  cadon item" -ForegroundColor White
    Write-Host "      Add a new item to the current project. Asks for display name and identifier." -ForegroundColor DarkGray
    Write-Host ""

    Write-Host "PUBLISHING" -ForegroundColor Yellow
    Write-Host "  cadon publish" -ForegroundColor White
    Write-Host "      Package the current project's RP and BP into a versioned folder and a .mcaddon file." -ForegroundColor DarkGray
    Write-Host "      Run inside a project's RP or BP folder. Asks for version number." -ForegroundColor DarkGray
    Write-Host ""

    Write-Host "DOWNLOADING FROM CURSEFORGE" -ForegroundColor Yellow
    Write-Host "  cadon apikey <key>" -ForegroundColor White
    Write-Host "      Save your CurseForge (CFCore) API key. Get one at console.curseforge.com" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  cadon projectid <modId> <fileId>" -ForegroundColor White
    Write-Host "      Download and install/update an addon directly from CurseForge." -ForegroundColor DarkGray
    Write-Host "      Find modId and fileId on the addon's CurseForge project page." -ForegroundColor DarkGray
    Write-Host "      Example: cadon projectid 123456 8265237" -ForegroundColor DarkGray
    Write-Host ""

    Write-Host "SETTINGS" -ForegroundColor Yellow
    Write-Host "  cadon code <editor-command-or-path>" -ForegroundColor White
    Write-Host "      Set the editor used to open new project workspaces." -ForegroundColor DarkGray
    Write-Host "      Example: cadon code code" -ForegroundColor DarkGray
    Write-Host "      (Specific to VS Code)" -ForegroundColor DarkGray
    Write-Host ""

    Write-Host "MAINTENANCE" -ForegroundColor Yellow
    Write-Host "  cadon uninstall" -ForegroundColor White
    Write-Host "      Completely remove Cadon from this device. Projects are not affected." -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  cadon help" -ForegroundColor White
    Write-Host "      Show this help message." -ForegroundColor DarkGray
    Write-Host ""

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

# Confirm
$modeLabel = if ($fullCopy) { "full template (all folders)" } else { "minimal template (manifest, scripts, pack_icon only)" }

Write-Host ""
Write-Host "This will create project '$projectName' using the $modeLabel." -ForegroundColor Yellow
Write-Host "  RP: $destRP" -ForegroundColor Yellow
Write-Host "  BP: $destBP" -ForegroundColor Yellow
Write-Host ""
Write-Host "Press Enter to continue, or type 'n' to cancel." -ForegroundColor Cyan
$confirm = Read-Host

if ($confirm -eq "n") {
    Write-Host "Project creation canceled." -ForegroundColor Red
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